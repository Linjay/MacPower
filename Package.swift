// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacPower",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacPower", targets: ["MacPower"]),
        .executable(name: "MacPowerProbe", targets: ["MacPowerProbe"])
    ],
    targets: [
        .target(name: "PowerCore"),
        .target(name: "PowerHardware", dependencies: ["PowerCore"]),
        .target(name: "UpdateCore"),
        .executableTarget(name: "MacPower", dependencies: ["PowerCore", "PowerHardware", "UpdateCore"]),
        .executableTarget(name: "MacPowerProbe", dependencies: ["PowerCore", "PowerHardware"]),
        .testTarget(name: "PowerCoreTests", dependencies: ["PowerCore"]),
        .testTarget(name: "UpdateCoreTests", dependencies: ["UpdateCore"])
    ],
    swiftLanguageModes: [.v5]
)
