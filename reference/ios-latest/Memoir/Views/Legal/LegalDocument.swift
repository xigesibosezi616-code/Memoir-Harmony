import Foundation

/// 法律文本：隐私政策 / 用户协议。
///
/// **为什么走 bundle 里的 md 文件，而不是 `Localizable.xcstrings`**：
/// 这两份文档是数千字的长文，塞进 catalog 会把翻译文件撑得没法看，
/// 而且译者拿到的是被切碎的句子，读不出上下文。一种语言一个文件，
/// 译者拿到的就是一整篇完整的文档。
///
/// **为什么内置而不是只放网页**：App Store Connect 的隐私政策 URL 是必填项，
/// 网页那份必须有；但审核时如果网络不通或域名还没部署好，内嵌网页就是一片空白 ——
/// 「链接打不开直接拒」正是上架清单 A6 警告的事。内置一份，审核绝对打得开。
/// 两份内容同源：`Scripts/build_legal_html.py` 从同一批 md 生成网页版。
enum LegalDocument: String, CaseIterable, Identifiable {
    case privacy
    case terms

    /// 当前生效的政策版本，与两份 md 顶部的「更新日期」一致。
    ///
    /// 🔴 **改了政策内容就要改这里** —— 用户的同意记录存的是版本号，
    /// 版本一变，老用户下次启动会重新看到告知与同意页。
    /// 不改的话，等于用户从没同意过新版本，而你以为他同意了。
    /// 2026-10-09：隐私政策第七节注销账号改为 App 内自助（上架清单 A9）
    static let currentVersion = "2026-10-09"


    var id: String { rawValue }

    /// 文件名前缀，对应 `Resources/Legal/<prefix>_<lang>.md`
    var filePrefix: String {
        switch self {
        case .privacy: return "privacy"
        case .terms:   return "terms"
        }
    }

    /// 导航栏标题。
    ///
    /// 这里退回 `String` + `NSLocalizedString(bundle: .appLanguage)` 而不是
    /// `LocalizedStringKey`，是因为它要交给 `.navigationTitle(_:)` 的 String 重载
    /// 与外部调用方拼字符串（见 CLAUDE.md 第 7 条的例外说明）。
    var navigationTitle: String {
        switch self {
        case .privacy: return NSLocalizedString("隐私政策", bundle: .appLanguage, comment: "法律文档标题")
        case .terms:   return NSLocalizedString("用户协议", bundle: .appLanguage, comment: "法律文档标题")
        }
    }

    /// 读取当前 App 语言对应的正文。
    ///
    /// 找不到时**退回简体中文**而不是返回空 —— 法律文本一片空白是合规事故，
    /// 显示一份看得懂但语言不对的文档，比什么都没有强得多。
    func loadMarkdown(language: String) -> String {
        for candidate in Self.candidates(for: language) {
            if let url = Bundle.main.url(
                forResource: "\(filePrefix)_\(candidate)",
                withExtension: "md"
            ), let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return ""
    }

    /// 语言回退链：精确匹配 → 同语族 / 英语 → 简体中文兜底。
    ///
    /// 例：`zh-Hant` 找不到时退到 `zh-Hans`（看得懂）而不是 `en`；
    /// `fr` 找不到时退到 `en`（比中文更可能读懂）再退 `zh-Hans`。
    static func candidates(for language: String) -> [String] {
        var chain: [String] = []
        if !language.isEmpty { chain.append(language) }

        if language.hasPrefix("zh") {
            chain.append("zh-Hans")
        } else if language != "en" {
            chain.append("en")
        }
        chain.append("zh-Hans")

        // 去重且保序
        var seen = Set<String>()
        return chain.filter { seen.insert($0).inserted }
    }
}
