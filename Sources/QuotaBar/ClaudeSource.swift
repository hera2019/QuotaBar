import Foundation

/// Claude has no local API for plan usage, so Claude itself writes this file before it reports back
/// (see the CLAUDE.md rule in the README).
enum ClaudeSource {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/QuotaWindow/claude-usage.json")

    static func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    static func load() -> Result<ProviderUsage, SourceError> {
        guard let data = try? Data(contentsOf: fileURL) else {
            return .failure(.message(L10n.claudeNoData))
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let windows = obj["windows"] as? [String: Any] else {
            return .failure(.malformed)
        }
        func window(_ key: String) -> LimitWindow? {
            guard let w = windows[key] as? [String: Any],
                  let used = (w["usedPercent"] as? NSNumber)?.doubleValue else { return nil }
            return LimitWindow(usedPercent: used, resetsAt: parseDate(w["resetsAt"]))
        }
        let usage = ProviderUsage(
            fiveHour: window("fiveHour"),
            weekly: window("weekly"),
            updatedAt: parseDate(obj["updatedAt"]) ?? modificationDate() ?? Date()
        )
        if usage.fiveHour == nil && usage.weekly == nil { return .failure(.malformed) }
        return .success(usage)
    }

    /// Accepts ISO 8601 (with or without fractional seconds) or Unix seconds.
    static func parseDate(_ value: Any?) -> Date? {
        if let n = value as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        guard let s = value as? String else { return nil }
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: s) { return d }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: s)
    }
}

enum SourceError: Error {
    case notFound, timedOut, malformed, launchFailed
    case message(String)

    var text: String {
        switch self {
        case .notFound: return L10n.codexNotFound
        case .timedOut: return L10n.codexTimedOut
        case .malformed: return L10n.malformed
        case .launchFailed: return L10n.codexLaunchFailed
        case .message(let m): return m
        }
    }
}
