import Foundation
import SwiftData

/// **Schema V6** —— 信件抬头「致 XXX」。
///
/// > 📌 2026-10 出 V7 后，本版的 `Tag` 已冻结成快照（见下方 `models`）。
/// > 📌 2026-10 出 V8 后，`JournalEntry` 和 `Letter` 借用 `SchemaV7` 的快照（V6、V7 两版里它们一模一样）。
///
/// 与 V5 的唯一差异：**`Letter` 多了一个可选字段 `toName`**（写信当时的用户昵称快照）。
/// 其余五个 model 一个字都没动，也没有增删 entity。
///
/// V5 → V6 走 `.lightweight`：**新增可选字段**，不删、不改名、不改类型、不做数据转换 ——
/// SwiftData 能自动推断，老信件的 `toName` 解成 nil，抬头退回只写「致」。
///
/// ---
///
/// ## ⚠️ 这是本项目第一次「给已有 model 加字段」，和前几版不是一回事
///
/// V3→V4（加 `MediaAsset`）、V4→V5（加 `DraftEntry`）都是**新增 entity**，
/// 两版的 model 列表本就不同，怎么写都不会撞车。
/// **给已有 model 加字段会撞**：`VersionedSchema.models` 返回活类型时，
/// 给 `Letter` 加 `toName` 会让 `SchemaV5` 也跟着"看到"这个字段，
/// 两版展开后完全相同 → 容器初始化直接崩 `Duplicate version checksums detected.`
///
/// 所以 `SchemaV5` 已被**冻结成快照**（enum 里内嵌 V5 当时的 `JournalEntry` 与 `Letter` 定义）。
/// 只冻结这两个是因为只有它们之间有 `@Relationship` 牵连。
///
/// > 📌 **以后每加一个新版本，都要先把上一版按这个样子冻结。**
/// > 中途试过「不建 V6、靠 CoreData 自动推断可选字段」，实测不行：
/// > SwiftData 走 `VersionedSchema` 路径时不会退回自动推断，报 `unrecognised property key`。
///
/// ## 📌 关于 2026-08-09 那次回退
///
/// 这套改动在 2026-08-09 加过一次，因真机崩溃被整体回退。
/// **后来查明与本 schema 无关** —— 真凶是 `MemoirApp` 里每次 body 求值都新建一个
/// 带 CloudKit 的 `ModelContainer`（详见 `MemoirApp.sharedModelContainer` 的注释）。
/// 修掉那行之后真机正常，这套 schema 按原样加了回来。
enum SchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)

    /// ⚠️ **`Tag` 用的是下面内嵌的快照，不是活类型**（2026-10 出 V7 时冻结）。
    ///
    /// V7 只给 `Tag` 加了字段，所以只冻结 `Tag`。`Tag` 与其他 model 没有 `@Relationship`，
    /// 其余五个用活类型不会影响本版校验和 —— 它们在 V6 和 V7 之间一个字没变。
    /// 将来哪个 model 再加字段，就要回来把它也冻结进这里（以及之后每一版）。
    ///
    /// **`JournalEntry`、`Letter` 借用 `SchemaV7` 的快照**（2026-10 出 V8 时补）：V8 给活的 `Letter`
    /// 加了字段，这里若还用活类型，V6 就会"看到"那个字段，跟真实的 V6 store 对不上，V6 老库就迁不动了。
    static var models: [any PersistentModel.Type] {
        [SchemaV7.JournalEntry.self, Self.Tag.self, MoodTag.self, SchemaV7.Letter.self, MediaAsset.self, DraftEntry.self]
    }

    // MARK: - V6 当时的 Tag 快照（冻结，不要跟着活类型改）
    //
    // 只用于迁移时描述"V6 长什么样"，运行时不会被实例化。
    // 与活类型的差异：这里**没有** V7 加的 `sortOrder` / `coverPhotoFilename` / `coverLayoutID` / `subtitle`。

    @Model
    final class Tag {
        var id: UUID = UUID()
        var name: String = ""
        var color: String?
        var colorID: String = "WineRed"
        var textureID: String = "Leather"
        var lastOpenedAt: Date = Date()
        var createdAt: Date = Date()

        init() {}
    }
}
