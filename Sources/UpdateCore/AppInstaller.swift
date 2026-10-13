import Foundation
import Darwin

public enum UpdateInstallPhase: String, Equatable, Sendable {
    case downloading, verifying, restarting
}

public enum UpdateInstallationState: Equatable {
    case idle, downloading, verifying, restarting, failed(String)
    public var isBusy: Bool {
        switch self { case .downloading, .verifying, .restarting: return true; default: return false }
    }
}

public enum AppInstallError: Error, LocalizedError, Equatable {
    case noPackage, unsupportedVersion, missingInstaller, invalidLocation, notWritable, failed(String)
    public var errorDescription: String? {
        switch self {
        case .noPackage: return "此版本没有适合当前 Mac 的更新文件。"
        case .unsupportedVersion: return "此版本暂不支持自动安装，请选择其他发布版本。"
        case .missingInstaller: return "应用缺少更新组件，请重新安装完整的 MacPower 应用。"
        case .invalidLocation: return "请将应用命名为 MacPower.app 并放入“应用程序”后再更新。"
        case .notWritable: return "当前安装位置不可写，请将 MacPower 放入个人“应用程序”目录后再更新。"
        case .failed(let message): return message
        }
    }
}

/// Runs the bundled, signed installer. Its output goes to a private file rather
/// than a pipe so it can survive the parent app exiting during replacement.
@MainActor public final class AppInstaller {
    static let pendingKey = "updates.pendingInstallation"
    private let bundleURL: URL
    private let scriptURL: URL?
    private let directory: URL
    private let defaults: UserDefaults
    private var activeProcess: Process?

    public init(bundleURL: URL = Bundle.main.bundleURL,
                scriptURL: URL? = Bundle.main.url(forResource: "InstallUpdate", withExtension: "sh"),
                directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.bundleURL = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        self.scriptURL = scriptURL
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPower/Updates", isDirectory: true)
        self.defaults = defaults
    }

    public static func validate(_ release: AppRelease) throws {
        guard !release.version.isPrerelease, release.version.number.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else {
            throw AppInstallError.unsupportedVersion
        }
        let expected = ReleaseClient.releasesURL.appendingPathComponent("download/v\(release.version.number)/MacPower-\(release.version.number)-arm64.zip")
        guard release.downloadURL == expected else { throw AppInstallError.noPackage }
    }

    public func install(_ release: AppRelease, progress: @escaping @MainActor (UpdateInstallPhase) -> Void) async throws {
        try Self.validate(release)
        let manager = FileManager.default
        guard bundleURL.lastPathComponent == "MacPower.app" else { throw AppInstallError.invalidLocation }
        guard manager.isWritableFile(atPath: bundleURL.path), manager.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path) else {
            throw AppInstallError.notWritable
        }
        guard let scriptURL, manager.fileExists(atPath: scriptURL.path) else { throw AppInstallError.missingInstaller }
        cleanupCompletedSessions()
        let session = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: session, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = session.appendingPathComponent("install.sh")
        try manager.copyItem(at: scriptURL, to: script)
        let event = session.appendingPathComponent("event")
        let log = session.appendingPathComponent("install.log")
        manager.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: log)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", script.path, "--version", release.version.number,
                             "--dir", bundleURL.deletingLastPathComponent().path,
                             "--wait-pid", String(ProcessInfo.processInfo.processIdentifier)]
        var environment = ProcessInfo.processInfo.environment
        environment["MACPOWER_UPDATE_EVENT_FILE"] = event.path
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output; process.standardError = output
        defaults.set(["directory": session.path, "version": release.version.number, "bundle": bundleURL.path], forKey: Self.pendingKey)
        do { try process.run() }
        catch {
            try? output.close(); defaults.removeObject(forKey: Self.pendingKey)
            try? manager.removeItem(at: session)
            throw AppInstallError.failed("无法启动更新安装，请稍后重试。")
        }
        activeProcess = process
        try? output.close()
        var previous: UpdateInstallPhase?
        do {
            while process.isRunning {
                try Task.checkCancellation()
                if let text = try? String(contentsOf: event, encoding: .utf8),
                   let phase = UpdateInstallPhase(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines)), phase != previous {
                    previous = phase
                    // The worker now waits for this app's PID to disappear. Ownership
                    // passes to the worker, which completes or rolls back independently.
                    if phase == .restarting { activeProcess = nil; progress(phase); return }
                    progress(phase)
                }
                try await Task.sleep(nanoseconds: 150_000_000)
            }
        } catch {
            if process.isRunning { process.terminate() }
            activeProcess = nil
            defaults.removeObject(forKey: Self.pendingKey)
            throw error
        }
        defaults.removeObject(forKey: Self.pendingKey)
        activeProcess = nil
        throw AppInstallError.failed(Self.failureMessage(at: log))
    }

    public func cancel() {
        // Called synchronously during app termination; a cancelled async task may
        // not resume its cleanup before NSApplication exits the process.
        if let process = activeProcess, process.isRunning { process.terminate() }
    }

    public func recoveredFailure(currentVersion: String) -> String? {
        cleanupCompletedSessions()
        guard let pending = defaults.dictionary(forKey: Self.pendingKey),
              let path = pending["directory"] as? String,
              let requested = pending["version"] as? String else { return nil }
        let session = URL(fileURLWithPath: path).standardizedFileURL
        guard session.deletingLastPathComponent().path == directory.standardizedFileURL.path,
              UUID(uuidString: session.lastPathComponent) != nil else {
            defaults.removeObject(forKey: Self.pendingKey); return nil
        }
        defaults.removeObject(forKey: Self.pendingKey)
        if let current = ReleaseVersion(currentVersion), let target = ReleaseVersion(requested), current >= target { return nil }
        return "上次更新未完成，旧版本已保留。请重试更新。"
    }

    private func cleanupCompletedSessions() {
        let manager = FileManager.default
        for session in (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            guard UUID(uuidString: session.lastPathComponent) != nil,
                  let event = try? String(contentsOf: session.appendingPathComponent("event"), encoding: .utf8),
                  ["completed", "failed"].contains(event.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            try? manager.removeItem(at: session)
        }
    }

    private static func failureMessage(at log: URL) -> String {
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        if let line = text.split(separator: "\n").last(where: { $0.hasPrefix("MacPower:") }) {
            return String(line.dropFirst("MacPower:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "下载或校验未能完成，旧版本未更改。请稍后重试。"
    }
}
