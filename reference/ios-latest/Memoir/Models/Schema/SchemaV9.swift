import Foundation
import SwiftData

/// **Schema V9** —— 世界笔友（2026-10-16，方案见 `Docs/WORLD_PENPALS.md`「第 4、5 步方案」）。
///
/// 与 V8 的差异：
/// 1. **`Letter` 多了四个可选字段**
///    | 字段 | 类型 | 用途 |
///    |---|---|---|
///    | `penPalID` | `String?` | 世界笔友的 id（`penpals.json`）；nil = 自己起名的那位 |
///    | `translatedBody` | `String?` | 译文（读信人的语言）；`body` 是笔友母语写的原文 |
///    | `danger` | `Bool?` | 日记里有危机信号：正面放译文（读信人的语言） |
///    | `postage` | `Int?` | 这封贴了几张邮票 |
/// 2. **新增 entity `PenPalNote`**：「他记得的关于你的事」，每位笔友各一份，只在本机 + iCloud
///
/// V8 → V9 走 `.lightweight`：只加可选字段和新表，不删、不改名、不改类型 ——
/// 老信件四个字段解成 nil，就是「自己起名的那位、没有译文、不危险、没记邮资」，正好是它们的样子。
enum SchemaV9: VersionedSchema {
    static var versionIdentifier = Schema.Version(9, 0, 0)

    /// ⚠️ **`JournalEntry`、`Letter`、`DraftEntry`、`MoodTag` 用的是下面内嵌的快照，不是活类型**（2026-10-17 出 V10 时冻结）。
    ///
    /// V10 删了 `JournalEntry`、`DraftEntry` 上的旧心情字段，删了整个 `MoodTag`；冻结 `JournalEntry` 就得连 `Letter` 一起冻结
    /// （两者之间有 `@Relationship`）。`MoodTag` 和 `DraftEntry` 的快照 V1～V8 也在用（它们原来都直接用活类型，字段和这里一样）。
    /// 其余三个 model（`Tag`、`MediaAsset`、`PenPalNote`）在 V9 和 V10 之间没变，仍用活类型。
    static var models: [any PersistentModel.Type] {
        [Self.JournalEntry.self, Tag.self, Self.MoodTag.self, Self.Letter.self, MediaAsset.self, Self.DraftEntry.self, PenPalNote.self]
    }

    // MARK: - V9 当时的字段快照（冻结，不要跟着活类型改）
    //
    // 只用于迁移时描述"V9 长什么样"，运行时不会被实例化。字段必须和 V9 时的活类型**一个不差**，
    // 否则已经在 V9 的库认不出自己是哪一版，迁移会失败。

    @Model
    final class JournalEntry {
        var id: UUID = UUID()
        var title: String = ""
        var content: String = ""
        var date: Date = Date()
        var mood: String = ""
        var moodColorHex: String?
        var tags: [String] = []
        var isFavorite: Bool = false
        var wordCount: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        var audioURLs: [String] = []
        var weatherInfo: String?
        var locationInfo: String?
        var weatherCode: String?
        var stampEmoji: String?

        var contentBlocksData: Data?

        /// 反向关系必须指向**同一版的快照**，写成活类型就等于把活的模型图拽回来
        @Relationship(inverse: \SchemaV9.Letter.relatedEntries)
        var letters: [SchemaV9.Letter]? = []

        init() {}
    }

    @Model
    final class Letter {
        var id: UUID = UUID()

        @Relationship(deleteRule: .nullify)
        var relatedEntries: [SchemaV9.JournalEntry]? = []

        var status: String = LetterStatus.pending.rawValue
        var body: String = ""
        var fromCharacter: String = "青鸟"
        var toName: String?
        var stationery: String?
        var penPalID: String?
        var translatedBody: String?
        var danger: Bool?
        var postage: Int?
        var triggerKind: String = LetterTriggerKind.weekly.rawValue
        var errorMessage: String?

        var generatedAt: Date = Date()
        var deliveredAt: Date?
        var readAt: Date?
        var updatedAt: Date = Date()

        init() {}
    }

    /// 写日记页的草稿。V5 起就是这个样子（V5～V8 也指向这份快照）
    @Model
    final class DraftEntry {
        var id: UUID = UUID()
        var title: String = ""
        var contentBlocksData: Data?
        var mood: String = ""
        var moodColorHex: String?
        var tags: [String] = []
        var audioURLs: [String] = []
        var weatherCode: String?
        var weatherInfo: String?
        var locationInfo: String?
        var placeMode: String = "auto"
        var manualPlaceName: String?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init() {}
    }

    /// 旧的心情标签（平静、喜悦、低落……），V10 整个删掉。V1～V8 也指向这份快照
    @Model
    final class MoodTag {
        var id: UUID = UUID()
        var name: String = ""
        var colorHex: String = "#B8AD9C"
        var isDefault: Bool = false
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var iconName: String?

        init() {}
    }
}
