import Foundation
import SwiftData

/// SwiftData 迁移计划。所有 schema 演进都走这里，**严禁**回到"删 store 文件"兜底。
///
/// 每加一版 schema：
/// 1. 新建 `SchemaVN.swift`（拷贝上一版字段定义、追加新字段）
/// 2. 把新版本加到 `schemas` 数组末尾
/// 3. 在 `stages` 末尾追加迁移 stage（`.lightweight` / `.custom`）
/// 4. 把 `ModelContainer` 引用从 `SchemaV(N-1).self` 改成 `SchemaVN.self`
/// 5. **在模拟器上用一个旧版本的 store 真跑一次迁移** —— 光看容器能不能初始化是不够的：
///    store 已经在最新版时根本不会走迁移路径，问题要等真实用户升级才爆。
///    做法：先用旧版 App 建库，再装新版启动，确认数据都在。
enum MemoirMigrationPlan: SchemaMigrationPlan {
    /// ⚠️ **每个版本的持久化结构必须真的不一样**，否则 CoreData 会抛
    /// `Duplicate version checksums across stages detected.` 并崩在容器初始化。
    ///
    /// **`SchemaV1` 和 `SchemaV2` 因此被排除在迁移计划之外**，原因是同一个：
    /// 这几个 `VersionedSchema` 的 `models` 返回的都是**活的类型**，不是当时的快照。
    ///
    /// - V3 给 `JournalEntry` 加了 `@Relationship(inverse: \Letter.relatedEntries) var letters`，
    ///   这条关系**把 `Letter` 拽进了模型图** —— 于是"只有三个 model"的 `SchemaV1`
    ///   实际展开后也是四个 entity，和 V3 校验和相同
    /// - `SchemaV2` 的 model 列表本就和 V3 逐字相同（V3 只做了关系可选化 + 补默认值，
    ///   按其自身注释"不改变持久化结构"）
    ///
    /// `SchemaV1.swift` 的注释早就写明「若将来要改字段，必须在此处保留当时的字段定义
    /// （拷贝 @Model class 到 enum 内嵌套）」—— V3 加关系时没照做，V1 快照就此失真。
    /// 两个文件保留作版本史留档，但不参与迁移。
    ///
    /// **这个雷从 V3 起就埋着**，只是此前 store 一直已在最新版、从没真正走过迁移路径，
    /// 直到 2026-08-08 加 V4 才暴露。也就是说 V1/V2 → V3 的迁移**从未在任何设备上真正执行过**，
    /// 那两个 stage 早就是形同虚设（校验和撞了，CoreData 根本区分不出来）。
    ///
    /// **影响**：真正的 V1 / V2 老 store（2026-06 App Store 准备之前的开发版，从未上架）
    /// 不再能被迁移。要恢复支持的话，得在 `SchemaV1` / `SchemaV2` 里内嵌**当时的** @Model 定义快照。
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self, SchemaV8.self]
    }

    static var stages: [MigrationStage] {
        [
            // V3 → V4：纯新增 MediaAsset entity（照片/录音的云端载体），老 model 一个字没动。
            // 存量照片不在迁移里搬 —— 由 MediaStorage.syncToCloud 运行时懒回填 → lightweight 安全
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
            // V4 → V5：纯新增 DraftEntry entity（写日记页的草稿），老 model 一个字没动 → lightweight 安全
            .lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self),
            // V5 → V6：给已有的 Letter 加一个**可选**字段 toName（信件抬头的昵称快照）。
            // 本项目第一次动已有 model 的字段 —— SchemaV5 为此已冻结成快照，
            // 否则两版校验和相同会直接崩。老信件解成 nil，抬头退回只写「致」→ lightweight 安全
            .lightweight(fromVersion: SchemaV5.self, toVersion: SchemaV6.self),
            // V6 → V7：给 `Tag` 加四个字段（三个可选 + 带默认值的 sortOrder），为日记本重铸占位。
            // SchemaV6 已把 `Tag` 冻结成快照，两版校验和不同。不删、不改名、不改类型 → lightweight 安全
            .lightweight(fromVersion: SchemaV6.self, toVersion: SchemaV7.self),
            // V7 → V8：给 `Letter` 加一个可选字段 `stationery`（火漆信）。
            // SchemaV7 已把 `JournalEntry`、`Letter` 冻结成快照。老信件解成 nil = 普通信纸 → lightweight 安全
            .lightweight(fromVersion: SchemaV7.self, toVersion: SchemaV8.self)
        ]
    }
}
