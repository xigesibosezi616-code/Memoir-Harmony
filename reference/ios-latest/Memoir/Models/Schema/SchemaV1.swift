import Foundation
import SwiftData

/// **Schema V1** —— App Store 准备阶段（2026-06）之前的生产 schema 快照。
///
/// 包含：JournalEntry / Tag / MoodTag 三个 @Model，无 Letter。
///
/// V1 → V2 migration 是 lightweight（仅新增 Letter，不动 V1 任何 model 字段）。
/// 若将来要改 JournalEntry / Tag / MoodTag 的字段，必须在此处保留**当时的字段定义**
/// （拷贝 @Model class 到 enum 内嵌套），否则旧 store 数据无法被识别。
/// 目前 V1 = V2 的非 Letter 部分完全一致，直接引用全局类型即可。
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [JournalEntry.self, Tag.self, SchemaV9.MoodTag.self]
    }
}
