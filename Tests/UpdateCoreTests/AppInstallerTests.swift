import Foundation
import Testing
@testable import UpdateCore

private func installRelease(_ version: String = "1.2.0", package: Bool = true) -> AppRelease {
    AppRelease(version: ReleaseVersion(version)!, isPrerelease: true, notes: "",
               pageURL: ReleaseClient.releasesURL.appendingPathComponent("tag/v\(version)"),
               downloadURL: package ? ReleaseClient.releasesURL.appendingPathComponent("download/v\(version)/MacPower-\(version)-arm64.zip") : nil)
}

@MainActor struct UpdateInstallationTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "MacPower.InstallTests.\(UUID().uuidString)")! }
    private func settle(_ predicate: () -> Bool) async {
        for _ in 0..<1000 { if predicate() { return }; await Task.yield() }
        Issue.record("Update operation did not settle")
    }

    @Test func updateRequiresClickAndOnlyRestartsAfterHandoff() async {
        let preferences = defaults()
        var fetched = 0, installed = 0, restarted = 0
        var resume: CheckedContinuation<Void, Never>?
        let remote = installRelease()
        let store = UpdateStore(currentVersion: "1.1.0", defaults: preferences, fetch: { _ in fetched += 1; return remote }, install: { release, progress in
            #expect(release == remote)
            installed += 1; progress(.verifying)
            await withCheckedContinuation { resume = $0 }
            progress(.restarting)
        })
        store.onRestartRequested = { restarted += 1 }
        store.automaticChecks = true
        await settle { store.state == .available(remote) }
        #expect(installed == 0)
        store.installUpdate(); store.installUpdate()
        await settle { resume != nil }
        store.check()
        #expect(installed == 1 && fetched == 1 && restarted == 0)
        #expect(store.installationState == .verifying)
        resume?.resume()
        await settle { restarted == 1 }
        #expect(store.installationState == .restarting)
        store.cancel()
        #expect(store.installationState == .restarting)
    }

    @Test func failureKeepsReleaseAndPreferencesAndCanRetry() async {
        let preferences = defaults()
        let original = Data([1, 2, 3])
        preferences.set(original, forKey: "preferences.v1")
        let remote = installRelease()
        var attempts = 0, restarted = 0
        let store = UpdateStore(currentVersion: "1.1.0", defaults: preferences, fetch: { _ in remote }, install: { _, progress in
            attempts += 1
            if attempts == 1 { throw AppInstallError.failed("文件校验未通过，旧版本未更改。") }
            progress(.verifying); progress(.restarting)
        })
        store.onRestartRequested = { restarted += 1 }
        store.check(); await settle { store.state == .available(remote) }
        store.installUpdate(); await settle { !store.installationState.isBusy }
        #expect(store.state == .available(remote))
        #expect(store.installationState == .failed("文件校验未通过，旧版本未更改。"))
        #expect(preferences.data(forKey: "preferences.v1") == original && restarted == 0)
        store.installUpdate(); await settle { restarted == 1 }
        #expect(attempts == 2)
    }

    @Test func missingPackageAndUpToDateVersionNeverInstall() async {
        for hasPackage in [false, true] {
            var attempts = 0
            let remote = installRelease(package: hasPackage)
            let store = UpdateStore(currentVersion: hasPackage ? "1.2.0" : "1.1.0", defaults: defaults(), fetch: { _ in remote }, install: { _, _ in attempts += 1 })
            store.check(); await settle { store.state != .checking }
            store.installUpdate(); await Task.yield()
            #expect(attempts == 0)
            if !hasPackage { #expect(store.installationState == .failed(AppInstallError.noPackage.localizedDescription)) }
        }
    }

    @Test func cancellingBeforeHandoffNeverRestarts() async {
        var entered = false, restarted = 0
        let remote = installRelease()
        let store = UpdateStore(currentVersion: "1.1.0", defaults: defaults(), fetch: { _ in remote }, install: { _, _ in
            entered = true
            try await Task.sleep(nanoseconds: 10_000_000_000)
        })
        store.onRestartRequested = { restarted += 1 }
        store.check(); await settle { store.state == .available(remote) }
        store.installUpdate(); await settle { entered }
        store.cancel()
        for _ in 0..<10 { await Task.yield() }
        #expect(store.installationState == .idle && restarted == 0)
    }
}

