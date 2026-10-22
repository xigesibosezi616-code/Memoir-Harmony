import Foundation
import SwiftData

/// 「他记得的关于你的事」里的一条（2026-10-16，V9 新增，见 `SchemaV9`）。
///
/// - 每位世界笔友各一份（`penPalID`），**只存在本机 + 用户自己的 iCloud**，寄给这一位时随请求带上，服务端用完即弃
/// - 来自他每封回信里的「记下的事」；危险的那封一条都不记（服务端就不给）
/// - `notedAt` = 记下它的那封回信的写信时刻 —— 信可能隔几周才寄，他得知道这是哪天记的
///   （「有一场很想去的面试」是上个月的事，就该问「后来怎么样了」）
/// - 用户能看、能删（界面在第 6 步）
///
/// ⚠️ CloudKit 约束：非可选属性必须带默认值（见 `JournalEntry` 顶部说明）
@Model
final class PenPalNote {
    var id: UUID = UUID()
    var penPalID: String = ""
    var text: String = ""
    var notedAt: Date = Date()
    var createdAt: Date = Date()

    init(penPalID: String, text: String, notedAt: Date) {
        self.id = UUID()
        self.penPalID = penPalID
        self.text = text
        self.notedAt = notedAt
        self.createdAt = .now
    }

    /// 每位笔友最多带几条去（最近的）
    static let sendLimit = 20
}
