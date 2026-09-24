import Foundation

/// SemVer precedence: compare numeric components and prereleases; ignore build metadata.
public struct ReleaseVersion: Comparable, Sendable {
    public let number: String
    private let core: [Int]
    private let prerelease: [String]

    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let build = value.split(separator: "+", omittingEmptySubsequences: false)
        guard build.count <= 2,
              build.count == 1 || Self.validIdentifiers(String(build[1]), numericLeadingZeros: true) else { return nil }
        let parts = build[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3, numbers.allSatisfy({ Self.isNumber(String($0)) && ($0.count == 1 || $0.first != "0") }),
              numbers.allSatisfy({ Int($0) != nil }) else { return nil }
        if parts.count == 2 && !Self.validIdentifiers(String(parts[1]), numericLeadingZeros: false) { return nil }
        number = value
        core = numbers.map { Int($0)! }
        prerelease = parts.count == 2 ? parts[1].split(separator: ".").map(String.init) : []
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }
    private static func isNumber(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }
    private static func validIdentifiers(_ value: String, numericLeadingZeros: Bool) -> Bool {
        value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
                && (numericLeadingZeros || !isNumber(String(part)) || part.count == 1 || part.first != "0")
        }
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.core == rhs.core && lhs.prerelease == rhs.prerelease }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.core != rhs.core { return lhs.core.lexicographicallyPrecedes(rhs.core) }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let ln = isNumber(left), rn = isNumber(right)
            if ln && rn { return left.count == right.count ? left < right : left.count < right.count }
            if ln != rn { return ln }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
