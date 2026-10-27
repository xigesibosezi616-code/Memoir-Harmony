import Foundation
import SwiftData

/// **Schema V11** —— 笔友手记（2026-10-27，见 `Docs/HarmonyUpdates/U01_world_penpals.md`「笔友手记」）。
///
/// 与 V10 的差异：**`PenPalNote` 加两个字段**
/// | 字段 | 类型 | 用途 |
/// |---|---|---|
/// | `kind` | `String`，默认 `"recent"` | `"profile"` = 画像（这个人是谁，一位笔友一份完整的文本）；`"recent"` = 大事（带日期的事和节点） |
/// | `updatedAt` | `Date?` | 笔友改过这一条的时刻；nil = 没改过 |
///
/// 老的每一条都是世界笔友回信时记下的小事，正好都是「大事」，所以 `kind` 默认 `"recent"`。
/// 自己起名的那位从 V11 起也有一本手记，`penPalID = "own"`（不改字段，只是多一种取值）。
///
/// V10 → V11 走 `.lightweight`：只加带默认值的字段和可选字段，不删、不改名、不改类型。
enum SchemaV11: VersionedSchema {
    static var versionIdentifier = Schema.Version(11, 0, 0)

    /// 仍用**活类型**：V12 只新增了 `MoodSummary`，这六个 model 一个字段都没动，两版的校验和靠多出来的那个 entity 区分。
    /// 将来哪个 model 改了字段，要回来把它冻结成快照（同 `SchemaV10` 的写法）。
    static var models: [any PersistentModel.Type] {
        [JournalEntry.self, Tag.self, Letter.self, MediaAsset.self, DraftEntry.self, PenPalNote.self]
    }
}
