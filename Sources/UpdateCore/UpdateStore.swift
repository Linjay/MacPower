import Combine
import Foundation

public enum UpdateState: Equatable {
    case idle, checking, noReleases
    case upToDate(AppRelease), available(AppRelease), failed(String)
}

@MainActor public final class UpdateStore: ObservableObject {
    public let currentVersion: String
    @Published public private(set) var state: UpdateState = .idle
    @Published public private(set) var lastChecked: Date?
    @Published public var automaticChecks: Bool {
        didSet {
            defaults.set(automaticChecks, forKey: "updates.automatic")
            if automaticChecks { checkIfDue() }
        }
    }
    @Published public var includingPreviews: Bool {
        didSet {
            defaults.set(includingPreviews, forKey: "updates.previews")
            cancel()
            state = .idle
            lastChecked = nil
            defaults.removeObject(forKey: "updates.lastChecked")
            defaults.removeObject(forKey: "updates.lastAttempt")
            if automaticChecks { checkIfDue() }
        }
    }
    private let defaults: UserDefaults
    private let fetch: (Bool) async throws -> AppRelease?
    private var task: Task<Void, Never>?
    private var generation = 0

    public init(currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                defaults: UserDefaults = .standard,
                fetch: @escaping (Bool) async throws -> AppRelease? = { try await ReleaseClient().latest(includingPreviews: $0) }) {
        self.currentVersion = currentVersion ?? "开发版"
        self.defaults = defaults
        self.fetch = fetch
        automaticChecks = defaults.bool(forKey: "updates.automatic")
        // MacPower currently ships previews. Separate keys preserve all existing monitoring preferences.
        includingPreviews = defaults.object(forKey: "updates.previews") as? Bool ?? true
        lastChecked = defaults.object(forKey: "updates.lastChecked") as? Date
    }

    public func checkIfDue(now: Date = Date()) {
        guard automaticChecks else { return }
        if let attempt = defaults.object(forKey: "updates.lastAttempt") as? Date,
           now.timeIntervalSince(attempt) < 24 * 60 * 60 { return }
        check(now: now)
    }

    public func check(now: Date = Date()) {
        guard task == nil else { return }
        guard let installed = ReleaseVersion(currentVersion) else { state = .failed(UpdateError.invalidVersion.localizedDescription); return }
        if let retry = defaults.object(forKey: "updates.retryAfter") as? Date, now < retry {
            state = .failed(UpdateError.rateLimited(retry).localizedDescription); return
        }
        defaults.set(now, forKey: "updates.lastAttempt")
        state = .checking
        let previews = includingPreviews, token = generation
        task = Task { [weak self, fetch] in
            do {
                let release = try await fetch(previews)
                guard let self, !Task.isCancelled, token == self.generation else { return }
                if let release { self.state = installed < release.version ? .available(release) : .upToDate(release) }
                else { self.state = .noReleases }
                self.lastChecked = Date()
                self.defaults.set(self.lastChecked, forKey: "updates.lastChecked")
                self.defaults.removeObject(forKey: "updates.retryAfter")
            } catch {
                guard let self, !Task.isCancelled, token == self.generation else { return }
                if case UpdateError.rateLimited(let retry) = error {
                    self.defaults.set(retry ?? Date().addingTimeInterval(3600), forKey: "updates.retryAfter")
                }
                self.state = .failed(error.localizedDescription)
            }
            self?.task = nil
        }
    }

    public func cancel() {
        generation += 1
        task?.cancel(); task = nil
        if state == .checking { state = .idle }
    }
}
