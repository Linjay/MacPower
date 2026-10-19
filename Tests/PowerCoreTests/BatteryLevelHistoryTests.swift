import Foundation
import Testing
@testable import PowerCore

struct BatteryLevelHistoryTests {
    let epoch = Date(timeIntervalSince1970:1_700_000_040)
    func sample(_ percent: Int?, at seconds: Double) -> PowerSnapshot {
        var result = PowerSnapshot.unavailable(at:epoch.addingTimeInterval(seconds))
        result.hasBattery = true; result.externalConnected = false; result.percent = percent
        return result
    }
    @Test func minuteKeepsLastActualReadingAndTimestampRatherThanMean() {
        var recorder = HistoryRecorder()
        recorder.record(sample(51,at:0),expectedInterval:5)
        recorder.record(sample(50,at:5),expectedInterval:5)
        let level = recorder.archive.points.first?.batteryLevel
        #expect(recorder.archive.points.count == 1)
        #expect(level?.percent == 50)
        #expect(level?.sampledAt == epoch.addingTimeInterval(5))
        #expect(level?.coveredSeconds == 5)
        #expect(recorder.archive.points.first?.battery.mean == nil)
    }
    @Test func missingAndInvalidPercentagesSplitSegmentsWithinTheSameMinute() {
        var recorder = HistoryRecorder()
        for (index,percent) in [50,nil,49,101,0,-1,100].enumerated() {
            recorder.record(sample(percent,at:Double(index)*5),expectedInterval:5)
        }
        let records = recorder.archive.points.compactMap(\.batteryLevel)
        #expect(records.map(\.percent) == [50,49,0,100])
        #expect(Set(records.map(\.segment)).count == 4)
        #expect(records.allSatisfy { $0.coveredSeconds == 0 })
    }
    @Test func gapsPauseAndRestartNeverBridgeBatteryLevel() {
        var recorder = HistoryRecorder()
        recorder.record(sample(70,at:0),expectedInterval:5)
        recorder.record(sample(69,at:60),expectedInterval:5)
        recorder.breakContinuity()
        recorder.record(sample(68,at:65),expectedInterval:5)
        var restarted = HistoryRecorder(archive:recorder.archive)
        restarted.record(sample(67,at:70),expectedInterval:5)
        let records = restarted.archive.points.compactMap(\.batteryLevel)
        #expect(Set(records.map(\.segment)).count == 4)
        #expect(records.allSatisfy { $0.coveredSeconds == 0 })
    }
    @Test func powerProvenanceChangesDoNotBreakValidLevelContinuity() {
        var recorder = HistoryRecorder()
        recorder.record(sample(50,at:0),expectedInterval:5)
        var next = sample(49,at:5)
        next.battery = PowerMetric(-10,quality:.estimated,source:"fixture",at:next.timestamp)
        recorder.record(next,expectedInterval:5)
        let points = recorder.archive.points
        #expect(points.count == 2)
        #expect(points[0].segment != points[1].segment)
        #expect(points[0].batteryLevel?.segment == points[1].batteryLevel?.segment)
        #expect(points[1].batteryLevel?.coveredSeconds == 5)
    }
    @Test func reorderedAndBatterylessSamplesCannotInventReadings() {
        var recorder = HistoryRecorder()
        recorder.record(sample(50,at:5),expectedInterval:5)
        recorder.record(sample(60,at:0),expectedInterval:5)
        var absent = sample(0,at:10); absent.hasBattery = false
        recorder.record(absent,expectedInterval:5)
        recorder.record(sample(49,at:15),expectedInterval:5)
        #expect(recorder.archive.points.compactMap(\.batteryLevel).map(\.percent) == [50,49])
        #expect(recorder.archive.points.last?.batteryLevel?.coveredSeconds == 0)
    }
    @Test func oldArchiveDecodesWithoutLevelAndNewArchiveRoundTrips() throws {
        var recorder = HistoryRecorder(); recorder.record(sample(0,at:0),expectedInterval:5)
        let encoded = try JSONEncoder().encode(recorder.archive)
        let decoded = try JSONDecoder().decode(HistoryArchive.self,from:encoded)
        #expect(decoded.points == recorder.archive.points)
        var object = try #require(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        var points = try #require(object["points"] as? [[String:Any]])
        points[0].removeValue(forKey:"batteryLevel"); object["points"] = points
        let old = try JSONDecoder().decode(HistoryArchive.self,from:JSONSerialization.data(withJSONObject:object))
        #expect(old.version == 1); #expect(old.points.count == 1)
        #expect(old.points[0].batteryLevel == nil)
    }
    @Test func csvAppendsActualLevelAndLeavesOldOrMissingLevelEmpty() {
        var recorder = HistoryRecorder()
        recorder.record(sample(nil,at:0),expectedInterval:5)
        recorder.record(sample(0,at:5),expectedInterval:5)
        let rows = HistoryExport.csv(recorder.archive.points).split(separator:"\n").map { $0.split(separator:",",omittingEmptySubsequences:false) }
        #expect(rows[0].count == 25); #expect(rows[0][21] == "battery_percent")
        #expect(rows[1][21] == ""); #expect(rows[1][22] == ""); #expect(rows[1][24] == "")
        #expect(rows[2][21] == "0"); #expect(rows[2][22] == "2023-11-14T22:14:05Z")
    }
    @Test func trendSummaryUsesActualEndpointsClipsCoverageAndDoesNotSelectLongGaps() {
        var recorder = HistoryRecorder()
        recorder.record(sample(50,at:0),expectedInterval:5)
        recorder.record(sample(49,at:5),expectedInterval:5)
        recorder.record(sample(48,at:300),expectedInterval:5)
        let trend = BatteryLevelTrend(points:recorder.archive.points,start:epoch,end:epoch.addingTimeInterval(300))
        #expect(trend.first?.percent == 49); #expect(trend.last?.percent == 48)
        #expect(trend.change == -1); #expect(trend.coverage == 1)
        #expect(trend.nearest(to:epoch.addingTimeInterval(150)) == nil)
        #expect(trend.nearest(to:epoch.addingTimeInterval(300))?.percent == 48)
        let single = BatteryLevelTrend(points:recorder.archive.points,start:epoch.addingTimeInterval(299),end:epoch.addingTimeInterval(300))
        #expect(single.change == nil); #expect(single.coverage == 0)
    }
    @Test func draftLevelArchiveMigratesActualReadingsWithoutInventingPower() throws {
        var recorder = HistoryRecorder(); recorder.record(sample(nil,at:0),expectedInterval:5)
        var object = try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(recorder.archive)) as? [String:Any])
        let segment = UUID()
        object["batteryLevels"] = [0,5,60].enumerated().map { index,offset in
            ["date":epoch.addingTimeInterval(Double(offset)).timeIntervalSinceReferenceDate,
             "percent":[100,99,98][index],"state":"battery","segment":segment.uuidString,"coveredSeconds":Double(offset == 0 ? 0 : 5)] as [String:Any]
        }
        let migrated = try JSONDecoder().decode(HistoryArchive.self,from:JSONSerialization.data(withJSONObject:object))
        #expect(migrated.points.count == 2)
        #expect(migrated.points.first?.id == recorder.archive.points.first?.id)
        #expect(migrated.points.compactMap(\.batteryLevel).map(\.percent) == [99,98])
        #expect(migrated.points.last?.batteryLevel?.sampledAt == epoch.addingTimeInterval(60))
        #expect(migrated.points.last?.input.mean == nil)
        #expect(migrated.points.last?.battery.mean == nil)
        #expect(migrated.points.last?.samples == 0)
        let saved = try JSONEncoder().encode(migrated)
        let reopened = try JSONDecoder().decode(HistoryArchive.self,from:saved)
        #expect(reopened.points == migrated.points)
        #expect((try JSONSerialization.jsonObject(with:saved) as? [String:Any])?["batteryLevels"] == nil)
    }
    @Test func draftMigrationPreservesGapsAndRejectsInvalidPercentages() throws {
        let first = UUID(), second = UUID()
        let levels: [[String:Any]] = [(0,50,first),(5,49,second),(10,101,second)].map { offset,percent,segment in
            ["date":epoch.addingTimeInterval(Double(offset)).timeIntervalSinceReferenceDate,
             "percent":percent,"state":"battery","segment":segment.uuidString,"coveredSeconds":0]
        }
        let object: [String:Any] = ["version":1,"points":[],"health":[],"batteryLevels":levels]
        let migrated = try JSONDecoder().decode(HistoryArchive.self,from:JSONSerialization.data(withJSONObject:object))
        let records = migrated.points.compactMap(\.batteryLevel)
        #expect(records.map(\.percent) == [50,49])
        #expect(records.map(\.segment) == [first,second])
        #expect(records.allSatisfy { $0.coveredSeconds == 0 })
    }
}
