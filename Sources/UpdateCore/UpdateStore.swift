import Combine
import Foundation

public enum UpdateState: Equatable {
    case idle, checking, noReleases
    case upToDate(AppRelease), available(AppRelease), failed(String)
}

public typealias UpdateInstallOperation = @MainActor (AppRelease, @escaping @MainActor (UpdateInstallPhase) -> Void) async throws -> Void

@MainActor public final class UpdateStore: ObservableObject {
    public let currentVersion: String
    @Published public private(set) var state: UpdateState = .idle
    @Published public private(set) var lastChecked: Date?
    @Published public private(set) var installationState: UpdateInstallationState = .idle
    public var onRestartRequested: (() -> Void)?
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
    private let install: UpdateInstallOperation
    private let cancelNativeInstallation: () -> Void
    private var task: Task<Void, Never>?
    private var installationTask: Task<Void, Never>?
    private var installationGeneration = 0
    private var generation = 0

    public init(currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                defaults: UserDefaults = .standard,
                fetch: ((Bool) async throws -> AppRelease?)? = nil,
                install: UpdateInstallOperation? = nil) {
        self.currentVersion = currentVersion ?? "开发版"
        self.defaults = defaults
        self.fetch = fetch ?? { try await ReleaseClient(defaults: defaults).latest(includingPreviews: $0) }
        let installer = AppInstaller(defaults: defaults)
        self.install = install ?? { release, progress in try await installer.install(release, progress: progress) }
        self.cancelNativeInstallation = { installer.cancel() }
        // Old versions paused the entire check after API throttling. Only pause the API now.
        if let retry = defaults.object(forKey: "updates.retryAfter") as? Date {
            defaults.set(retry, forKey: ReleaseClient.apiRetryKey)
            defaults.removeObject(forKey: "updates.retryAfter")
        }
        automaticChecks = defaults.bool(forKey: "updates.automatic")
        // MacPower currently ships previews. Separate keys preserve all existing monitoring preferences.
        includingPreviews = defaults.object(forKey: "updates.previews") as? Bool ?? true
        lastChecked = defaults.object(forKey: "updates.lastChecked") as? Date
        if install == nil, let failure = installer.recoveredFailure(currentVersion: self.currentVersion) {
            installationState = .failed(failure)
        }
    }

    public func checkIfDue(now: Date = Date()) {
        guard automaticChecks else { return }
        if let attempt = defaults.object(forKey: "updates.lastAttempt") as? Date,
           now.timeIntervalSince(attempt) < 24 * 60 * 60 { return }
        check(now: now)
    }

    public func check(now: Date = Date()) {
        guard task == nil, !installationState.isBusy else { return }
        guard let installed = ReleaseVersion(currentVersion) else { state = .failed(UpdateError.invalidVersion.localizedDescription); return }
        if let retry = defaults.object(forKey: "updates.serviceRetryAfter") as? Date, now < retry {
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
                self.defaults.removeObject(forKey: "updates.serviceRetryAfter")
            } catch {
                guard let self, !Task.isCancelled, token == self.generation else { return }
                if case UpdateError.rateLimited(let retry) = error {
                    self.defaults.set(retry ?? Date().addingTimeInterval(3600), forKey: "updates.serviceRetryAfter")
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
        // After handoff, the independent installer must survive app termination.
        if installationState != .restarting {
            cancelNativeInstallation()
            installationGeneration += 1
            installationTask?.cancel(); installationTask = nil
            if installationState.isBusy { installationState = .idle }
        }
    }

    public func installUpdate() {
        guard installationTask == nil, !installationState.isBusy,
              case .available(let release) = state else { return }
        guard release.downloadURL != nil else {
            installationState = .failed(AppInstallError.noPackage.localizedDescription); return
        }
        let token = installationGeneration
        installationState = .downloading
        installationTask = Task { [weak self, install] in
            do {
                try await install(release) { [weak self] phase in
                    guard let self, token == self.installationGeneration else { return }
                    switch phase {
                    case .downloading: self.installationState = .downloading
                    case .verifying: self.installationState = .verifying
                    case .restarting: self.installationState = .restarting
                    }
                }
                guard let self, !Task.isCancelled, token == self.installationGeneration else { return }
                self.installationTask = nil
                self.installationState = .restarting
                self.onRestartRequested?()
            } catch {
                guard let self, token == self.installationGeneration else { return }
                self.installationTask = nil
                if error is CancellationError { self.installationState = .idle }
                else { self.installationState = .failed(error.localizedDescription) }
            }
        }
    }
}
