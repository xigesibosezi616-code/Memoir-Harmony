import Foundation
import SwiftData

/// **Schema V10** —— 写完日记的心情页（2026-10-17，见 `Docs/HarmonyUpdates/U03_mood_checkin.md`）。
///
/// 与 V9 的差异：
/// 1. **`JournalEntry` 加两个可选字段**：`moodValence`（愉悦度 -1…1）、`moodLabels`（情绪词的 key，1～3 个）
/// 2. **`JournalEntry` 删三个字段**：旧心情 `mood`、`moodColorHex`，没人用的印章表情 `stampEmoji`
/// 3. **`DraftEntry` 删旧心情** `mood`、`moodColorHex`（心情改在保存之后的心情页里记，草稿不存）
/// 4. **删掉整个 `MoodTag`**（旧心情标签）
///
/// 🔴 旧日记上的旧心情**直接清空、不换算**（2026-10-17 用户定）：升级后它们都是「没记心情」。
///
/// V9 → V10 走 `.lightweight`：只加可选字段、删字段、删 entity，不改名、不改类型。
enum SchemaV10: VersionedSchema {
    static var versionIdentifier = Schema.Version(10, 0, 0)

    /// V10 是当前最新版，用**活类型**。
    /// 等将来出 V11 时，要回来把有变化的 model 冻结成快照（同 `SchemaV9` 的写法）。
    static var models: [any PersistentModel.Type] {
        [JournalEntry.self, Tag.self, Letter.self, MediaAsset.self, DraftEntry.self, PenPalNote.self]
    }
}
