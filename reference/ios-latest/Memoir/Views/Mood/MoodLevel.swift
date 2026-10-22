import SwiftUI

/// 心情的九档（2026-10-17 从七档改成九档，档名换成好听的四字称谓）。愉悦度 -1…1 均分九段。
///
/// 和苹果「健康」：写进去的是愉悦度本身（连续的数），「健康」按自己的七档归类 ——
/// 实测（`HKStateOfMind.ValenceClassification`）是均分七段，分界 ±1/7、±3/7、±5/7。九档的正中落在它的：
/// 跌入谷底 → veryUnpleasant · 黯然神伤、郁郁寡欢 → unpleasant · 闷闷不乐 → slightlyUnpleasant · 不悲不喜 → neutral ·
/// 怡然自得 → slightlyPleasant · 满心欢喜、神采飞扬 → pleasant · 心花怒放 → veryPleasant
nonisolated enum MoodLevel: Int, CaseIterable, Comparable {
    case rockBottom, heartsick, melancholy, glum, even, content, joyful, radiant, overjoyed

    static let count = 9
    /// 一档有多宽（愉悦度）
    static let width = 2.0 / Double(count)

    init(valence: Double) {
        let index = Int(((min(max(valence, -1), 1) + 1) / 2 * Double(Self.count)).rounded(.down))
        self = MoodLevel(rawValue: min(max(index, 0), Self.count - 1)) ?? .even
    }

    static func < (a: MoodLevel, b: MoodLevel) -> Bool { a.rawValue < b.rawValue }

    /// 这一档的中间值（点「平常」之类回到正中时用）
    var centerValence: Double { (Double(rawValue) + 0.5) * Self.width - 1 }

    var isUnpleasant: Bool { self < .even }
    var isPleasant: Bool { self > .even }

    /// 这一档的代表色：取自线团爱心那一档的调色板（`ScribbleHeartDrawing`），从灰蓝一路到玫瑰红。
    /// 写作统计的心情分布、日记上的心情小圆点、选中的情绪词都用它
    @MainActor var tint: Color {
        switch self {
        case .rockBottom: return Color(hex: "#6B7394")
        case .heartsick: return Color(hex: "#7078A8")
        case .melancholy: return Color(hex: "#7380BF")
        case .glum: return Color(hex: "#9E99DB")
        case .even: return Color(hex: "#61BFD1")
        case .content: return Color(hex: "#85D670")
        case .joyful: return Color(hex: "#F5CC4C")
        case .radiant: return Color(hex: "#FF876B")
        case .overjoyed: return Color(hex: "#FA5C94")
        }
    }

    /// 发给后端写进来信提示词用的英文名（不跟 App 语言走，见 `EntrySnapshot.mood`）
    var englishName: String {
        switch self {
        case .rockBottom: return "rock bottom"
        case .heartsick: return "heartsick"
        case .melancholy: return "melancholy"
        case .glum: return "a little glum"
        case .even: return "neither sad nor glad"
        case .content: return "content"
        case .joyful: return "joyful"
        case .radiant: return "radiant"
        case .overjoyed: return "over the moon"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .rockBottom: return "跌入谷底"
        case .heartsick: return "黯然神伤"
        case .melancholy: return "郁郁寡欢"
        case .glum: return "闷闷不乐"
        case .even: return "不悲不喜"
        case .content: return "怡然自得"
        case .joyful: return "满心欢喜"
        case .radiant: return "神采飞扬"
        case .overjoyed: return "心花怒放"
        }
    }

    /// 档位下面那句话（2026-10-17 产品定）：不愉快那头请他停一停（停够 3 秒换成跟着震动呼吸），
    /// 平常和愉快那头说一句好话。🔴 只陪着、不评判，**不许写疗效**（不说「会好的」「能缓解」）
    var hint: LocalizedStringKey {
        switch self {
        case .rockBottom: return "辛苦了。停在这里，握着手机，什么都不用做"
        case .heartsick: return "辛苦了。先别急，停在这里，握着手机"
        case .melancholy: return "没关系。停在这里，握着手机，慢一点"
        case .glum: return "有点闷也没关系。停一会儿，慢一点"
        case .even: return "平平常常，也是好好过的一天"
        case .content: return "有一点点好，也值得记下来"
        case .joyful: return "这份好心情，值得多留一会儿"
        case .radiant: return "这样的日子，值得多记几笔"
        case .overjoyed: return "真好。把这一刻好好收着"
        }
    }
}
