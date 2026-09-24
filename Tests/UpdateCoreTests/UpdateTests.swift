import Foundation
import Testing
@testable import UpdateCore

private func releases(_ entries: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: entries) }
private func entry(_ tag: String, preview: Bool = false, draft: Bool = false, asset: String? = nil) -> [String: Any] {
    ["tag_name": tag, "prerelease": preview, "draft": draft, "body": "更新说明",
     "assets": asset.map { [["name": $0, "state": "uploaded", "size": 1024]] } ?? []]
}
private func release(_ version: String) throws -> AppRelease {
    try #require(try ReleaseClient.latest(from: releases([entry(version)]), includingPreviews: true))
}

struct ReleaseVersionTests {
    @Test func numericComponentsAndBuildMetadata() throws {
        #expect(try #require(ReleaseVersion("0.1.9")) < #require(ReleaseVersion("v0.1.10")))
        #expect(try #require(ReleaseVersion("0.9.9")) < #require(ReleaseVersion("1.0.0")))
        #expect(ReleaseVersion("v1.2.3+123") == ReleaseVersion("1.2.3+456"))
    }
    @Test func prereleasePrecedenceMatchesSemver() throws {
        let values = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
        for (left, right) in zip(values, values.dropFirst()) {
            #expect(try #require(ReleaseVersion(left)) < #require(ReleaseVersion(right)))
        }
        #expect(try #require(ReleaseVersion("1.0.0-99999999999999999999")) < #require(ReleaseVersion("1.0.0-100000000000000000000")))
    }
    @Test func malformedVersionsDoNotCompareAsZero() {
        for value in ["", "main", "1.0", "1.0.0.1", "01.0.0", "-1.0.0", "1.0.0-", "1.0.0-01", "1.0.0+", "1.0.0+a+b", "1.0.0-a..b", "1.0.0/a", "1.0.0-中文", "999999999999999999999.0.0"] {
            #expect(ReleaseVersion(value) == nil)
        }
    }
}

struct ReleaseSelectionTests {
    @Test func previewChannelFindsExistingMacPowerPreviewTags() throws {
        let data = try releases([entry("v0.1.0", preview: true), entry("v0.1.1", preview: true, asset: "MacPower-0.1.1-arm64.zip")])
        let latest = try #require(try ReleaseClient.latest(from: data, includingPreviews: true, architecture: "arm64"))
        #expect(latest.version.number == "0.1.1")
        #expect(latest.isPrerelease)
        #expect(latest.downloadURL?.absoluteString == "https://github.com/Linjay/MacPower/releases/download/v0.1.1/MacPower-0.1.1-arm64.zip")
        #expect(try ReleaseClient.latest(from: data, includingPreviews: false) == nil)
    }
    @Test func highestVersionWinsRegardlessOfPublicationOrder() throws {
        let data = try releases([entry("v1.0.9"), entry("v2.0.0"), entry("v9.0.0", draft: true), entry("v3.0.0", preview: true), entry("v4.0.0-beta.1")])
        #expect(try ReleaseClient.latest(from: data, includingPreviews: false)?.version.number == "2.0.0")
        #expect(try ReleaseClient.latest(from: data, includingPreviews: true)?.version.number == "4.0.0-beta.1")
    }
    @Test func incompatibleOrMissingAssetsStillOfferReleaseNotes() throws {
        let data = try releases([entry("v1.0.0", asset: "MacPower-1.0.0-arm64.zip")])
        let latest = try #require(try ReleaseClient.latest(from: data, includingPreviews: true, architecture: "x86_64"))
        #expect(latest.downloadURL == nil)
        #expect(latest.pageURL.absoluteString == "https://github.com/Linjay/MacPower/releases/tag/v1.0.0")
    }
    @Test func remoteURLsCannotRedirectUpdateButtons() throws {
        var payload = entry("v1.0.0", asset: "MacPower-1.0.0-arm64.zip")
        payload["html_url"] = "https://example.invalid/other"
        payload["assets"] = [["name": "MacPower-1.0.0-arm64.zip", "state": "uploaded", "size": 1024, "browser_download_url": "file:///tmp/other"]]
        let latest = try #require(try ReleaseClient.latest(from: releases([payload]), includingPreviews: true, architecture: "arm64"))
        #expect(latest.downloadURL?.host == "github.com")
        #expect(latest.pageURL.host == "github.com")
    }
    @Test func malformedAndEmptyFeedsAreDifferent() throws {
        #expect(try ReleaseClient.latest(from: releases([]), includingPreviews: true) == nil)
        #expect(throws: UpdateError.invalidResponse) { try ReleaseClient.latest(from: Data("{}".utf8), includingPreviews: true) }
        #expect(throws: UpdateError.invalidResponse) { try ReleaseClient.latest(from: releases([entry("nightly")]), includingPreviews: true) }
    }
}

