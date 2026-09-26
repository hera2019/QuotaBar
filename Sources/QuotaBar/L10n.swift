import Foundation

/// English by default; Simplified / Traditional Chinese when the system's first language is Chinese.
enum L10n {
    enum Lang { case en, zhHans, zhHant }

    static let lang: Lang = {
        guard let first = Locale.preferredLanguages.first?.lowercased(), first.hasPrefix("zh") else { return .en }
        let traditional = first.contains("hant") || ["zh-tw", "zh-hk", "zh-mo"].contains { first.hasPrefix($0) }
        return traditional ? .zhHant : .zhHans
    }()

    static func t(_ en: String, _ hans: String, _ hant: String) -> String {
        switch lang {
        case .en: return en
        case .zhHans: return hans
        case .zhHant: return hant
        }
    }

    // Display styles
    static var styleMenuBar: String { t("Menu Bar", "菜单栏", "選單列") }
    static var styleStrip: String { t("Thin Strip", "细条浮窗", "細條浮窗") }
    static var styleCard: String { t("Card", "标准浮窗", "標準浮窗") }

    // Ring captions
    static var failed: String { t("Failed", "读取失败", "讀取失敗") }
    static var wasReset: String { t("Reset", "已重置", "已重置") }
    static var notOnPlan: String { t("N/A", "无此额度", "無此額度") }

    static func percentage(_ label: String, _ percent: Int, mode: PercentageMode, resets: String?) -> String {
        let amount: String
        switch mode {
        case .used: amount = t("\(percent)% used", "已用 \(percent)%", "已用 \(percent)%")
        case .remaining: amount = t("\(percent)% remaining", "剩余 \(percent)%", "剩餘 \(percent)%")
        }
        let line = t("\(label)   \(amount)", "\(label)　\(amount)", "\(label)　\(amount)")
        guard let resets else { return line }
        return t("\(line) · resets \(resets)", "\(line) · \(resets) 重置", "\(line) · \(resets) 重置")
    }

    static func captionLine(_ label: String, _ caption: String) -> String {
        t("\(label)   \(caption)", "\(label)　\(caption)", "\(label)　\(caption)")
    }

    // Errors
    static var codexNotFound: String { t("codex not found (install the ChatGPT desktop app)", "找不到 codex（需安装 ChatGPT 桌面版）", "找不到 codex（需安裝 ChatGPT 桌面版）") }
    static var codexTimedOut: String { t("codex did not respond", "codex 没有回应", "codex 沒有回應") }
    static var malformed: String { t("Unrecognized usage data", "用量资料格式无法辨识", "用量資料格式無法辨識") }
    static var codexLaunchFailed: String { t("Could not start codex", "codex 启动失败", "codex 啟動失敗") }
    static var codexError: String { t("codex returned an error", "codex 回报错误", "codex 回報錯誤") }
    static var claudeNoData: String { t("No data yet — Claude writes it when reporting", "还没有资料，等 Claude 回报时写入", "還沒有資料，等 Claude 回報時寫入") }

    // Menu
    static func claudeUpdated(_ when: String) -> String { t("Claude data updated \(when)", "Claude 资料更新于 \(when)", "Claude 資料更新於 \(when)") }
    static var display: String { t("Display", "显示形式", "顯示形式") }
    static var percentageDisplay: String { t("Percentages", "百分比显示", "百分比顯示") }
    static var usedMode: String { t("Used", "已用", "已用") }
    static var remainingMode: String { t("Remaining", "剩余", "剩餘") }
    static var refresh: String { t("Refresh Now", "立即刷新", "立即重新整理") }
    static var quit: String { t("Quit QuotaBar", "退出 QuotaBar", "結束 QuotaBar") }
}
