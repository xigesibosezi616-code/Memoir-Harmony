import SwiftUI

struct LanguageOption: Identifiable {
    let id: String       // locale identifier
    let displayName: String
}

@Observable
class LanguageManager {
    /// 当前语言，**永远是 `supportedLanguages` 里的一个**（空串只在 init 里存在一瞬）。
    ///
    /// 🔴 **不要改回 `@AppStorage` + `@ObservationIgnored`**。原先是那么写的，后果是
    /// **改了语言不会触发任何观察更新** —— 对勾不动、`.environment(\.locale)` 不重新求值，
    /// 用户只能杀掉后台重进才看到切换。`@AppStorage` 是给 View 用的 `DynamicProperty`，
    /// 放进 `@Observable` 类里本就不通知，再加 `@ObservationIgnored` 等于彻底断了信号。
    ///
    /// 现在是普通属性 + `didSet` 落盘：`@Observable` 能追踪，写入仍走同一个
    /// UserDefaults key（`Bundle.appLanguage` 靠它读）。
    var appLanguage: String = "" {
        didSet {
            guard appLanguage != oldValue else { return }
            UserDefaults.standard.set(appLanguage, forKey: Self.storageKey)
        }
    }

    static let storageKey = "appLanguage"

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        let resolved = stored.isEmpty ? Self.resolveInitialLanguage() : stored
        appLanguage = resolved
        // 首启解析出来的结果要立刻落盘 —— `Bundle.appLanguage` 直接读 UserDefaults，
        // 不落盘的话它会 fallback 到 Bundle.main（= 系统语言），与 App 内选定的语言不一致
        if stored != resolved {
            UserDefaults.standard.set(resolved, forKey: Self.storageKey)
        }
    }

    var currentLocale: Locale {
        Locale(identifier: appLanguage.isEmpty ? "en" : appLanguage)
    }

    var isChineseLocale: Bool {
        currentLocale.language.languageCode?.identifier == "zh"
    }

    /// 支持的语言。**没有「跟随系统」这一项**（2026-08-08 决策）——
    /// 首次启动时后台按系统语言自动挑一个，之后就是一个明确的语言，
    /// 不给用户一个"到底现在是哪种语言"说不清的选项。
    ///
    /// ⚠️ **改这个列表 = 改承诺**。加语言的顺序：
    /// ① 翻完 `Localizable.xcstrings`（含 `GreetingManager` 那批语气文案）
    /// ② 在 pbxproj 的 `knownRegions` 里加上（**不加的话翻译根本不会被打包**）
    /// ③ 在 `InfoPlist.xcstrings` 里给 App 名**和四条权限说明**
    ///    （权限说明是系统弹窗，漏了就是外语用户看到中文）
    /// ④ 把语言代码加进 `Scripts/check_localization.py` 的 `LANGS`
    /// ⑤ 最后才加进这个列表。
    ///
    /// 做完跑一遍 `python3 Scripts/check_localization.py`，退出码必须是 0；
    /// 再确认 `Memoir.app/<lang>.lproj/Localizable.strings` 真的生成了（这一步能抓出漏加 knownRegions）。
    static let supportedLanguages: [LanguageOption] = [
        LanguageOption(id: "zh-Hans", displayName: "简体中文"),
        LanguageOption(id: "zh-Hant", displayName: "繁體中文"),
        LanguageOption(id: "en", displayName: "English"),
        LanguageOption(id: "ja", displayName: "日本語"),
        LanguageOption(id: "ko", displayName: "한국어"),
        LanguageOption(id: "fr", displayName: "Français"),
        LanguageOption(id: "es", displayName: "Español")
    ]

    /// 首次启动时按系统语言挑一个受支持的语言。
    ///
    /// 规则（2026-08-08 定）：**跟随系统；系统语言不在名单里的，统一用英语。**
    /// 中文要区分简繁 —— 港澳台按繁体，其余按简体。
    static func resolveInitialLanguage() -> String {
        let supported = Set(supportedLanguages.map(\.id))

        // 按用户在系统里排的偏好顺序找第一个我们支持的
        for identifier in Locale.preferredLanguages {
            let locale = Locale(identifier: identifier)
            guard let code = locale.language.languageCode?.identifier else { continue }

            if code == "zh" {
                // script 最可信（zh-Hant-TW / zh-Hans-CN）；没有 script 时看地区
                if let script = locale.language.script?.identifier {
                    return script == "Hant" ? "zh-Hant" : "zh-Hans"
                }
                let region = locale.region?.identifier
                return ["TW", "HK", "MO"].contains(region ?? "") ? "zh-Hant" : "zh-Hans"
            }

            if supported.contains(code) { return code }   // en / ja / fr / es
        }

        // 系统语言不在名单里 —— 用英语，而不是中文：
        // 一个看不懂中文的用户，看到满屏中文只会直接删 App
        return "en"
    }
}