@MainActor struct UpdateStoreTests {
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "MacPower.UpdateTests.\(UUID().uuidString)")!
    }
    private func clear(_ defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("updates.") { defaults.removeObject(forKey: key) }
    }
    private func complete(_ store: UpdateStore) async {
        for _ in 0..<1000 {
            if store.state != .checking { return }
            await Task.yield()
        }
        Issue.record("Update check did not finish")
    }

    @Test func olderEqualAndNewerInstalledVersionsNeverDowngrade() async throws {
        let remote = try release("1.2.0")
        for installed in ["1.1.0", "1.2.0", "1.3.0"] {
            let defaults = isolatedDefaults(); defer { clear(defaults) }
            let store = UpdateStore(currentVersion: installed, defaults: defaults, fetch: { _ in remote })
            store.check(); await complete(store)
            #expect(store.state == (installed == "1.1.0" ? .available(remote) : .upToDate(remote)))
            #expect(store.lastChecked != nil)
        }
    }
    @Test func automaticChecksAreOptInAndThrottledAcrossRestarts() async throws {
        let defaults = isolatedDefaults(); defer { clear(defaults) }
        var calls = 0
        let store = UpdateStore(currentVersion: "1.0.0", defaults: defaults, fetch: { _ in calls += 1; return nil })
        #expect(!store.automaticChecks)
        #expect(store.includingPreviews)
        store.checkIfDue(); await Task.yield()
        #expect(calls == 0)
        store.automaticChecks = true; await complete(store)
        #expect(calls == 1)
        let restarted = UpdateStore(currentVersion: "1.0.0", defaults: defaults, fetch: { _ in calls += 1; return nil })
        #expect(restarted.automaticChecks)
        restarted.checkIfDue(); await Task.yield()
        #expect(calls == 1)
        restarted.checkIfDue(now: Date().addingTimeInterval(86401)); await complete(restarted)
        #expect(calls == 2)
    }
    @Test func failureCanBeRetriedAndIsNeverReportedAsUpToDate() async throws {
        let defaults = isolatedDefaults(); defer { clear(defaults) }
        var calls = 0
        let store = UpdateStore(currentVersion: "1.0.0", defaults: defaults, fetch: { _ in
            calls += 1
            if calls == 1 { throw UpdateError.network }
            return nil
        })
        store.check(); await complete(store)
        #expect(store.state == .failed(UpdateError.network.localizedDescription))
        #expect(store.lastChecked == nil)
        store.check(); await complete(store)
        #expect(store.state == .noReleases)
        #expect(calls == 2)
    }
    @Test func rateLimitSurvivesRestartsAndAvoidsRepeatedRequests() async {
        let defaults = isolatedDefaults(); defer { clear(defaults) }
        let retry = Date().addingTimeInterval(3600)
        let store = UpdateStore(currentVersion: "1.0.0", defaults: defaults, fetch: { _ in throw UpdateError.rateLimited(retry) })
        store.check(); await complete(store)
        var calls = 0
        let restarted = UpdateStore(currentVersion: "1.0.0", defaults: defaults, fetch: { _ in calls += 1; return nil })
        restarted.check(); await complete(restarted)
        #expect(calls == 0)
        #expect(restarted.state == .failed(UpdateError.rateLimited(retry).localizedDescription))
    }
    @Test func repeatedClicksAndCancelledChannelResultsCannotOverwriteState() async throws {
        let defaults = isolatedDefaults(); defer { clear(defaults) }
        var continuation: CheckedContinuation<AppRelease?, Never>?
        var calls = 0
        let store = UpdateStore(currentVersion: "1.0.0", defaults: defaults, fetch: { _ in
            calls += 1
            return await withCheckedContinuation { continuation = $0 }
        })
        store.check(); store.check()
        for _ in 0..<1000 { if continuation != nil { break }; await Task.yield() }
        #expect(calls == 1)
        store.includingPreviews = false
        continuation?.resume(returning: try release("9.0.0"))
        for _ in 0..<10 { await Task.yield() }
        #expect(store.state == .idle)
        #expect(store.lastChecked == nil)
        #expect(!defaults.bool(forKey: "updates.previews"))
    }
    @Test func developmentBuildDoesNotMakeNetworkRequests() async {
        let defaults = isolatedDefaults(); defer { clear(defaults) }
        var calls = 0
        let store = UpdateStore(currentVersion: nil, defaults: defaults, fetch: { _ in calls += 1; return nil })
        store.check(); await complete(store)
        #expect(calls == 0)
        #expect(store.state == .failed(UpdateError.invalidVersion.localizedDescription))
    }
}

