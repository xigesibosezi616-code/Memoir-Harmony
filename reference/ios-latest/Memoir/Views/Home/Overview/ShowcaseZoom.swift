import SwiftUI

/// 大屏模式一屏放几篇（2026-10-21 用户提：像「照片」那样双指捏合 —— 一屏一篇 → 4 篇 → 16 篇 → 64 篇）。
///
/// 每一级都是上一级的一半宽、一半高（列数翻倍），所以一屏的篇数 ×4：
///
/// | 级 | 列 | 一屏约 | 一格里有什么 |
/// |---|---|---|---|
/// | 一篇 | 1 | 1 | 原来的大卡片，左右翻（`ShowcaseView`） |
/// | 四篇 | 2 | 4 | 小一号的大卡片：照片、标题、日期、心情、两行正文 |
/// | 十六篇 | 4 | 16 | 照片（没照片是心情色）+ 标题一行 + 几号 |
/// | 六十四篇 | 8 | 64 | 只剩照片 / 心情色和几号，一眼看一两个月 |
///
/// **最多 64**：8 列时一格约 42 点宽，刚够手指点得准（苹果的下限是 44 点）、照片还认得出是哪张；
/// 再密一级（16 列、约 20 点）点不准，照片也只剩色块了 —— 看不清就不叫总览了。
enum ShowcaseZoom: Int, CaseIterable, Comparable {
    case one = 0
    case four
    case sixteen
    case sixtyFour

    static let storageKey = "showcaseZoom"

    /// 一行几篇
    var columns: Int { 1 << rawValue }

    /// 格子之间的空隙：越密越窄，64 篇时几乎拼成一张
    var spacing: CGFloat {
        switch self {
        case .one: return 0
        case .four: return 12
        case .sixteen: return 8
        case .sixtyFour: return 4
        }
    }

    /// 格子的圆角：跟着格子一起缩
    var cornerRadius: CGFloat {
        switch self {
        case .one: return 26
        case .four: return 16
        case .sixteen: return 10
        case .sixtyFour: return 6
        }
    }

    /// 宫格里每一格的宽高比（宽 / 高）—— 和大卡片差不多，四篇时两行正好铺满一屏
    static let cellAspect: CGFloat = 0.66

    /// 宫格两边的留白，和大卡片一样
    static let margin: CGFloat = 18

    /// 往里捏（看更多篇）一级；已经最密就是 nil
    var zoomedOut: ShowcaseZoom? { ShowcaseZoom(rawValue: rawValue + 1) }
    /// 往外张（看更少篇）一级；已经一篇就是 nil
    var zoomedIn: ShowcaseZoom? { ShowcaseZoom(rawValue: rawValue - 1) }

    static func < (a: ShowcaseZoom, b: ShowcaseZoom) -> Bool { a.rawValue < b.rawValue }
}
