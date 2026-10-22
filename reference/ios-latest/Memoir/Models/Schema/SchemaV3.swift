import Foundation
import SwiftData

/// **Schema V3** —— 为接入 CloudKit 同步而做的结构调整。
///
/// 与 V2 的差异（entity 集合不变，仍是四个）：
/// - `Letter.relatedEntries` 由 `[JournalEntry]` 改为可选 `[JournalEntry]?`
/// - **新增** `JournalEntry.letters` 作为上述关系的反向端
/// - 所有非可选属性补上默认值（Swift 层的初始化默认值，不改变持久化结构）
///
/// 三条都是 CloudKit 的硬性要求：记录可能缺字段，所以要有默认值；
/// 关系必须成对且可选，否则容器初始化直接失败。
///
/// V2 → V3 走 `.lightweight`：只是**放宽**约束（非可选变可选）和**新增**一个关系端，
/// 没有删除、没有改名、没有类型变更 —— 属于 SwiftData 能自动推断的范畴，不需要自定义迁移。
enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [JournalEntry.self, Tag.self, SchemaV9.MoodTag.self, Letter.self]
    }
}