private final class StubURLProtocol: URLProtocol {
    static var status = 200
    static var headers: [String: String] = [:]
    static var body = Data("[]".utf8)
    static var failure: URLError?
    static var requestSeen: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestSeen = request
        if let failure = Self.failure { client?.urlProtocol(self, didFailWithError: failure); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: Self.headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct ReleaseClientTests {
    private func client(status: Int = 200, headers: [String: String] = [:], body: Data = Data("[]".utf8), failure: URLError? = nil) -> ReleaseClient {
        StubURLProtocol.status = status; StubURLProtocol.headers = headers; StubURLProtocol.body = body; StubURLProtocol.failure = failure
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return ReleaseClient(session: URLSession(configuration: configuration))
    }
    @Test func liveRequestShapeHasNoCredentialsOrTelemetry() async throws {
        let result = try await client(body: releases([entry("v0.1.1", preview: true)])).latest(includingPreviews: true)
        #expect(result?.version.number == "0.1.1")
        let request = try #require(StubURLProtocol.requestSeen)
        #expect(request.url == ReleaseClient.endpoint)
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "MacPower-UpdateChecker")
    }
    @Test func httpErrorsAndRateLimitsAreActionable() async {
        for (status, headers, expected) in [
            (403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000000"], UpdateError.rateLimited(Date(timeIntervalSince1970:1800000000))),
            (429, [:], .rateLimited(nil)), (403, [:], .http(403)), (404, [:], .unavailable), (500, [:], .http(500))
        ] {
            do { _ = try await client(status: status, headers: headers).latest(includingPreviews: true); Issue.record("Expected HTTP failure") }
            catch { #expect(error as? UpdateError == expected) }
        }
    }
    @Test func offlineAndMalformedResponsesDoNotBecomeEmptyReleaseLists() async {
        do { _ = try await client(failure: URLError(.notConnectedToInternet)).latest(includingPreviews: true); Issue.record("Expected network failure") }
        catch { #expect(error as? UpdateError == .network) }
        do { _ = try await client(body: Data("not json".utf8)).latest(includingPreviews: true); Issue.record("Expected parse failure") }
        catch { #expect(error as? UpdateError == .invalidResponse) }
    }
}
