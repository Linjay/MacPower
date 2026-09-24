import Foundation
import Testing
@testable import PowerCore

struct EnergyModeTests {
    @Test func modernPoliciesRemainSeparateForEachPowerSource() {
        let profiles = EnergyModeProfiles.parse("""
        Battery Power:
         powermode 1
         sleep 1
        AC Power:
         powermode 2
        """)
        #expect(profiles.mode(externalConnected: false) == .lowPower)
        #expect(profiles.mode(externalConnected: true) == .highPower)
        #expect(profiles.mode(externalConnected: nil) == .unknown)
    }

    @Test func allModernModesAndFutureValues() {
        for (value, expected) in [("0", EnergyMode.automatic), ("1", .lowPower), ("2", .highPower), ("3", .unknown), ("-1", .unknown), ("yes", .unknown)] {
            let profiles = EnergyModeProfiles.parse("Battery Power:\n powermode \(value)")
            #expect(profiles.battery == expected)
            #expect(profiles.adapter == .unknown)
        }
    }

    @Test func legacyPoliciesAndContradictions() {
        for (fields, expected) in [
            ("lowpowermode 0", EnergyMode.automatic),
            ("lowpowermode 1", .lowPower),
            ("lowpowermode 2", .highPower),
            ("lowpowermode 0\n highpowermode 1", .highPower),
            ("lowpowermode 1\n highpowermode 1", .unknown),
            ("highpowermode 0", .unknown),
            ("lowpowermode -1", .unknown),
            ("lowpowermode 0\n highpowermode 9", .unknown)
        ] {
            #expect(EnergyModeProfiles.parse("Battery Power:\n \(fields)").battery == expected)
        }
    }

    @Test func absentOrMalformedPoliciesNeverBecomeAutomatic() {
        #expect(EnergyModeProfiles.parse("").battery == .unknown)
        #expect(EnergyModeProfiles.parse("Battery Power:\n sleep 1").battery == .unknown)
        #expect(EnergyModeProfiles.parse("Battery Power:\n powermode\n lowpowermode 0").battery == .unknown)
        #expect(EnergyModeProfiles.parse("Battery Power:\n powermode 99\n lowpowermode 0").battery == .unknown)
        #expect(EnergyModeProfiles.parse("Battery Power:\n sleep 1\nUPS Power:\n powermode 2").battery == .unknown)
    }

    @Test func modernPolicyTakesPrecedenceOverLegacyAlias() {
        #expect(EnergyModeProfiles.parse("Battery Power:\n powermode 0\n lowpowermode 1").battery == .automatic)
    }

    @Test func dischargingOnACUsesACPolicyAndInactiveStatesHaveNoModeColor() {
        let profiles = EnergyModeProfiles.parse("Battery Power:\n powermode 1\nAC Power:\n powermode 2")
        let snapshot = PowerParser.parse(registry: ["ExternalConnected": true, "PowerTelemetryData": ["BatteryPower": -10_000]])
        #expect(snapshot.state == .supplement)
        #expect(snapshot.state.showsEnergyMode)
        #expect(profiles.mode(externalConnected: snapshot.externalConnected) == .highPower)
        #expect(PowerState.battery.showsEnergyMode)
        for state in [PowerState.charging, .full, .idle, .updating, .stale, .sleeping, .unavailable] {
            #expect(!state.showsEnergyMode)
        }
    }
}
