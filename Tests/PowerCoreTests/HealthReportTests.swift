import Foundation
import Testing
@testable import PowerCore

struct HealthReportTests {
    private let date = Date(timeIntervalSince1970:1_700_000_000)

    private func report(_ info: [String:Any]) throws -> HealthReport {
        try PowerParser.health(from:JSONSerialization.data(withJSONObject:["SPPowerDataType":[["sppower_battery_health_info":info]]]),at:date)
    }

    @Test func nestedSystemReportUsesHealthRatherThanChargePercentage() throws {
        let raw: [String:Any] = ["SPPowerDataType":[["_items":[[
            "sppower_battery_charge_info":["sppower_battery_state_of_charge":42],
            "sppower_battery_health_info":["sppower_battery_health_maximum_capacity":" 98%\n","sppower_battery_health":"Good","sppower_battery_cycle_count":144]
        ]]]]]
        let result = try PowerParser.health(from:JSONSerialization.data(withJSONObject:raw),at:date)
        #expect(result.maximumCapacity == 98)
        #expect(result.conditionLabel == "正常")
        #expect(result.cycleCount == 144)
        #expect(result.hasData)
        #expect(result.date == date)
    }

    @Test func integerHealthPercentageAndRealZeroRemainValid() throws {
        #expect(try report(["sppower_battery_health_maximum_capacity":97]).maximumCapacity == 97)
        let zero = try report(["sppower_battery_health_maximum_capacity":0,"sppower_battery_cycle_count":0])
        #expect(zero.maximumCapacity == 0)
        #expect(zero.cycleCount == 0)
        #expect(zero.hasData)
    }

    @Test func invalidHealthIsUnknownInsteadOfZeroOrRoundedPercentage() throws {
        for raw: Any in [true,-1,101,99.5,"unknown","98.5%"] {
            let result = try report(["sppower_battery_health_maximum_capacity":raw])
            #expect(result.maximumCapacity == nil)
            #expect(!result.hasData)
        }
    }

    @Test func missingReportAndEmptyConditionDoNotCreateHealthPlaceholders() throws {
        let empty = try report(["sppower_battery_health":" \n ","sppower_battery_cycle_count":true])
        #expect(empty.condition == nil)
        #expect(empty.cycleCount == nil)
        #expect(!empty.hasData)
        let chargeOnly = try PowerParser.health(from:Data(#"{"SPPowerDataType":[{"sppower_battery_charge_info":{"sppower_battery_state_of_charge":100}}]}"#.utf8))
        #expect(chargeOnly.maximumCapacity == nil)
        #expect(!chargeOnly.hasData)
    }

    @Test func emptySectionsDoNotHideLaterBatteryHealth() throws {
        let raw = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{}},{"_items":[{"sppower_battery_health_info":{"sppower_battery_health":"Service Recommended"}}]}]}"#.utf8)
        let result = try PowerParser.health(from:raw)
        #expect(result.conditionLabel == "建议维修")
        #expect(result.hasData)
        #expect(result.maximumCapacity == nil)
    }

    @Test func existingArchivedHealthReportsRemainReadable() throws {
        let original = HealthReport(date:date,maximumCapacity:91,condition:"Good",cycleCount:750)
        let restored = try JSONDecoder().decode(HealthReport.self,from:JSONEncoder().encode(original))
        #expect(restored == original)
        #expect(restored.hasData)
    }
}
