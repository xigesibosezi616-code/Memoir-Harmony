import SwiftUI

/// 照片封面的版式（2026-10 P3b）。存在 `Tag.coverLayoutID`，**只对有照片的封面生效** ——
/// 没照片就是纯色亚麻，没有版式可言。
///
/// rawValue 写进库和备份包（`BackupTag.coverLayout`），是跨端契约，**不要改**。
enum CoverLayout: String, CaseIterable, Codable {
    /// 满版：照片铺满整个封面，书名压在照片上
    case fullBleed = "FullBleed"
    /// 白框：米白纸封面，照片嵌在上半部，书名写在照片下面（参考图 ② 的 CHRONICLE）
    case framed = "Framed"
    /// 贴照片：亚麻布面中间贴一张带白边的照片、四角压着相角，书名烫在照片下面 —— 老相册的封面
    case tipIn = "TipIn"

    /// 见 `HomeDisplayMode.displayName`：常驻界面的文案用 `LocalizedStringKey`，切换语言当场跟着变
    var displayName: LocalizedStringKey {
        switch self {
        case .fullBleed: return "满版"
        case .framed:    return "白框"
        case .tipIn:     return "贴照片"
        }
    }

    /// 这个版式下还看不看得见布面颜色（贴照片的底子是布面，颜色要能选）
    var showsClothColor: Bool { self == .tipIn }
}

extension Tag {
    /// 封面版式；库里没有 / 不认识的值（更新版本加的）按满版
    var coverLayout: CoverLayout {
        coverLayoutID.flatMap(CoverLayout.init(rawValue:)) ?? .fullBleed
    }
}
