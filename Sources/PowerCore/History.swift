import Foundation

public struct MetricSummary: Codable, Equatable, Sendable {
    public var mean: Double?
    public var minimum: Double?
    public var maximum: Double?
    public var count: Int = 0
    public var source: String = "—"
    public var quality: Quality = .unavailable
    mutating func add(_ metric: PowerMetric) {
        guard let value = metric.value else { return }
        mean = ((mean ?? 0) * Double(count) + value) / Double(count+1)
        minimum = min(minimum ?? value, value); maximum = max(maximum ?? value, value)
        count += 1; source = metric.source; quality = metric.quality
    }
}

public struct HistoryPoint: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var date: Date
    public var lastSampleAt: Date
    public var segment: UUID
    public var state: PowerState
    public var input = MetricSummary()
    public var battery = MetricSummary()
    public var system = MetricSummary()
    public var samples = 0
    public var coveredSeconds = 0.0
    public var chargedWh = 0.0
    public var dischargedWh = 0.0
    public var inputWh = 0.0
    public var systemWh = 0.0
}

public struct HistoryArchive: Codable, Sendable {
    public var version = 1
    public var points: [HistoryPoint] = []
    public var health: [HealthReport] = []
    public init() {}
    public static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let data = try Data(contentsOf: url)
        // A normal 90-day minute archive can exceed 50 MB. Match the 140,000-point retention cap.
        guard data.count < 256_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
    public mutating func prune(now: Date, days: Int) {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        points.removeAll { $0.date < cutoff || $0.date > now.addingTimeInterval(120) }
        health.removeAll { $0.date < now.addingTimeInterval(-90*86_400) }
        // Bound memory even if a noisy source changes provenance on every sample.
        if points.count > 140_000 { points.removeFirst(points.count - 140_000) }
    }
    public mutating func addHealth(_ report: HealthReport) {
        guard report.maximumCapacity != nil else { return }
        if let index = health.lastIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: report.date) && $0.source == report.source }) {
            health[index] = report
        } else { health.append(report) }
    }
}

public struct HistoryRecorder: Sendable {
    public private(set) var archive: HistoryArchive
    private var previous: PowerSnapshot?
    private var segment = UUID()
    public init(archive: HistoryArchive = HistoryArchive()) { self.archive = archive }
    public mutating func breakContinuity() { previous = nil; segment = UUID() }
    public mutating func clear() { archive = HistoryArchive(); breakContinuity() }
    public mutating func prune(now: Date, days: Int) { archive.prune(now: now, days: days) }
    public mutating func addHealth(_ report: HealthReport) { archive.addHealth(report) }

    public mutating func record(_ sample: PowerSnapshot, expectedInterval: TimeInterval) {
        guard sample.hasBattery, sample.externalConnected != nil else { breakContinuity(); return }
        if let previous, sample.timestamp <= previous.timestamp { return }
        let gap = previous.map { sample.timestamp.timeIntervalSince($0.timestamp) } ?? .infinity
        let continuous = previous.map { old in
            gap <= max(1, expectedInterval) * 3 && old.externalConnected == sample.externalConnected &&
            signature(old.input) == signature(sample.input) && signature(old.battery) == signature(sample.battery) && signature(old.system) == signature(sample.system)
        } ?? false
        if !continuous { segment = UUID() }
        let minute = Date(timeIntervalSince1970: floor(sample.timestamp.timeIntervalSince1970 / 60) * 60)
        if archive.points.last?.date != minute || archive.points.last?.segment != segment {
            archive.points.append(HistoryPoint(date: minute, lastSampleAt: sample.timestamp, segment: segment, state: sample.state))
        }
        var point = archive.points.removeLast()
        point.input.add(sample.input); point.battery.add(sample.battery); point.system.add(sample.system)
        point.lastSampleAt = sample.timestamp; point.samples += 1
        if continuous, let old = previous {
            if let a = old.battery.value, let b = sample.battery.value {
                let energy = Self.splitEnergy(from: a, to: b, seconds: gap)
                point.chargedWh += energy.charged; point.dischargedWh += energy.discharged
                point.coveredSeconds += gap
            }
            if let a = old.input.value, let b = sample.input.value { point.inputWh += (a+b)/2 * gap/3600 }
            if let a = old.system.value, let b = sample.system.value { point.systemWh += (a+b)/2 * gap/3600 }
        }
        archive.points.append(point); previous = sample
    }

    private func signature(_ m: PowerMetric) -> String { "\(m.source)|\(m.quality.rawValue)|\(m.value != nil)" }
    public static func splitEnergy(from a: Double, to b: Double, seconds: Double) -> (charged: Double, discharged: Double) {
        guard seconds > 0 else { return (0,0) }
        if a >= 0 && b >= 0 { return ((a+b)/2*seconds/3600, 0) }
        if a <= 0 && b <= 0 { return (0, -(a+b)/2*seconds/3600) }
        let firstSeconds = seconds * abs(a)/(abs(a)+abs(b))
        let first = abs(a)*firstSeconds/2/3600, second = abs(b)*(seconds-firstSeconds)/2/3600
        return a > 0 ? (first,second) : (second,first)
    }
}

public enum HistoryExport {
    public static func csv(_ points: [HistoryPoint]) -> String {
        let iso = ISO8601DateFormatter()
        func value(_ v: Double?) -> String { v.map { String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "" }
        func quote(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let header = "minute_utc,last_sample_utc,state,input_w_mean,input_w_min,input_w_max,battery_w_mean,battery_w_min,battery_w_max,system_w_mean,system_w_min,system_w_max,battery_covered_seconds,charged_wh,discharged_wh,input_source,battery_source,system_source,input_quality,battery_quality,system_quality"
        let rows = points.map { p in
            [iso.string(from:p.date), iso.string(from:p.lastSampleAt), p.state.rawValue,
             value(p.input.mean), value(p.input.minimum), value(p.input.maximum), value(p.battery.mean), value(p.battery.minimum), value(p.battery.maximum),
             value(p.system.mean), value(p.system.minimum), value(p.system.maximum), value(p.coveredSeconds), value(p.chargedWh), value(p.dischargedWh),
             quote(p.input.source), quote(p.battery.source), quote(p.system.source),p.input.quality.rawValue,p.battery.quality.rawValue,p.system.quality.rawValue].joined(separator:",")
        }
        return "\u{FEFF}" + ([header] + rows).joined(separator:"\n") + "\n"
    }
}
