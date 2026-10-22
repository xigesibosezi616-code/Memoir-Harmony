import Foundation
import SwiftData

/// **Schema V8** —— 尺素会员的火漆信。
///
/// 与 V7 的唯一差异：**`Letter` 多了一个可选字段 `stationery`**（这封信用的信纸，
/// 寄出那一刻按会员身份写定）。其余五个 model 一个字没动，也没有增删 entity。
///
/// 为什么要落库而不是显示时读会员状态：会员到期后，**已经收到的火漆信要保持原样**
/// （产品定，见 `Docs/MEMBERSHIP.md`）。不记下来的话，一停会员旧信就全变回普通信纸。
///
/// > 📌 2026-10-16 出 V9 后，本版的 `JournalEntry` 和 `Letter` 已冻结成快照（见下方 `models`）。
///
/// V7 → V8 走 `.lightweight`：新增可选字段，不删、不改名、不改类型 ——
/// 老信件解成 nil，就是普通信纸，正好是它们寄出时的样子。
enum SchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(8, 0, 0)

    /// ⚠️ **`JournalEntry` 和 `Letter` 用的是下面内嵌的快照，不是活类型**（2026-10-16 出 V9 时冻结）。
    ///
    /// V9 给 `Letter` 加了字段；冻结 `Letter` 就得连 `JournalEntry` 一起冻结 ——
    /// 两者之间有 `@Relationship`，活的 `JournalEntry` 会把活的 `Letter` 拽回模型图。
    /// 其余四个 model 在 V8 和 V9 之间没变，仍用活类型（V9 新增的 `PenPalNote` 不在这一版里）。
    static var models: [any PersistentModel.Type] {
        [Self.JournalEntry.self, Tag.self, SchemaV9.MoodTag.self, Self.Letter.self, MediaAsset.self, SchemaV9.DraftEntry.self]
    }

    // MARK: - V8 当时的字段快照（冻结，不要跟着活类型改）
    //
    // 只用于迁移时描述"V8 长什么样"，运行时不会被实例化。
    // 与活类型的差异：`Letter` 这里**没有** V9 加的 `penPalID` / `translatedBody` / `danger` / `postage`。

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
        @Relationship(inverse: \SchemaV8.Letter.relatedEntries)
        var letters: [SchemaV8.Letter]? = []

        init() {}
    }

    @Model
    final class Letter {
        var id: UUID = UUID()

        @Relationship(deleteRule: .nullify)
        var relatedEntries: [SchemaV8.JournalEntry]? = []

        var status: String = LetterStatus.pending.rawValue
        var body: String = ""
        var fromCharacter: String = "青鸟"
        var toName: String?
        var stationery: String?
        var triggerKind: String = LetterTriggerKind.weekly.rawValue
        var errorMessage: String?

        var generatedAt: Date = Date()
        var deliveredAt: Date?
        var readAt: Date?
        var updatedAt: Date = Date()

        init() {}
    }
}
