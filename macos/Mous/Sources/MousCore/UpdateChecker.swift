import Foundation

public enum UpdateChecker {
    public static let fallbackVersion = "0.1.3"

    public static func installedVersion(bundle: Bundle = .main) -> String {
        let raw = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallbackVersion : trimmed
    }

    public static func normalizedVersion(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }
        return value
    }

    /// Semver-ish dotted compare. `v0.1.3` equals `0.1.3`; missing parts count as 0.
    public static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionParts(lhs)
        let right = versionParts(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    public static func isRemoteNewer(installed: String, remote: String) -> Bool {
        compareVersions(installed, remote) == .orderedAscending
    }

    public static func versionParts(_ raw: String) -> [Int] {
        normalizedVersion(raw)
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { component in
                Int(component.prefix(while: \.isNumber)) ?? 0
            }
    }
}
