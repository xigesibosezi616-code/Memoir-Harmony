import Foundation
import SwiftData

/// **Schema V8** —— 尺素会员的火漆信。
///
/// 与 V7 的唯一差异：**`Letter` 多了一个可选字段 `stationery`**（这封信用的信纸，
/// 寄出那一刻按会员身份写定）。其余五个 model 一个字没动，也没有增删 entity。
///
/// 为什么要落库而不是显示时读会员状态：会员到期后，**已经收到的火漆信要保持原样**
/// （产品定，见 `Docs/MEMBERSHIP.md`）。不记下来的话，一停会员旧信就全变回普通信纸。
///
/// V7 → V8 走 `.lightweight`：新增可选字段，不删、不改名、不改类型 ——
/// 老信件解成 nil，就是普通信纸，正好是它们寄出时的样子。
enum SchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(8, 0, 0)

    /// V8 是当前最新版，用**活类型**。
    /// 等将来出 V9 时，要回来把有变化的 model 冻结成快照（同 `SchemaV7` 冻结 `Letter` 的写法）。
    static var models: [any PersistentModel.Type] {
        [JournalEntry.self, Tag.self, MoodTag.self, Letter.self, MediaAsset.self, DraftEntry.self]
    }
}
