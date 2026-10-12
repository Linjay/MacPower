import Foundation

public struct AppRelease: Equatable, Sendable {
    public let version: ReleaseVersion
    public let isPrerelease: Bool
    public let notes: String
    public let pageURL: URL
    public let downloadURL: URL?
}

public enum UpdateError: Error, LocalizedError, Equatable {
    case invalidVersion, invalidResponse, unavailable, rateLimited(Date?), http(Int), network

    public var errorDescription: String? {
        switch self {
        case .invalidVersion: return "无法识别当前应用版本，请使用已打包的 MacPower，或打开发布页查看。"
        case .invalidResponse: return "更新信息格式不正确，请稍后重试或打开发布页。"
        case .unavailable: return "发布列表暂时不可访问，请稍后重试或打开发布页。"
        case .rateLimited(let retry):
            return retry.map { "GitHub 请求已限流，可在 \($0.formatted(date: .omitted, time: .standard)) 后重试，或直接打开发布页。" }
                ?? "GitHub 请求已限流，请稍后重试，或直接打开发布页。"
        case .http(let code): return "检查更新失败（HTTP \(code)），请稍后重试或打开发布页。"
        case .network: return "无法连接更新服务，请检查网络后重试，或打开发布页。"
        }
    }
}

public struct ReleaseClient: Sendable {
    public static let releasesURL = URL(string: "https://github.com/Linjay/MacPower/releases")!
    public static let endpoint = URL(string: "https://api.github.com/repos/Linjay/MacPower/releases?per_page=100")!
    public static let feedURL = URL(string: "https://github.com/Linjay/MacPower/releases.atom")!
    static let apiRetryKey = "updates.apiRetryAfter"
    private let session: URLSession
    private let cooldown: APICooldown
    public init(session: URLSession? = nil, defaults: UserDefaults = .standard) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        self.session = session ?? URLSession(configuration: configuration)
        cooldown = APICooldown(defaults: defaults)
    }

    public func latest(includingPreviews: Bool) async throws -> AppRelease? {
        if let retry = cooldown.retryAfter, retry > Date() {
            return try await latestFromPublicPages(includingPreviews: includingPreviews)
        }
        do {
            let (data, _) = try await load(Self.endpoint, accept: "application/vnd.github+json")
            let release = try Self.latest(from: data, includingPreviews: includingPreviews)
            cooldown.retryAfter = nil
            return release
        } catch UpdateError.rateLimited(let retry) {
            cooldown.retryAfter = retry ?? Date().addingTimeInterval(3600)
            return try await latestFromPublicPages(includingPreviews: includingPreviews)
        }
    }

    private func latestFromPublicPages(includingPreviews: Bool) async throws -> AppRelease? {
        let selected: PublicReleaseEntry
        let page: Data
        if includingPreviews {
            let (feed, _) = try await load(Self.feedURL, accept: "application/atom+xml")
            guard let entry = try PublicReleaseFeed.parse(feed).max(by: { $0.version < $1.version }) else { return nil }
            selected = entry
            (page, _) = try await load(Self.releasesURL.appendingPathComponent("tag").appendingPathComponent(entry.tag))
        } else {
            // Atom has no prerelease flag and only contains recent entries. GitHub's stable
            // redirect also finds an older stable release when all recent entries are previews.
            let (data, response) = try await load(Self.releasesURL.appendingPathComponent("latest"))
            guard let url = response.url else { throw UpdateError.invalidResponse }
            if url == Self.releasesURL { return nil }
            guard url.pathComponents.count == 6,
                  url.pathComponents.prefix(5).elementsEqual(["/", "Linjay", "MacPower", "releases", "tag"]),
                  let version = ReleaseVersion(url.lastPathComponent) else { throw UpdateError.invalidResponse }
            selected = PublicReleaseEntry(tag: url.lastPathComponent, version: version, notes: "")
            page = data
        }
        let preview = try PublicReleaseFeed.isPreview(page: page, tag: selected.tag) || selected.version.isPrerelease
        guard includingPreviews || !preview else { throw UpdateError.invalidResponse }
        let (assets, _) = try await load(Self.releasesURL.appendingPathComponent("expanded_assets").appendingPathComponent(selected.tag))
        let download = try PublicReleaseFeed.downloadURL(assets: assets, tag: selected.tag, version: selected.version, architecture: Self.architecture)
        return AppRelease(version: selected.version, isPrerelease: preview, notes: selected.notes,
                          pageURL: Self.releasesURL.appendingPathComponent("tag").appendingPathComponent(selected.tag), downloadURL: download)
    }

    private func load(_ url: URL, accept: String = "text/html") async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if url == Self.endpoint { request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version") }
        request.setValue("MacPower-UpdateChecker", forHTTPHeaderField: "User-Agent")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw UpdateError.network }
        guard let http = response as? HTTPURLResponse, let responseURL = http.url,
              responseURL.scheme == "https", responseURL.host == url.host,
              responseURL.user == nil, responseURL.password == nil, data.count <= 4_000_000 else { throw UpdateError.invalidResponse }
        if http.statusCode == 429 || (http.statusCode == 403 && http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0") {
            let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init).map { Date().addingTimeInterval($0) }
            throw UpdateError.rateLimited(retry ?? reset)
        }
        guard http.statusCode != 404 else { throw UpdateError.unavailable }
        guard http.statusCode == 200 else { throw UpdateError.http(http.statusCode) }
        return (data, http)
    }

    /// Select by version, not creation order: a late maintenance release must not hide a newer version.
    public static func latest(from data: Data, includingPreviews: Bool, architecture: String = architecture) throws -> AppRelease? {
        guard data.count <= 4_000_000, let entries = try? JSONDecoder().decode([ReleasePayload].self, from: data) else {
            throw UpdateError.invalidResponse
        }
        var candidates: [AppRelease] = []
        for entry in entries where !entry.draft {
            guard let version = ReleaseVersion(entry.tag_name) else { continue }
            let preview = entry.prerelease || version.isPrerelease
            guard includingPreviews || !preview else { continue }
            // Build trusted URLs from the fixed repository, never follow a URL supplied in release notes.
            let pageURL = releasesURL.appendingPathComponent("tag").appendingPathComponent(entry.tag_name)
            let assetName = "MacPower-\(version.number)-\(architecture).zip"
            let hasAsset = entry.assets.contains { $0.name == assetName && $0.state == "uploaded" && $0.size > 0 }
            let download = hasAsset ? releasesURL.appendingPathComponent("download").appendingPathComponent(entry.tag_name).appendingPathComponent(assetName) : nil
            candidates.append(AppRelease(version: version, isPrerelease: preview, notes: String((entry.body ?? "").prefix(16_000)), pageURL: pageURL, downloadURL: download))
        }
        if candidates.isEmpty && entries.contains(where: { !$0.draft && (includingPreviews || !$0.prerelease) && ReleaseVersion($0.tag_name) == nil }) {
            throw UpdateError.invalidResponse
        }
        return candidates.max { $0.version < $1.version }
    }

    public static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unsupported"
        #endif
    }

    private struct ReleasePayload: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let body: String?
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let state: String
        let size: Int
    }

    // UserDefaults supports concurrent access; this wrapper has no other shared state.
    private struct APICooldown: @unchecked Sendable {
        let defaults: UserDefaults
        var retryAfter: Date? {
            get { defaults.object(forKey: ReleaseClient.apiRetryKey) as? Date }
            nonmutating set {
                if let newValue { defaults.set(newValue, forKey: ReleaseClient.apiRetryKey) }
                else { defaults.removeObject(forKey: ReleaseClient.apiRetryKey) }
            }
        }
    }
}
