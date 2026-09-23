import Foundation
import PowerCore
import PowerHardware

struct Report: Codable { var snapshot: PowerSnapshot; var health: HealthReport? }
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
let report = Report(snapshot: PowerReader.read(), health: try? PowerReader.readHealth())
do { print(String(decoding: try encoder.encode(report), as: UTF8.self)) }
catch { fputs("Unable to encode power report\n", stderr); exit(1) }
