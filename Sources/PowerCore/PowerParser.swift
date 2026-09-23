import Foundation

public enum PowerParser {
    public static func parse(registry r: [String: Any]?, source p: [String: Any] = [:], at date: Date = Date()) -> PowerSnapshot {
        guard let r else { return .unavailable(at: date) }
        let telemetry = r["PowerTelemetryData"] as? [String: Any] ?? [:]
        let adapter = r["AdapterDetails"] as? [String: Any] ?? [:]
        let external = (r["ExternalConnected"] as? NSNumber)?.boolValue ?? (p["Power Source State"] as? String).flatMap { $0 == "AC Power" ? true : $0 == "Battery Power" ? false : nil }
        let charging = (p["Is Charging"] as? NSNumber)?.boolValue ?? (r["IsCharging"] as? NSNumber)?.boolValue
        let full = (p["Is Charged"] as? NSNumber)?.boolValue ?? (r["FullyCharged"] as? NSNumber)?.boolValue
        let voltage = number(r["Voltage"], range: 1...30_000).map { $0 / 1000 }
        let currentField = r["InstantAmperage"] != nil ? "InstantAmperage" : "Amperage"
        let current = signedNumber(r[currentField], range: -40_000...40_000).map { $0 / 1000 }
        var input = metric(telemetry["SystemPowerIn"], key: "PowerTelemetryData.SystemPowerIn", date: date, signed: false)
        var battery = metric(telemetry["BatteryPower"], key: "PowerTelemetryData.BatteryPower", date: date, signed: true)
        var system = metric(telemetry["SystemLoad"], key: "PowerTelemetryData.SystemLoad", date: date, signed: false)
        // Firmware telemetry can lag an unplug event. Battery mode uses current/voltage and labels the derivation.
        if external == false {
            input = PowerMetric(0, quality: .reported, source: "系统电源状态 · 未接入外部电源", at: date)
            battery = .missing(at: date, reason: "等待电池放电读数")
            system = .missing(at: date)
        }
        if battery.value == nil, let voltage, let current, !(external == false && current > 0) {
            battery = PowerMetric(voltage * current, quality: .estimated, source: "AppleSmartBattery.Voltage × \(currentField)", at: date)
        }
        if external == false, let watts = battery.value, watts <= 0 {
            system = PowerMetric(-watts, quality: .estimated, source: "电池放电功率（设备边界估算）", at: date)
        }
        // Never subtract measurements from different source families just to complete a power-flow equation.
        if system.value == nil, input.quality == .telemetry, battery.quality == .telemetry,
           let i = input.value, let b = battery.value, i - b >= 0, i - b <= 400 {
            system = PowerMetric(i-b, quality: .estimated, source: "同批遥测：输入 − 电池净功率", at: date)
        }
        var percent: Int?
        if let c = number(p["Current Capacity"], range: 0...100_000), let m = number(p["Max Capacity"], range: 1...100_000), c <= m {
            percent = Int((100*c/m).rounded())
        } else if number(r["MaxCapacity"], range: 100...100) != nil {
            percent = number(r["CurrentCapacity"], range: 0...100).map { Int($0.rounded()) }
        }
        let minutesKey = charging == true ? "Time to Full Charge" : external == false ? "Time to Empty" : ""
        let minutes = number(p[minutesKey], range: 1...1440).map(Int.init)
        return PowerSnapshot(timestamp: date, hasBattery: true, externalConnected: external, isCharging: charging, isFull: full,
            percent: percent, input: input, battery: battery, system: system,
            adapterWatts: external == true ? number(adapter["Watts"], range: 1...500) : nil,
            cycleCount: number(r["CycleCount"], range: 0...100_000).map(Int.init), voltage: voltage, amperage: current,
            minutesRemaining: minutes, condition: p["BatteryHealth"] as? String)
    }

    public static func health(from data: Data, at date: Date = Date()) throws -> HealthReport {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = root?["SPPowerDataType"] as? [[String: Any]] ?? []
        let health = items.compactMap { $0["sppower_battery_health_info"] as? [String: Any] }.first ?? [:]
        let text = health["sppower_battery_health_maximum_capacity"] as? String
        let capacity = text.flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
        return HealthReport(date: date, maximumCapacity: capacity.flatMap { (0...100).contains($0) ? $0 : nil },
            condition: health["sppower_battery_health"] as? String,
            cycleCount: number(health["sppower_battery_cycle_count"], range: 0...100_000).map(Int.init))
    }

    private static func metric(_ raw: Any?, key: String, date: Date, signed: Bool) -> PowerMetric {
        let value = signed ? signedNumber(raw, range: -400_000...400_000) : number(raw, range: 0...400_000)
        return PowerMetric(value.map { $0 / 1000 }, quality: .telemetry, source: key, at: date)
    }
    private static func number(_ raw: Any?, range: ClosedRange<Double>) -> Double? {
        guard let raw, !(raw is Bool && CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID()),
              let n = raw as? NSNumber else { return nil }
        let v = n.doubleValue; return v.isFinite && range.contains(v) ? v : nil
    }
    private static func signedNumber(_ raw: Any?, range: ClosedRange<Double>) -> Double? {
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let value = n.doubleValue > Double(Int64.max) ? Double(n.int64Value) : n.doubleValue
        return value.isFinite && range.contains(value) ? value : nil
    }
}
