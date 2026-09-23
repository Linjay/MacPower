import Foundation
import IOKit
import IOKit.ps
import PowerCore

public enum PowerReader {
    public static func read() -> PowerSnapshot {
        let date = Date()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return .unavailable(at: date) }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let registry = properties?.takeRetainedValue() as? [String: Any] else { return .unavailable(at: date) }
        var description: [String: Any] = [:]
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                if let detail = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                   detail["Type"] as? String == "InternalBattery" { description = detail; break }
            }
        }
        return PowerParser.parse(registry: registry, source: description, at: date)
    }

    /// Low-frequency, bounded system report. Raw report (which can contain IDs) is never persisted or logged.
    public static func readHealth() throws -> HealthReport {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json", "-detailLevel", "mini"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline:.now()+12, execute:watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); watchdog.cancel()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return try PowerParser.health(from: data)
    }
}

public final class PowerEventObserver {
    private var source: CFRunLoopSource?
    private let callback: () -> Void
    public init(callback: @escaping () -> Void) {
        self.callback = callback
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerEventObserver>.fromOpaque(context).takeUnretainedValue().callback()
        }, pointer)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }
    deinit { if let source { CFRunLoopSourceInvalidate(source) } }
}
