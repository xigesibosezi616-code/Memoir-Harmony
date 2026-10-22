import Foundation
import SwiftData

/// **Schema V2** —— 引入 `Letter` @Model（AI 来信功能基础设施）。
///
/// 与 V1 的差异：
/// - **新增** `Letter` entity
/// - JournalEntry / Tag / MoodTag 字段**完全未变**
///
/// 因此 V1 → V2 走 `MigrationStage.lightweight`（SwiftData 自动建 Letter 表，不动现有数据）。
enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [JournalEntry.self, Tag.self, SchemaV9.MoodTag.self, Letter.self]
    }
}
