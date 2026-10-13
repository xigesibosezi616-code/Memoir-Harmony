import Foundation
import SwiftData

/// **Schema V4** —— 让照片和录音也能跨设备同步。
///
/// 与 V3 的唯一差异：**新增 `MediaAsset` 一个 entity**。
/// 四个老 model 的字段、关系、约束**一个字都没动**。
///
/// 为什么需要它：照片/录音是磁盘上的独立文件，SwiftData 里只有文件名，
/// 所以 CloudKit 同步过去的日记有字没图。`MediaAsset` 用
/// `@Attribute(.externalStorage) Data` 装字节，CloudKit 镜像会自动把它转成 CKAsset 带走。
/// 详见 `MediaAsset` 的注释。
///
/// V3 → V4 走 `.lightweight`：**纯新增 entity**，不删、不改名、不改类型、不做数据转换 ——
/// SwiftData 能自动推断。存量照片不在这一步搬，改由 `MediaStorage.syncToCloud`
/// 在运行时**懒回填**，避免"一次性迁移用户全部照片"这种最危险的操作。
enum SchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [JournalEntry.self, Tag.self, MoodTag.self, Letter.self, MediaAsset.self]
    }
}
