import Foundation

public enum Reminder: String, Sendable { case low, charged, supplement }
public struct ReminderPolicy: Sendable {
    private var lowArmed = true
    private var chargedArmed = true
    private var supplementArmed = true
    private var supplementSince: Date?
    public init() {}
    public mutating func evaluate(_ snapshot: PowerSnapshot, preferences p: Preferences) -> [Reminder] {
        var events: [Reminder] = []
        guard let percent = snapshot.percent, snapshot.hasBattery else { supplementSince = nil; return [] }
        if percent > p.lowThreshold + 3 || snapshot.externalConnected == true { lowArmed = true }
        if percent < p.chargeThreshold - 3 || snapshot.externalConnected == false { chargedArmed = true }
        if !p.lowBatteryReminder { lowArmed = true }
        if !p.chargeReminder { chargedArmed = true }
        if p.lowBatteryReminder && lowArmed && snapshot.externalConnected == false && percent <= p.lowThreshold {
            lowArmed = false; events.append(.low)
        }
        if p.chargeReminder && chargedArmed && snapshot.externalConnected == true && percent >= p.chargeThreshold {
            chargedArmed = false; events.append(.charged)
        }
        if snapshot.state == .supplement {
            if supplementSince == nil { supplementSince = snapshot.timestamp }
            if p.supplementReminder && supplementArmed && snapshot.timestamp.timeIntervalSince(supplementSince!) >= 30 {
                supplementArmed = false; events.append(.supplement)
            }
        } else { supplementSince = nil; supplementArmed = true }
        return events
    }
    public mutating func resetContinuity() { supplementSince = nil }
}
