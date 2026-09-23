import Foundation
import Testing
@testable import PowerCore

struct PowerCoreTests {
    let epoch = Date(timeIntervalSince1970:1_700_000_000)
    func sample(input:Any? = 61_600,battery:Any? = 27_600,load:Any? = 34_000,external:Bool = true,current:Int = 2200,offset:Double = 0) -> PowerSnapshot {
        var telemetry: [String:Any] = [:]
        telemetry["SystemPowerIn"] = input;telemetry["BatteryPower"] = battery;telemetry["SystemLoad"] = load
        return PowerParser.parse(registry:["PowerTelemetryData":telemetry,"ExternalConnected":external,"IsCharging":external && current > 0,"Voltage":12_500,"InstantAmperage":current,"CurrentCapacity":65,"MaxCapacity":100,"AdapterDetails":["Watts":65],"CycleCount":144],at:epoch.addingTimeInterval(offset))
    }
    @Test func testChargingKeepsAdapterCapabilitySeparateFromMeasuredInput() {
        let s = sample()
        #expect(s.adapterWatts == 65);#expect(s.input.value == 61.6)
        #expect(s.battery.value == 27.6);#expect(s.system.value == 34)
        #expect(s.percent == 65);#expect(s.state == .charging)
    }
    @Test func testUnsignedTwoComplementDischargeIsDecodedWithoutLosingSign() {
        let wrapped = NSNumber(value:UInt64(bitPattern:Int64(-15_000)))
        let s = sample(input:30_000,battery:wrapped,load:45_000,current:-1200)
        #expect(s.battery.value == -15);#expect(s.state == .supplement)
        #expect(s.battery.formatted(signed:true) == "−15.0")
    }
    @Test func testUnplugDiscardsStalePositiveTelemetryAndUsesSignedBatteryEstimate() {
        let s = sample(external:false,current:-1000)
        #expect(s.adapterWatts == nil);#expect(s.input.value == 0)
        #expect(s.battery.value == -12.5);#expect(s.battery.quality == .estimated)
        #expect(s.system.value == 12.5);#expect(s.system.quality == .estimated)
        #expect(s.state == .battery)
    }
    @Test func testUnplugWithOldPositiveCurrentDoesNotClaimChargingOrZeroPower() {
        let s = sample(external:false,current:1000)
        #expect(s.battery.value == nil);#expect(s.system.value == nil)
        #expect(s.battery.formatted() == "—")
    }
    @Test func testMissingInputDoesNotUseAdapterRatingOrFakeSystemLoad() {
        let s = sample(input:nil,load:nil)
        #expect(s.adapterWatts == 65);#expect(s.input.value == nil);#expect(s.system.value == nil)
        #expect(s.battery.value == 27.6)
    }
    @Test func testSystemFallbackRequiresCompatibleTelemetryAndNonNegativeDifference() {
        #expect(sample(load:nil).system.value == 34)
        #expect(sample(load:nil).system.quality == .estimated)
        #expect(sample(input:1000,load:nil).system.value == nil)
        #expect(sample(battery:nil,load:nil).system.value == nil) // V × I must not be mixed into this subtraction.
    }
    @Test func testImpossibleValuesAndBooleanTelemetryRemainUnavailable() {
        let s = sample(input:true,battery:Double.nan,load:Double.infinity)
        #expect(s.input.value == nil);#expect(s.system.value == nil)
        #expect(s.battery.quality == .estimated)
        #expect(sample(input:500_001).input.value == nil)
    }
    @Test func testNoServiceMeansUnavailableNotEmptyBattery() {
        let s = PowerParser.parse(registry:nil,at:epoch)
        #expect(!(s.hasBattery));#expect(s.percent == nil);#expect(s.battery.value == nil)
        #expect(s.state == .unavailable)
    }
    @Test func testFallbackCurrentKeepsItsActualFieldName() {
        let s = PowerParser.parse(registry:["ExternalConnected":false,"Voltage":12_000,"Amperage":-1000],at:epoch)
        #expect(s.battery.value == -12)
        #expect(s.battery.quality == .estimated)
        #expect(s.battery.source == "AppleSmartBattery.Voltage × Amperage")
        #expect(s.input.source == "系统电源状态 · 未接入外部电源")
    }
    @Test func testZeroIsAValidMeasurementAndFormattingNeverShowsNegativeZero() {
        #expect(sample(battery:0).battery.value == 0)
        #expect(PowerMetric(-0.01,quality:.telemetry,source:"fixture",at:epoch).formatted(signed:true) == "0.0")
        #expect(sample().battery.formatted(signed:true) == "+27.6")
    }
    @Test func testBatteryPercentageIsNotBatteryHealthAndUnknownTimeIsIgnored() throws {
        let p = PowerParser.parse(registry:["ExternalConnected":false,"CurrentCapacity":50,"MaxCapacity":100],source:["Current Capacity":20,"Max Capacity":80,"Time to Empty":65535],at:epoch)
        #expect(p.percent == 25);#expect(p.minutesRemaining == nil)
        let raw = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"98%","sppower_battery_health":"Good","sppower_battery_cycle_count":144}}]}"#.utf8)
        let health = try PowerParser.health(from:raw,at:epoch)
        #expect(health.maximumCapacity == 98);#expect(health.conditionLabel == "正常")
    }
    @Test func testFullAndIdleAreNotGuessedFromBatteryPercentage() {
        var s = sample(battery:0,current:0);s.isFull = true
        #expect(s.state == .full)
        s.isFull = false;s.isCharging = false;s.percent = 100
        #expect(s.state == .idle)
    }
    @Test func testSourceChangeNeedsTwoConsistentSamples() {
        var gate = SourceStabilizer()
        #expect(gate.accept(sample()) == .charging)
        #expect(gate.accept(sample(external:false,current:-1000)) == .updating)
        #expect(gate.accept(sample(external:false,current:-1000,offset:1)) == .battery)
        #expect(gate.accept(sample(offset:2)) == .updating)
    }
    @Test func testThemeMatrixAndCorruptPreferencesFallBackToSystem() {
        #expect(AppearanceMode.system.resolved(systemIsDark:true) == .dark)
        #expect(AppearanceMode.system.resolved(systemIsDark:false) == .light)
        #expect(AppearanceMode.light.resolved(systemIsDark:true) == .light)
        #expect(AppearanceMode.dark.resolved(systemIsDark:false) == .dark)
        #expect(Preferences.decode(Data("corrupt".utf8)).appearance == .system)
        var p = Preferences();p.appearance = .dark
        #expect(Preferences.decode(try? JSONEncoder().encode(p)).appearance == .dark)
    }
    @Test func testHistoryIntegratesOnlyContinuousSamplesAndKeepsGaps() {
        var history = HistoryRecorder()
        history.record(sample(battery:36_000,offset:0),expectedInterval:5)
        history.record(sample(battery:36_000,offset:10),expectedInterval:5)
        #expect(abs((history.archive.points.reduce(0){$0+$1.chargedWh}) - (0.1)) <= 0.000001)
        history.record(sample(battery:36_000,offset:80),expectedInterval:5)
        #expect(abs((history.archive.points.reduce(0){$0+$1.chargedWh}) - (0.1)) <= 0.000001)
        #expect(history.archive.points.first?.segment != history.archive.points.last?.segment)
    }
    @Test func testHistorySourceChangesBreakLinesAndEnergyIntegration() {
        var h = HistoryRecorder();h.record(sample(),expectedInterval:5)
        h.record(sample(battery:nil,offset:5),expectedInterval:5)
        #expect(h.archive.points.count == 2)
        #expect(h.archive.points[0].segment != h.archive.points[1].segment)
        #expect(h.archive.points.reduce(0){$0+$1.coveredSeconds} == 0)
    }
    @Test func testEnergySeparatesChargeAndDischargeAcrossZero() {
        let energy = HistoryRecorder.splitEnergy(from:20,to:-20,seconds:3600)
        #expect(abs((energy.charged) - (5)) <= 0.000001)
        #expect(abs((energy.discharged) - (5)) <= 0.000001)
    }
    @Test func testMinuteAggregationPreservesExtremaAndRejectsReorderedSamples() {
        var h = HistoryRecorder()
        h.record(sample(battery:20_000,offset:0),expectedInterval:5)
        h.record(sample(battery:40_000,offset:5),expectedInterval:5)
        h.record(sample(battery:90_000,offset:2),expectedInterval:5)
        #expect(h.archive.points.count == 1)
        #expect(h.archive.points[0].battery.mean == 30)
        #expect(h.archive.points[0].battery.minimum == 20)
        #expect(h.archive.points[0].battery.maximum == 40)
    }
    @Test func testArchiveRoundTripRetentionAndCSVLeaveMissingColumnsEmpty() throws {
        var h = HistoryRecorder();h.record(sample(input:nil,load:nil),expectedInterval:5)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let url = dir.appendingPathComponent("history.json")
        try h.archive.save(to:url)
        var read = try HistoryArchive.load(from:url)
        #expect(read.points == h.archive.points)
        let csv = HistoryExport.csv(read.points).split(separator:"\n")[1].split(separator:",",omittingEmptySubsequences:false)
        #expect(csv[3] == "");#expect(csv[6] == "27.6000");#expect(csv[9] == "")
        read.prune(now:epoch.addingTimeInterval(8*86_400),days:7);#expect(read.points.isEmpty)
    }
    @Test func testSleepAndRecordPauseNeverBridgeEnergyGap() {
        var h = HistoryRecorder();h.record(sample(),expectedInterval:5);h.breakContinuity()
        h.record(sample(offset:5),expectedInterval:5)
        #expect(h.archive.points.reduce(0){$0+$1.chargedWh} == 0)
        #expect(h.archive.points.count == 2)
    }
    @Test func testHealthHistoryUpdatesDailyAndIgnoresUnavailableValues() {
        var archive = HistoryArchive()
        archive.addHealth(HealthReport(date:epoch,maximumCapacity:98,condition:"Good",cycleCount:144))
        archive.addHealth(HealthReport(date:epoch.addingTimeInterval(10),maximumCapacity:97,condition:"Good",cycleCount:144))
        archive.addHealth(HealthReport(date:epoch.addingTimeInterval(86_400),maximumCapacity:nil,condition:nil,cycleCount:nil))
        #expect(archive.health.count == 1);#expect(archive.health[0].maximumCapacity == 97)
    }
    @Test func testRemindersAreOptInDeduplicatedAndRearmWithHysteresis() {
        var policy = ReminderPolicy(), p = Preferences(), s = sample(external:false,current:-1000)
        s.percent = 19
        #expect(policy.evaluate(s,preferences:p).isEmpty)
        p.lowBatteryReminder = true
        #expect(policy.evaluate(s,preferences:p) == [.low])
        #expect(policy.evaluate(s,preferences:p).isEmpty)
        s.percent = 22;#expect(policy.evaluate(s,preferences:p).isEmpty)
        s.percent = 25;_ = policy.evaluate(s,preferences:p)
        s.percent = 19;#expect(policy.evaluate(s,preferences:p) == [.low])
    }
    @Test func testSupplementReminderRequiresThirtySecondsAndResetsOnInterruption() {
        var policy = ReminderPolicy(), p = Preferences();p.supplementReminder = true
        #expect(policy.evaluate(sample(battery:-15_000,current:-1000),preferences:p).isEmpty)
        #expect(policy.evaluate(sample(battery:-15_000,current:-1000,offset:29),preferences:p).isEmpty)
        #expect(policy.evaluate(sample(battery:-15_000,current:-1000,offset:30),preferences:p) == [.supplement])
        #expect(policy.evaluate(sample(battery:-15_000,current:-1000,offset:31),preferences:p).isEmpty)
    }
}
