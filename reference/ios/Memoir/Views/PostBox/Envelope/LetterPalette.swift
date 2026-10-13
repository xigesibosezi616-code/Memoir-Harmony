import SwiftUI

/// 会员信件的用料：信封、内衬、信纸、格线。跟着主题换。
///
/// 信纸是「纸」，不跟主题的明暗走 —— 皮革主题是深色，但摊在皮桌面上的那张信纸还是米白的
struct LetterPalette {
    /// 信纸
    let paper: Color
    /// 字
    let ink: Color
    /// 格线
    let rule: Color
    /// 信封外面
    let envelope: Color
    /// 信封折边的线和阴影
    let envelopeEdge: Color
    /// 信封内衬（拆开才看得见的那一层）
    let liner: Color
    /// 信纸四周有没有一圈细框（八行笺那样）
    let framed: Bool

    static func of(themeID: String) -> LetterPalette {
        switch themeID {
        case "leather": return .leather
        case "kent": return .kent
        default: return .bamboo
        }
    }

    /// 素笺：米色信封，朱红内衬，红格信笺
    static let bamboo = LetterPalette(
        paper: Color(hex: "#F7F1E3"),
        ink: Color(hex: "#3D3428"),
        rule: Color(hex: "#B5473A").opacity(0.32),
        envelope: Color(hex: "#EEE5D3"),
        envelopeEdge: Color(hex: "#BFAE90"),
        liner: Color(hex: "#B65A45"),
        framed: true
    )

    /// 皮革：牛皮纸信封，深棕内衬，米白信纸配赭色格线
    static let leather = LetterPalette(
        paper: Color(hex: "#F1E8D4"),
        ink: Color(hex: "#2E241B"),
        rule: Color(hex: "#8A6A45").opacity(0.35),
        envelope: Color(hex: "#B8935F"),
        envelopeEdge: Color(hex: "#7E5F38"),
        liner: Color(hex: "#3B2A1E"),
        framed: false
    )

    /// 肯特：白信封，藏青内衬，白纸灰蓝格线
    static let kent = LetterPalette(
        paper: Color(hex: "#FDFDFB"),
        ink: Color(hex: "#1A1A1A"),
        rule: Color(hex: "#7C8FA6").opacity(0.35),
        envelope: Color(hex: "#F6F6F3"),
        envelopeEdge: Color(hex: "#CFCFC8"),
        liner: Color(hex: "#2F4A6B"),
        framed: false
    )
}
