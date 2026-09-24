import Foundation

public enum EnergyMode: String, Codable, Sendable {
    case automatic, lowPower, highPower, unknown

    public var title: String {
        switch self {
        case .automatic: return "自动"
        case .lowPower: return "节能"
        case .highPower: return "高性能"
        case .unknown: return "未提供"
        }
    }

    public var symbol: String {
        switch self {
        case .automatic: return "gearshape"
        case .lowPower: return "leaf.fill"
        case .highPower: return "speedometer"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// The selected system policy, not a claim about instantaneous CPU performance.
public struct EnergyModeProfiles: Codable, Equatable, Sendable {
    public var battery: EnergyMode = .unknown
    public var adapter: EnergyMode = .unknown
    public var sampledAt: Date

    public init(at date: Date = Date()) { sampledAt = date }

    public func mode(externalConnected: Bool?) -> EnergyMode {
        switch externalConnected {
        case false: return battery
        case true: return adapter
        case nil: return .unknown
        }
    }

    /// Parse only mode fields from the read-only `pmset -g custom` output.
    public static func parse(_ output: String, at date: Date = Date()) -> Self {
        var profiles: [String: [String: String]] = [:]
        var section: String?
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasSuffix(":") {
                section = text == "Battery Power:" || text == "AC Power:" ? text : nil
                continue
            }
            guard let section else { continue }
            let fields = text.split(whereSeparator: \.isWhitespace)
            guard let key = fields.first.map(String.init), ["powermode", "lowpowermode", "highpowermode"].contains(key) else { continue }
            profiles[section, default: [:]][key] = fields.count == 2 ? String(fields[1]) : ""
        }
        var result = Self(at: date)
        result.battery = decode(profiles["Battery Power:"] ?? [:])
        result.adapter = decode(profiles["AC Power:"] ?? [:])
        return result
    }

    private static func decode(_ fields: [String: String]) -> EnergyMode {
        // Modern pmset uses a tri-state policy. Unknown future values stay unknown.
        if let mode = fields["powermode"] {
            return ["0": .automatic, "1": .lowPower, "2": .highPower][mode] ?? .unknown
        }
        let low = fields["lowpowermode"], high = fields["highpowermode"]
        guard low.map({ ["0", "1", "2"].contains($0) }) ?? true,
              high.map({ ["0", "1"].contains($0) }) ?? true else { return .unknown }
        if low == "1" && high == "1" { return .unknown }
        if high == "1" || low == "2" { return .highPower }
        if low == "1" { return .lowPower }
        if low == "0" { return .automatic }
        return .unknown
    }
}

public extension PowerState {
    var showsEnergyMode: Bool { self == .battery || self == .supplement }
}
