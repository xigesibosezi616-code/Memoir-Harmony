import Foundation
import SwiftData

/// 笔友手记里的一条（2026-10-16 V9 新增；2026-10-27 V11 起分画像 / 大事，见 `SchemaV11`）。
///
/// 为什么有它（用户原话）：「让用户觉得这个笔友是真的他的一个长期的笔友，而不是感觉像一个 AI，
/// 今天发生的事情或者前几周发生的事情过一段时间就忘了。」
///
/// - **每位笔友各一本**（`penPalID`）：世界笔友用他的 id，自己起名的那位用 `PenPalNote.ownID`（`"own"`）。
///   **各记各的**：寄给谁就只带谁的那本，只寄给 3 位的事，另外 12 位永远不知道
/// - **只存在本机 + 用户自己的 iCloud**，寄信时随请求带上，服务端用完即弃；跟着备份包导出
/// - 两种（`kind`）：
///   - **画像**（`profile`）：这个人是谁 —— 身边的人、工作、在意的事、反复出现的心事。**一位笔友一份完整的文本**（一行），需要时整份重写
///   - **大事**（`recent`）：生活里重要的事和节点（面试、搬家、生日、一段关系的变化……），带日期。带最近的 `recentLimit` 件
/// - 每封回信时**笔友自己改手记**（服务端另外问一次，`PenPalNotebook.apply` 照着改）：新记、改写（`updatedAt`）、
///   不再需要的拿掉；快满时自己合并旧的，或把反复出现的事写进画像。危险的那封一条都不动（服务端就不给）
/// - `notedAt` = 记下它的那封回信的写信时刻 —— 信可能隔几周才寄，他得知道这是哪天记的
///   （「有一场很想去的面试」是上个月的事，就该问「后来怎么样了」）
/// - 🔴 **用户在 App 里看不到、也删不了**（2026-10-24 产品定，原计划的查看 / 删除界面撤销）
///
/// ⚠️ CloudKit 约束：非可选属性必须带默认值（见 `JournalEntry` 顶部说明）
@Model
final class PenPalNote {
    var id: UUID = UUID()
    var penPalID: String = ""
    var text: String = ""
    var notedAt: Date = Date()
    var createdAt: Date = Date()
    /// 画像还是大事（`PenPalNote.Kind` 的 rawValue）。V11 加；老的都是大事
    var kind: String = "recent"
    /// 笔友改过这一条的时刻。V11 加；nil = 没改过
    var updatedAt: Date?

    init(penPalID: String, text: String, notedAt: Date, kind: Kind = .recent) {
        self.id = UUID()
        self.penPalID = penPalID
        self.text = text
        self.notedAt = notedAt
        self.createdAt = .now
        self.kind = kind.rawValue
    }

    enum Kind: String, Sendable {
        /// 画像：这个人是谁（一位笔友一份）
        case profile
        /// 大事：带日期的事和节点
        case recent
    }

    var noteKind: Kind { Kind(rawValue: kind) ?? .recent }

    /// 自己起名的那位的手记用这个 id（世界笔友的 id 都是名册里的小写英文名，不会撞）
    static let ownID = "own"
    /// 大事带最近的几件去（快满时笔友自己合并旧的，与后端 `RECENT_LIMIT` 一致）
    static let recentLimit = 30
}
