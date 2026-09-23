import Foundation

public enum Quality: String, Codable, Sendable {
    case telemetry, reported, estimated, unavailable
    public var label: String {
        switch self {
        case .telemetry: return "设备遥测"
        case .reported: return "系统报告"
        case .estimated: return "估算"
        case .unavailable: return "未提供"
        }
    }
}

public struct PowerMetric: Codable, Equatable, Sendable {
    public var value: Double?
    public var quality: Quality
    public var source: String
    public var sampledAt: Date
    public var reason: String?
    public init(_ value: Double?, quality: Quality, source: String, at: Date, reason: String? = nil) {
        self.value = value?.isFinite == true ? value : nil
        self.quality = self.value == nil ? .unavailable : quality
        self.source = source; self.sampledAt = at; self.reason = reason
    }
    public static func missing(at: Date, reason: String = "系统未提供有效读数") -> Self {
        Self(nil, quality: .unavailable, source: "—", at: at, reason: reason)
    }
    public func formatted(signed: Bool = false) -> String {
        guard let value else { return "—" }
        if abs(value) < 0.05 { return "0.0" }
        return String(format: signed && value > 0 ? "+%.1f" : "%.1f", value).replacingOccurrences(of: "-", with: "−")
    }
}

public enum PowerState: String, Codable, Sendable {
    case unavailable, updating, battery, charging, full, idle, supplement, stale, sleeping
    public var title: String {
        switch self {
        case .unavailable: return "暂时无法读取电源数据"
        case .updating: return "正在更新供电状态"
        case .battery: return "电池供电"
        case .charging: return "外接电源 · 正在充电"
        case .full: return "外接电源 · 已充满"
        case .idle: return "外接电源 · 当前未充电"
        case .supplement: return "外接电源 · 电池补充供电"
        case .stale: return "数据暂未更新"
        case .sleeping: return "睡眠期间暂停采集"
        }
    }
}

public struct PowerSnapshot: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var hasBattery: Bool
    public var externalConnected: Bool?
    public var isCharging: Bool?
    public var isFull: Bool?
    public var percent: Int?
    public var input: PowerMetric
    public var battery: PowerMetric
    public var system: PowerMetric
    public var adapterWatts: Double?
    public var cycleCount: Int?
    public var voltage: Double?
    public var amperage: Double?
    public var minutesRemaining: Int?
    public var condition: String?
    public var state: PowerState {
        guard hasBattery, let externalConnected else { return .unavailable }
        if !externalConnected { return .battery }
        if let watts = battery.value, watts < -0.5 { return .supplement }
        if isFull == true { return .full }
        if isCharging == true { return .charging }
        return .idle
    }
    public var batteryLabel: String {
        guard let watts = battery.value else { return "电池净功率" }
        return watts > 0.5 ? "充入电池" : watts < -0.5 ? "电池放电" : "电池净功率"
    }
    public static func unavailable(at: Date = Date()) -> Self {
        let m = PowerMetric.missing(at: at)
        return Self(timestamp: at, hasBattery: false, input: m, battery: m, system: m)
    }
}

public struct HealthReport: Codable, Equatable, Sendable {
    public var date: Date
    public var maximumCapacity: Int?
    public var condition: String?
    public var cycleCount: Int?
    public var source: String
    public init(date: Date, maximumCapacity: Int?, condition: String?, cycleCount: Int?, source: String = "macOS 系统信息") {
        self.date = date; self.maximumCapacity = maximumCapacity; self.condition = condition
        self.cycleCount = cycleCount; self.source = source
    }
    public var conditionLabel: String {
        switch condition?.lowercased() {
        case "good", "normal": return "正常"
        case "check battery", "service recommended", "poor": return "建议维修"
        case nil: return "系统未提供状况"
        default: return condition ?? "系统未提供状况"
        }
    }
}

public enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system, light, dark
    public var title: String { self == .system ? "跟随系统" : self == .light ? "浅色" : "深色" }
    public func resolved(systemIsDark: Bool) -> Self { self == .system ? (systemIsDark ? .dark : .light) : self }
}

public enum MenuMetric: String, CaseIterable, Codable, Sendable {
    case battery, input, system, percent
    public var title: String {
        switch self { case .battery: return "电池净功率"; case .input: return "电源输入"; case .system: return "整机耗电"; case .percent: return "电池电量" }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var appearance: AppearanceMode = .system
    public var menuMetric: MenuMetric = .battery
    public var showPercent = false
    public var recordHistory = true
    public var retentionDays = 7
    public var energySaving = false
    public var lowBatteryReminder = false
    public var chargeReminder = false
    public var supplementReminder = false
    public var lowThreshold = 20
    public var chargeThreshold = 80
    public init() {}
    public mutating func validate() {
        if ![7,30,90].contains(retentionDays) { retentionDays = 7 }
        lowThreshold = min(40, max(5, lowThreshold)); chargeThreshold = min(100, max(50, chargeThreshold))
    }
    public static func decode(_ data: Data?) -> Self {
        guard let data, var result = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        result.validate(); return result
    }
}

/// Requires two consistent samples after a source change, without interpreting old telemetry as the new source.
public struct SourceStabilizer: Sendable {
    private var established: Bool?
    private var candidate: Bool?
    public init() {}
    public mutating func accept(_ snapshot: PowerSnapshot) -> PowerState {
        guard let source = snapshot.externalConnected else { return .unavailable }
        if established == nil { established = source; return snapshot.state }
        if source == established { candidate = nil; return snapshot.state }
        if candidate == source { established = source; candidate = nil; return snapshot.state }
        candidate = source; return .updating
    }
    public mutating func reset() { established = nil; candidate = nil }
}
