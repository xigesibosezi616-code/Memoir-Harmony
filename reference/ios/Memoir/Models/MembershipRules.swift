import Foundation

// 尺素会员：哪些东西要会员。产品规则见 `Memoir/Docs/MEMBERSHIP.md`（2026-10-09 定）。
//
// 🔴 **只卡「新用上」，不收回已经用上的。** 旧日记里的会员相纸、已经设好的会员封面版式，
// 不是会员（包括会员到期）也照样显示；只是不能再给新东西用。用户的日记不会因为停了会员而变样。
//
// 界面上的这些判断用本机的 Apple 订阅状态（`StoreKitManager.isMember`），断网、没登录也成立。

extension PaperStyle {
    /// 免费的只有原图、宝丽来；和风贴纸、极简卡片、胶片帧、信纸附照要会员
    var isMemberOnly: Bool {
        switch self {
        case .original, .polaroid: return false
        case .washiSticker, .minimalCard, .filmFrame, .letterAttached: return true
        }
    }

    /// 插图时预先选中哪种。默认设成了会员款、但现在不是会员（比如会员到期了）→ 宝丽来，
    /// 否则会一直免费用着会员相纸
    static func defaultStyle(raw: String, isMember: Bool) -> PaperStyle {
        let style = PaperStyle(rawValue: raw) ?? .polaroid
        return style.isMemberOnly && !isMember ? .polaroid : style
    }
}

extension CoverLayout {
    /// 免费的只有满版；白框、贴照片要会员
    var isMemberOnly: Bool { self != .fullBleed }
}

extension CoverEdit {
    /// 这次保存要不要会员：**新选了**会员版式，而且保存后封面上有照片（没照片时版式不起作用）。
    /// 原来已经用着的会员版式不算 —— 到期后改个副标题、换个颜色，不该被拦
    ///
    /// - Parameters:
    ///   - originalLayout: 这本原来的版式；新建日记本传 nil
    ///   - hasExistingPhoto: 这本原来有没有照片封面
    func needsMembership(originalLayout: CoverLayout?, hasExistingPhoto: Bool) -> Bool {
        guard layout.isMemberOnly, layout != originalLayout else { return false }
        switch photo {
        case .replaced: return true
        case .removed: return false
        case .unchanged: return hasExistingPhoto
        }
    }
}
