import Foundation
import SwiftData

/// **Schema V5** —— 写日记页的草稿。
///
/// 与 V4 的唯一差异：**新增 `DraftEntry` 一个 entity**。
/// 五个老 model 的字段、关系、约束**一个字都没动**。
///
/// 为什么需要它：以前退出写日记页 = 内容直接丢。现在返回时可以存成草稿，
/// 下次进来接着写；**只有点对勾才算「完成了一篇书写」**，那一刻才产生 `JournalEntry`。
///
/// 为什么不给 `JournalEntry` 加 `isDraft` 标志位：那样每一处 `@Query<JournalEntry>`
/// （首页 / 日记本 / 搜索 / 大屏展示 / 备份包导出 / 字数统计…）都得记得加过滤，
/// 漏一处草稿就混进正式日记。独立 entity 从类型上杜绝这件事。详见 `DraftEntry` 注释。
///
/// V4 → V5 走 `.lightweight`：**纯新增 entity**，不删、不改名、不改类型、不做数据转换 ——
/// SwiftData 能自动推断，与 V3 → V4 加 `MediaAsset` 是同一个路子。
///
/// ---
///
/// ## ⚠️ 想给已有 model 加字段？先读这段
///
/// 2026-08-09 试过加 `SchemaV6`（给 `Letter` 加一个可选的 `toName`），真机一装就崩，
/// 当时判定是 schema 的锅、整体回退了。**这个判定后来被证明是错的** ——
/// 真凶是 `MemoirApp` 里 `.modelContainer(Self.makeModelContainer())` 每次 body 求值
/// 都新建一个带 CloudKit 的容器（详见 `MemoirApp.sharedModelContainer` 的注释）。
/// 那次改动和视频启动页同一批上真机，`showSplash` 的状态翻转让容器建了两次，
/// 于是崩在了 schema 头上。修掉容器那行之后真机正常。
///
/// **`toName` 本身是无辜的，V5→V6 这条路可以照原样走。**
///
/// 仍然成立的那条教训（这个是真的，在模拟器上复现过）：
///
/// > `VersionedSchema.models` 返回**活类型**时，给任何 model 加字段都会让上一版
/// > 跟着一起变，两版展开后完全相同 → `Duplicate version checksums detected.`
/// > 解法是把上一版**冻结成快照**（enum 里内嵌当时的 @Model 定义）。
/// > 加 `DraftEntry`（V4→V5）没踩到，是因为**新增 entity** 时两版的 model 列表本就不同；
/// > **给已有 model 加字段才会踩**。
///
/// 另一条也仍然成立、只是这次并不是它：模拟器没有 iCloud 账号，CloudKit 那层完全不参与，
/// **模拟器的迁移绿灯不能当真机的通行证**。但反过来也要记住 ——
/// 「真机崩了」不等于「schema 错了」，先拿日志定位再回退，
/// 这次白回退一次就是因为跳过了这一步。
enum SchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

    /// ⚠️ **`JournalEntry` 和 `Letter` 用的是下面内嵌的快照，不是活类型。**
    ///
    /// 只冻结这两个，是因为**只有它们之间有 `@Relationship` 牵连** ——
    /// 关系会把对方也拽进模型图，一个变两个都变。其余四个 model 之间没有任何关系，
    /// 用活类型不会影响本版的校验和。
    ///
    /// **`Tag` 借用 `SchemaV6.Tag` 快照**（2026-10 出 V7 时补）：V7 给活的 `Tag` 加了字段，
    /// 这里若还用活类型，V5 就会"看到"那些字段，跟真实的 V5 store 对不上，V5 老库就迁不动了。
    /// `Tag` 从 V3 到 V6 一个字没变，V6 的快照就是 V5 当时的样子，不必再抄一份。
    static var models: [any PersistentModel.Type] {
        [Self.JournalEntry.self, SchemaV6.Tag.self, SchemaV9.MoodTag.self, Self.Letter.self, MediaAsset.self, SchemaV9.DraftEntry.self]
    }

    // MARK: - V5 当时的字段快照（冻结，不要跟着活类型改）
    //
    // 这两个类**只用于迁移时描述"V5 长什么样"**，运行时不会被实例化。
    // 活类型后续怎么加字段都跟它们无关 —— 这正是冻结的意义。
    // 与活类型的唯一差异：`Letter` 这里**没有 `toName`**（那是 V6 加的）。

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

        /// 反向关系必须指向**同一版的快照** `SchemaV5.Letter`，
        /// 写成活类型 `Letter` 就等于把活的模型图拽回来，冻结也就白做了。
        @Relationship(inverse: \SchemaV5.Letter.relatedEntries)
        var letters: [SchemaV5.Letter]? = []

        init() {}
    }

    @Model
    final class Letter {
        var id: UUID = UUID()

        @Relationship(deleteRule: .nullify)
        var relatedEntries: [SchemaV5.JournalEntry]? = []

        var status: String = LetterStatus.pending.rawValue
        var body: String = ""
        var fromCharacter: String = "青鸟"
        var triggerKind: String = LetterTriggerKind.weekly.rawValue
        var errorMessage: String?

        var generatedAt: Date = Date()
        var deliveredAt: Date?
        var readAt: Date?
        var updatedAt: Date = Date()

        init() {}
    }
}
