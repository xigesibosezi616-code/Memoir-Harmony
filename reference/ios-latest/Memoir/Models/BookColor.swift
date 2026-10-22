import SwiftUI

/// 日记本封面颜色（**8 个**预设，对应 Assets.xcassets 里的 `Cover_{rawValue}_Linen.imageset`）。
///
/// 仅象牙白是浅色（`isLight = true`），文字用深棕；其余 7 色用米白。
///
/// 📌 **2026-08-08 从 12 色收敛到 9 色**（产品决策）。删掉的三个与保留色太接近，
/// 摆在一个书架上分不出来：赭红≈酒红、橄榄褐≈墨绿、古铜≈琥珀棕。
///
/// 📌 **2026-10 皮革下架，只留亚麻**（见 `BookTexture`）。牛皮只有皮革款，跟着下架 → 9 色变 8 色。
///
/// 存量数据由 `BookColor.retiredColorReplacement` + `migrateTagsToBookCoverSystem` 接住。
enum BookColor: String, CaseIterable, Codable {
    case wineRed       = "WineRed"
    case pineGreen     = "PineGreen"
    case prussianBlue  = "PrussianBlue"
    case eggplant      = "Eggplant"
    case amberBrown    = "AmberBrown"
    case charcoal      = "Charcoal"
    case slate         = "Slate"
    case ivory         = "Ivory"

    /// 已下架颜色 → 最接近的保留色。
    ///
    /// **不能只靠 `Tag.bookColor` 的 `?? .wineRed` 兜底** —— 那样橄榄褐和古铜的日记本
    /// 会一起变成酒红，用户看到的是"我的书架被人换了颜色"。按色值就近映射，
    /// 至少还在同一个色系里。
    static let retiredColorReplacement: [String: BookColor] = [
        "RustRed": .wineRed,        // #6C382F → #592A2C
        "OliveBrown": .pineGreen,   // #4B4930 → #34473B
        "BronzeBrown": .amberBrown, // #5B4029 → #7A5429
        "Camel": .amberBrown        // #A57A4E → #7A5429（2026-10 随皮革下架）
    ]

    /// 见 `HomeDisplayMode.displayName` 的注释：常驻界面的文案用 `LocalizedStringKey`，
    /// 这样用户切换语言时能当场跟着变
    var displayName: LocalizedStringKey {
        switch self {
        case .wineRed:      return "酒红"
        case .pineGreen:    return "墨绿"
        case .prussianBlue: return "普鲁士蓝"
        case .eggplant:     return "茄紫"
        case .amberBrown:   return "琥珀棕"
        case .charcoal:     return "炭黑"
        case .slate:        return "石灰"
        case .ivory:        return "象牙白"
        }
    }

    /// 颜色色点（仅用于颜色选择器的小圆点预览；实际封面渲染走 Cover_* 图）
    var hex: String {
        switch self {
        case .wineRed:      return "#592A2C"
        case .pineGreen:    return "#34473B"
        case .prussianBlue: return "#233C58"
        case .eggplant:     return "#3E2F43"
        case .amberBrown:   return "#7A5429"
        case .charcoal:     return "#201E1C"
        case .slate:        return "#625F5C"
        case .ivory:        return "#EBE2D2"
        }
    }

    /// 浅色底（仅象牙白），决定叠加文字颜色（深棕 vs 米白）
    var isLight: Bool {
        switch self {
        case .ivory: return true
        default:     return false
        }
    }
}
