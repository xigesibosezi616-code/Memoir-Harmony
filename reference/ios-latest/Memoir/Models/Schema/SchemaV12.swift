import Foundation
import SwiftData

/// **Schema V12** —— 情绪小结（2026-10-27，见 `Docs/HarmonyUpdates/U14_mood_insights.md`）。
///
/// 与 V11 的差异：**新增 entity `MoodSummary`**（每周 / 每月 / 每年一份情绪小结，会员）。其余六个 model 一个字段都没动。
///
/// V11 → V12 走 `.lightweight`：只加一个新 entity，不动已有的。
enum SchemaV12: VersionedSchema {
    static var versionIdentifier = Schema.Version(12, 0, 0)

    /// V12 是当前最新版，用**活类型**。
    /// 等将来出 V13 时，要回来把有变化的 model 冻结成快照（同 `SchemaV10` 的写法）。
    static var models: [any PersistentModel.Type] {
        [JournalEntry.self, Tag.self, Letter.self, MediaAsset.self, DraftEntry.self, PenPalNote.self, MoodSummary.self]
    }
}
