import Foundation
import SwiftData

/// **Schema V7** —— 日记本重铸（书架拖拽排序 + 照片封面 + 版式 + 副标题）。
///
/// > 📌 2026-10 出 V8 后，本版的 `JournalEntry` 和 `Letter` 已冻结成快照（见下方 `models`）。
///
/// 与 V6 的唯一差异：**`Tag` 多了四个字段**，其余五个 model 一个字没动，也没有增删 entity。
///
/// | 字段 | 类型 | 用途 |
/// |---|---|---|
/// | `sortOrder` | `Int = 0` | 书架上的位置，像桌面图标那样拖拽换位 |
/// | `coverPhotoFilename` | `String?` | 照片封面（文件在 `journal_photos/`，云端走 `MediaAsset`） |
/// | `coverLayoutID` | `String?` | 封面版式模板；nil = 经典布面（纯色亚麻图） |
/// | `subtitle` | `String?` | 书名下的小字；nil = 不显示（或由界面自动生成） |
///
/// **四个一次加完**，是为了只升一次 schema —— 每升一次都要冻结上一版、真跑迁移、真机验 CloudKit，
/// 代价不小。字段先占位，功能按阶段陆续接上。
///
/// V6 → V7 走 `.lightweight`：三个可选字段解成 nil；`sortOrder` 非可选但带默认值 0
/// （CloudKit 也要求非可选字段必须有默认值）。全体为 0 时按 `createdAt` 排，
/// 等于保留了老用户书架原来的顺序，**不需要自定义迁移去回填**。
enum SchemaV7: VersionedSchema {
    static var versionIdentifier = Schema.Version(7, 0, 0)

    /// ⚠️ **`JournalEntry` 和 `Letter` 用的是下面内嵌的快照，不是活类型**（2026-10 出 V8 时冻结）。
    ///
    /// V8 只给 `Letter` 加了字段；冻结 `Letter` 就得连 `JournalEntry` 一起冻结 ——
    /// 两者之间有 `@Relationship`，活的 `JournalEntry` 会把活的 `Letter` 拽回模型图。
    /// `Tag` 在 V7 和 V8 之间没变，仍用活类型。
    static var models: [any PersistentModel.Type] {
        [Self.JournalEntry.self, Tag.self, MoodTag.self, Self.Letter.self, MediaAsset.self, DraftEntry.self]
    }

    // MARK: - V7 当时的字段快照（冻结，不要跟着活类型改）
    //
    // 只用于迁移时描述"V7 长什么样"，运行时不会被实例化。
    // 与活类型的唯一差异：`Letter` 这里**没有 `stationery`**（那是 V8 加的）。
    // V6 和 V7 的这两个 model 完全一样，`SchemaV6` 直接借用这里的快照。

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
        @Relationship(inverse: \SchemaV7.Letter.relatedEntries)
        var letters: [SchemaV7.Letter]? = []

        init() {}
    }

    @Model
    final class Letter {
        var id: UUID = UUID()

        @Relationship(deleteRule: .nullify)
        var relatedEntries: [SchemaV7.JournalEntry]? = []

        var status: String = LetterStatus.pending.rawValue
        var body: String = ""
        var fromCharacter: String = "青鸟"
        var toName: String?
        var triggerKind: String = LetterTriggerKind.weekly.rawValue
        var errorMessage: String?

        var generatedAt: Date = Date()
        var deliveredAt: Date?
        var readAt: Date?
        var updatedAt: Date = Date()

        init() {}
    }
}
