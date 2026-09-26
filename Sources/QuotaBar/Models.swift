import AppKit

/// One quota window: percent used plus when it resets.
struct LimitWindow {
    var usedPercent: Double
    var resetsAt: Date?

    /// Once the reset time has passed, treat it as zero even if the data has not caught up yet.
    func effective(now: Date = Date()) -> LimitWindow {
        if let r = resetsAt, r <= now { return LimitWindow(usedPercent: 0, resetsAt: nil) }
        return self
    }
}

struct ProviderUsage {
    var fiveHour: LimitWindow?
    var weekly: LimitWindow?
    var updatedAt: Date
}

struct ProviderState {
    var usage: ProviderUsage?
    var error: String?
    var failed: Bool { usage == nil && error != nil }
}

enum Span: String {
    case fiveHour = "5H", weekly = "7D"
}

enum PercentageMode: String, CaseIterable {
    case used, remaining

    var title: String {
        switch self {
        case .used: return L10n.usedMode
        case .remaining: return L10n.remainingMode
        }
    }
}

/// Everything needed to draw one ring.
struct RingInfo {
    let provider: String   // "GPT" / "Claude"
    let span: Span
    let tint: NSColor
    let window: LimitWindow?
    let failed: Bool
    let caption: String     // line under the ring in the Card style
    let percentageMode: PercentageMode

    var displayedPercent: Int? {
        window.map { window in
            let value = percentageMode == .used ? window.usedPercent : 100 - window.usedPercent
            return Int(max(0, min(100, value)).rounded())
        }
    }

    /// The arc shows what is left; the number follows the selected percentage mode.
    var remaining: Double? {
        window.map { max(0, min(1, 1 - $0.usedPercent / 100)) }
    }
}

enum DisplayStyle: String, CaseIterable {
    case menuBar, strip, card

    var title: String {
        switch self {
        case .menuBar: return L10n.styleMenuBar
        case .strip: return L10n.styleStrip
        case .card: return L10n.styleCard
        }
    }
}

enum Tint {
    static let gpt = NSColor(srgbRed: 0.06, green: 0.64, blue: 0.50, alpha: 1)    // #10A37F
    static let claude = NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1) // #D97757
}

enum Fmt {
    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    private static let full: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f
    }()

    /// Time of day within 24 hours, otherwise the date.
    static func short(_ d: Date, now: Date = Date()) -> String {
        d.timeIntervalSince(now) < 24 * 3600 ? time.string(from: d) : day.string(from: d)
    }

    static func long(_ d: Date) -> String { full.string(from: d) }
}