@MainActor struct AppInstallerTests {
    @Test func onlyTrustedMatchingPackageIsAccepted() throws {
        try AppInstaller.validate(installRelease()) // GitHub's preview flag is supported.
        let remote = installRelease()
        let foreign = AppRelease(version: remote.version, isPrerelease: true, notes: "", pageURL: remote.pageURL,
                                 downloadURL: URL(string: "https://example.com/MacPower.zip"))
        #expect(throws: AppInstallError.noPackage) { try AppInstaller.validate(foreign) }
        #expect(throws: AppInstallError.noPackage) { try AppInstaller.validate(installRelease(package: false)) }
        #expect(throws: AppInstallError.unsupportedVersion) { try AppInstaller.validate(installRelease("1.2.0-beta")) }
    }

    private func fixture(_ script: String) throws -> (URL, URL, URL, UserDefaults) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPower-InstallerTest-\(UUID().uuidString)")
        let bundle = root.appendingPathComponent("MacPower.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let installer = root.appendingPathComponent("installer.sh")
        try script.write(to: installer, atomically: true, encoding: .utf8)
        return (root, bundle, installer, UserDefaults(suiteName: "MacPower.WorkerTest.\(UUID().uuidString)")!)
    }

    @Test func workerSurvivesHandoffWithoutOutputPipe() async throws {
        let (root, bundle, script, preferences) = try fixture("""
        print downloading > "$MACPOWER_UPDATE_EVENT_FILE"
        /bin/sleep 0.25
        print verifying > "$MACPOWER_UPDATE_EVENT_FILE"
        /bin/sleep 0.25
        print restarting > "$MACPOWER_UPDATE_EVENT_FILE"
        /bin/sleep 0.4
        print completed > "$MACPOWER_UPDATE_EVENT_FILE"
        print 'Worker survived the handoff'
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Updates")
        var phases: [UpdateInstallPhase] = []
        var installer: AppInstaller? = AppInstaller(bundleURL: bundle, scriptURL: script, directory: directory, defaults: preferences)
        try await installer!.install(installRelease()) { phases.append($0) }
        #expect(phases == [.downloading, .verifying, .restarting])
        let pending = try #require(preferences.dictionary(forKey: AppInstaller.pendingKey))
        let session = URL(fileURLWithPath: try #require(pending["directory"] as? String))
        installer?.cancel() // Handoff must detach the worker from app cancellation.
        installer = nil
        for _ in 0..<100 {
            if (try? String(contentsOf: session.appendingPathComponent("event"), encoding: .utf8)) == "completed\n" { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(try String(contentsOf: session.appendingPathComponent("install.log"), encoding: .utf8).contains("Worker survived the handoff"))
        let restarted = AppInstaller(bundleURL: bundle, scriptURL: script, directory: directory, defaults: preferences)
        #expect(restarted.recoveredFailure(currentVersion: "1.2.0") == nil)
        #expect(preferences.dictionary(forKey: AppInstaller.pendingKey) == nil)
    }

    @Test func workerFailureNeverRequestsRestart() async throws {
        let (root, bundle, script, preferences) = try fixture("""
        print downloading > "$MACPOWER_UPDATE_EVENT_FILE"
        print -u2 'MacPower: SHA-256 校验失败，旧版未更改。'
        print failed > "$MACPOWER_UPDATE_EVENT_FILE"
        exit 1
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        var phases: [UpdateInstallPhase] = []
        let installer = AppInstaller(bundleURL: bundle, scriptURL: script, directory: root.appendingPathComponent("Updates"), defaults: preferences)
        do { try await installer.install(installRelease()) { phases.append($0) }; Issue.record("Expected install failure") }
        catch { #expect(error as? AppInstallError == .failed("SHA-256 校验失败，旧版未更改。")) }
        #expect(!phases.contains(.restarting))
        #expect(preferences.dictionary(forKey: AppInstaller.pendingKey) == nil)
    }

    @Test func foreignRecoveryPathDoesNotDeleteFiles() throws {
        let (root, bundle, script, preferences) = try fixture("")
        defer { try? FileManager.default.removeItem(at: root) }
        preferences.set(["directory": root.path, "version": "1.2.0"], forKey: AppInstaller.pendingKey)
        let installer = AppInstaller(bundleURL: bundle, scriptURL: script, directory: root.appendingPathComponent("Updates"), defaults: preferences)
        #expect(installer.recoveredFailure(currentVersion: "1.1.0") == nil)
        #expect(FileManager.default.fileExists(atPath: script.path))
    }
}
