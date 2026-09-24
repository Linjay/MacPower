import AppKit
import Combine
import Foundation
import ServiceManagement
import UserNotifications
import UniformTypeIdentifiers
import PowerCore
import PowerHardware
import UpdateCore

@MainActor final class AppStore: ObservableObject {
    let updater = UpdateStore()
    @Published var settingsPage: SettingsPage = .appearance
    @Published var snapshot = PowerSnapshot.unavailable()
    @Published var health: HealthReport?
    @Published var state: PowerState = .updating
    @Published private(set) var energyModes = EnergyModeProfiles(at: .distantPast)
    @Published var message: String?
    @Published var healthMessage: String?
    @Published var revision = 0
    @Published var preferences: Preferences {
        didSet {
            // Never mutate an @Published property inside its observer. Decode validates persisted values;
            // UI controls constrain subsequent changes. Recursive writeback would overflow the stack.
            if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "preferences.v1") }
            if oldValue.recordHistory != preferences.recordHistory { recorder.breakContinuity() }
            recorder.prune(now: Date(), days: preferences.retentionDays)
            restartTimer(); persist(); onUpdate?()
        }
    }
    @Published var notificationStatus = "未开启时不申请通知权限"
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    var onUpdate: (() -> Void)?
    var showSettings: (() -> Void)?
    var showOverview: (() -> Void)?
    var showHistory: ((Int, Set<ChartSeries>) -> Void)?
    var showMetric: ((String) -> Void)?
    var quit: (() -> Void)?
    private var recorder: HistoryRecorder
    private let historyURL: URL
    private let ioQueue = DispatchQueue(label:"MacPower.history", qos:.utility)
    private var writeEnabled = true
    private var timer: Timer?
    private var observer: PowerEventObserver?
    private var observers: [NSObjectProtocol] = []
    private var sampling = false
    private var sleeping = false
    private var generation = 0
    private var panelVisible = false
    private var lastSave = Date.distantPast
    private var lastHealth = Date.distantPast
    private var healthLoading = false
    private var energyModesLoading = false
    private var powerModeObserver: NSObjectProtocol?
    private var stabilizer = SourceStabilizer()
    private var reminders = ReminderPolicy()
    var points: [HistoryPoint] { recorder.archive.points }
    var healthHistory: [HealthReport] { recorder.archive.health }
    var interval: TimeInterval { panelVisible ? 1 : preferences.energySaving ? 15 : 5 }
    var isStale: Bool { state == .stale || state == .updating || state == .sleeping || state == .unavailable }
    var energyMode: EnergyMode {
        guard !isStale, Date().timeIntervalSince(energyModes.sampledAt) < 45 else { return .unknown }
        return energyModes.mode(externalConnected: snapshot.externalConnected)
    }
    var energyModeSource: String {
        snapshot.externalConnected == true ? "macOS 外接电源设置" : "macOS 电池供电设置"
    }

    init() {
        preferences = Preferences.decode(UserDefaults.standard.data(forKey:"preferences.v1"))
        historyURL = FileManager.default.urls(for:.applicationSupportDirectory, in:.userDomainMask)[0]
            .appendingPathComponent("MacPower", isDirectory:true).appendingPathComponent("history-v1.json")
        do { recorder = HistoryRecorder(archive:try HistoryArchive.load(from:historyURL)) }
        catch {
            recorder = HistoryRecorder(); writeEnabled = false
            message = "历史文件无法读取，已保留原文件。本次记录暂存内存，可先导出。"
        }
        recorder.prune(now:Date(),days:preferences.retentionDays)
        health = recorder.archive.health.last
    }

    func start() {
        observer = PowerEventObserver { [weak self] in Task { @MainActor in
            self?.refreshEnergyModes(force: true); self?.sample()
        } }
        powerModeObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshEnergyModes(force: true) }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.sleep() }
        })
        observers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.wake() }
        })
        restartTimer(); sample(); refreshHealth()
    }
    func setVisible(_ visible: Bool) {
        panelVisible = visible; restartTimer()
        if visible { refreshEnergyModes(force: true); sample() }
    }
    private func restartTimer() {
        timer?.invalidate(); guard !sleeping else { return }
        timer = Timer.scheduledTimer(withTimeInterval:interval,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer?.tolerance = panelVisible ? 0.1 : 1
    }
    func sample() {
        guard !sleeping, !sampling else { return }
        refreshEnergyModes()
        sampling = true; let token = generation
        if Date().timeIntervalSince(snapshot.timestamp) > max(5, interval*3) { state = .stale; onUpdate?() }
        Task {
            let result = await Task.detached(priority:.utility) { PowerReader.read() }.value
            sampling = false
            guard token == generation, !sleeping else { return }
            snapshot = result; state = stabilizer.accept(result)
            if preferences.recordHistory && state != .updating && state != .unavailable {
                recorder.record(result,expectedInterval:interval)
            } else { recorder.breakContinuity() }
            if Date().timeIntervalSince(lastSave) >= 60 { recorder.prune(now:Date(),days:preferences.retentionDays); persist() }
            if state != .updating && state != .unavailable { deliver(reminders.evaluate(result,preferences:preferences)) }
            else { reminders.resetContinuity() }
            if Date().timeIntervalSince(lastHealth) > 3600 { refreshHealth() }
            onUpdate?()
        }
    }
    private func refreshEnergyModes(force: Bool = false) {
        guard !sleeping, !energyModesLoading,
              force || Date().timeIntervalSince(energyModes.sampledAt) >= 15 else { return }
        energyModesLoading = true
        let token = generation
        Task {
            let result = await Task.detached(priority: .utility) { PowerReader.readEnergyModes() }.value
            energyModesLoading = false
            guard token == generation, !sleeping else { return }
            energyModes = result; onUpdate?()
        }
    }
    func refreshHealth() {
        guard !healthLoading else { return }
        healthLoading = true; lastHealth = Date()
        Task {
            let result = await Task.detached(priority:.utility) { try? PowerReader.readHealth() }.value
            healthLoading = false
            guard let result else { healthMessage = "暂时无法读取系统健康报告，稍后可重试。"; return }
            health = result; healthMessage = nil
            if preferences.recordHistory { recorder.addHealth(result); persist() }
        }
    }
    private func sleep() {
        sleeping = true; generation += 1; timer?.invalidate(); state = .sleeping
        recorder.breakContinuity(); reminders.resetContinuity(); persist(); onUpdate?()
    }
    private func wake() {
        sleeping = false; generation += 1; stabilizer.reset(); recorder.breakContinuity()
        energyModes = EnergyModeProfiles(at: .distantPast)
        state = .updating; restartTimer(); sample(); refreshHealth()
    }
    func stop() {
        generation += 1; sleeping = true; timer?.invalidate(); observer = nil
        if let powerModeObserver { NotificationCenter.default.removeObserver(powerModeObserver) }
        persist(); ioQueue.sync {}
    }

    func persist() {
        guard writeEnabled else { return }
        let archive = recorder.archive, url = historyURL
        lastSave = Date()
        ioQueue.async { [weak self] in
            do { try archive.save(to:url) }
            catch { Task { @MainActor in self?.message = "历史记录未能保存到磁盘。现有记录仍可导出。" } }
        }
    }
    func clearHistory() {
        let alert = NSAlert(); alert.messageText = "清除全部本地历史？"
        alert.informativeText = "将删除功率记录和健康趋势，不会影响电池、外观设置或已导出的文件。此操作不可撤销。"
        alert.addButton(withTitle:"取消"); alert.addButton(withTitle:"清除历史")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        // If an unreadable file exists, preserve it as a recoverable backup before starting a new archive.
        if !writeEnabled && FileManager.default.fileExists(atPath:historyURL.path) {
            do { try FileManager.default.copyItem(at:historyURL,to:historyURL.deletingPathExtension().appendingPathExtension("backup-\(Int(Date().timeIntervalSince1970)).json")) }
            catch { message = "无法备份原历史文件，未清除任何记录。"; return }
        }
        writeEnabled = true; recorder.clear(); revision += 1; persist(); message = "本地历史已清除"
    }
    func selectedPoints(minutes: Int) -> [HistoryPoint] {
        let cutoff = Date().addingTimeInterval(-Double(minutes)*60)
        return points.filter { $0.lastSampleAt >= cutoff }
    }
    func export(minutes: Int) {
        let selected = selectedPoints(minutes:minutes)
        guard !selected.isEmpty else { message = "当前时段没有可导出的记录"; return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "MacPower-\(Date().formatted(.iso8601.year().month().day()))-\(minutes)min.csv"
        panel.title = "导出功率记录"; panel.prompt = "导出"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try HistoryExport.csv(selected).write(to:url,atomically:true,encoding:.utf8); message = "已导出 \(selected.count) 条记录" }
        catch { message = "导出失败：\(error.localizedDescription)" }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { message = "请在系统设置 → 通用 → 登录项中允许 MacPower。" }
        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; message = "登录启动设置未生效：\(error.localizedDescription)" }
    }
    func setReminder(_ key: WritableKeyPath<Preferences,Bool>, enabled: Bool) {
        if !enabled { preferences[keyPath:key] = false; return }
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound])
                if granted { preferences[keyPath:key] = true; notificationStatus = "已允许通知，满足条件时提醒一次" }
                else { notificationStatus = "通知未获允许，可在系统设置 → 通知中开启。" }
            } catch { notificationStatus = "无法申请通知权限：\(error.localizedDescription)" }
        }
    }
    private func deliver(_ events: [Reminder]) {
        for event in events {
            let content = UNMutableNotificationContent(); content.title = "MacPower"
            switch event {
            case .low: content.body = "电量已降至 \(snapshot.percent ?? 0)%，当前使用电池供电。"
            case .charged: content.body = "电量已达到 \(preferences.chargeThreshold)%。MacPower 只监测，不控制充电。"
            case .supplement: content.body = "插电后电池持续补充供电，当前外部供电可能不足以覆盖用电。"
            }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:"MacPower.\(event.rawValue)",content:content,trigger:nil)) { _ in }
        }
    }
    var menuText: String {
        if preferences.menuMetric == .percent { return snapshot.percent.map { "\($0)%" } ?? "—%" }
        guard !isStale else { return "— W" }
        switch preferences.menuMetric {
        case .input: return snapshot.externalConnected == false ? "未接入" : "\(snapshot.input.formatted()) W"
        case .battery: return "\(snapshot.battery.formatted(signed:true)) W"
        case .system: return "\(snapshot.system.formatted()) W"
        case .percent: return "—%"
        }
    }
    var batterySymbol: String {
        guard !isStale, let percent = snapshot.percent else { return "battery.0percent" }
        if snapshot.isCharging == true { return "battery.100percent.bolt" }
        let level = percent < 5 ? 0 : percent < 30 ? 25 : percent < 55 ? 50 : percent < 80 ? 75 : 100
        return "battery.\(level)percent"
    }
}
