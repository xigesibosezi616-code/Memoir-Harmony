import Foundation
import SwiftUI
import SwiftData

/// ⚠️ **CloudKit 约束**：非可选属性必须带默认值。见 `JournalEntry` 顶部说明。
@Model
class MoodTag {
    var id: UUID = UUID()
    var name: String = ""     // 默认心情存英文 key (calm/productive/...)，自定义心情存用户输入
    var colorHex: String = "#B8AD9C"
    var isDefault: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var iconName: String?

    init(name: String, colorHex: String, isDefault: Bool = false, sortOrder: Int = 0, iconName: String? = nil) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.iconName = iconName
    }

    /// 显示名称：默认心情根据当前语言翻译，自定义心情直接显示
    var displayName: String {
        if isDefault {
            return MoodTag.localizedName(for: name)
        }
        return name
    }

    /// 默认心情的显示名。`key` 是数据库里存的英文标识（`calm` / `joyful` …）。
    ///
    /// 译文放在 `Localizable.xcstrings` 的 `mood.*` 条目里，六种语言齐全。
    /// 原先这里是一张**只有中英三种语言的手工表**，日/法/西一律退回英文；
    /// 而且读的是 `Locale.autoupdatingCurrent` —— **完全无视 App 内的语言设置**，
    /// 用户在设置里选了日文，心情名还是跟着系统走。（2026-08-08 一并修）
    ///
    /// 用户自建的心情不走这里（`displayName` 直接返回原名），不需要也不该翻译。
    static func localizedName(for key: String) -> String {
        // bundle 用 `.appLanguage` 而不是 `.main`：main 走系统语言，会无视设置里选的语言
        let resolved = NSLocalizedString("mood.\(key)", bundle: .appLanguage, comment: "默认心情名")
        // 查不到就退回原 key —— 用户自建心情、或将来新增还没翻的，至少不会显示成空白
        return resolved == "mood.\(key)" ? key : resolved
    }

    // 📌 `presetColors`（12 个候选色）已于 2026-08-12 删除 ——
    // 它只服务于「用户自建心情时挑颜色」，而心情已改为纯预设、不可自建。
    // 预设心情各自的配色写在下面 `defaultMoodTags()` 里，与图标一一对应。

    /// 创建 12 个默认心情标签（name 存英文 key）
    static func defaultMoodTags() -> [MoodTag] {
        let defaults: [(key: String, color: String, icon: String)] = [
            ("calm",        "#A8C5B8", "leaf"),
            ("productive",  "#C5B8A8", "flame"),
            ("reflective",  "#B8C5D4", "drop"),
            ("joyful",      "#D4C8A8", "sun.max"),
            ("low",         "#C5B8C5", "moon"),
            ("anxious",     "#D4B8B8", "bolt"),
            ("grateful",    "#B8D4C8", "heart"),
            ("excited",     "#D4C4B8", "star"),
            ("tired",       "#B8B8D4", "cloud"),
            ("peaceful",    "#D4D4B8", "wind"),
            ("nostalgic",   "#C5D4B8", "sparkles"),
            ("hopeful",     "#D4B8C5", "snowflake")
        ]

        return defaults.enumerated().map { index, item in
            MoodTag(name: item.key, colorHex: item.color, isDefault: true, sortOrder: index, iconName: item.icon)
        }
    }
}

// MARK: - DefaultMoods

struct DefaultMoods {
    static let all: [(key: String, zhHans: String, zhHant: String)] = [
        ("calm",        "平静", "平靜"),
        ("productive",  "充实", "充實"),
        ("reflective",  "沉思", "沉思"),
        ("joyful",      "喜悦", "喜悅"),
        ("low",         "低落", "低落"),
        ("anxious",     "焦虑", "焦慮"),
        ("grateful",    "感恩", "感恩"),
        ("excited",     "期待", "期待"),
        ("tired",       "疲惫", "疲憊"),
        ("peaceful",    "安宁", "安寧"),
        ("nostalgic",   "怀念", "懷念"),
        ("hopeful",     "希望", "希望"),
    ]

    /// 判断显示名称是否为默认心情
    static func isDefault(_ name: String) -> Bool {
        return all.contains { $0.zhHans == name || $0.zhHant == name }
    }

    /// 判断英文 key 是否为默认心情
    static func isDefaultKey(_ key: String) -> Bool {
        return all.contains { $0.key == key }
    }
}
