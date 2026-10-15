import Foundation

/// The last observed state of charge in a minute bucket, independent of power telemetry.
public struct BatteryLevelRecord: Codable, Equatable, Identifiable, Sendable {
    public var percent: Int
    public var sampledAt: Date
    public var segment: UUID
    public var coveredSeconds: Double = 0
    public var id: Date { sampledAt }
    public init(percent: Int, sampledAt: Date, segment: UUID) {
        self.percent = percent; self.sampledAt = sampledAt; self.segment = segment
    }
}

public struct BatteryLevelTrend: Equatable, Sendable {
    public let records: [BatteryLevelRecord]
    public let coverage: Int
    public var first: BatteryLevelRecord? { records.first }
    public var last: BatteryLevelRecord? { records.last }
    public var change: Int? {
        guard records.count > 1, let first, let last else { return nil }
        return last.percent - first.percent
    }
    public init(points: [HistoryPoint], start: Date, end: Date) {
        records = points.compactMap(\.batteryLevel).filter {
            (0...100).contains($0.percent) && $0.sampledAt >= start && $0.sampledAt <= end
        }.sorted { $0.sampledAt < $1.sampledAt }
        let seconds = records.reduce(0.0) {
            $0 + min(max(0, $1.coveredSeconds), $1.sampledAt.timeIntervalSince(start))
        }
        coverage = end > start ? min(100, Int(seconds / end.timeIntervalSince(start) * 100)) : 0
    }
    public func nearest(to date: Date) -> BatteryLevelRecord? {
        guard let record = records.min(by: { abs($0.sampledAt.timeIntervalSince(date)) < abs($1.sampledAt.timeIntervalSince(date)) }),
              abs(record.sampledAt.timeIntervalSince(date)) <= 60 else { return nil }
        return record
    }
}
