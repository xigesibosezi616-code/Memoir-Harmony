import SwiftUI

/// 心情页第二步的情绪词（2026-10-17 产品定）。用苹果「健康」的那 38 个（以后能原样写进「健康」），存的是英文 key（`rawValue`）。
///
/// 第一步滑杆选个大概（九档），第二步在**这一档**对应的 3～5 个词里**选一个**（`choices(for:)`），然后结束。
/// 38 个词分到九档，每个词只在一档里出现。
nonisolated enum MoodLabel: String, CaseIterable, Identifiable {
    case hopeless, overwhelmed, scared, angry, disgusted
    case sad, lonely, disappointed, guilty, ashamed
    case drained, discouraged, frustrated, anxious, jealous
    case annoyed, irritated, stressed, worried, embarrassed
    case calm, peaceful, indifferent
    case content, satisfied, relieved, grateful
    case happy, joyful, amused, hopeful
    case confident, proud, brave, passionate
    case excited, amazed, surprised

    var id: String { rawValue }

    /// 这一档给哪几个词（常见的在前）
    static func choices(for level: MoodLevel) -> [MoodLabel] {
        switch level {
        case .rockBottom: return [.hopeless, .overwhelmed, .scared, .angry, .disgusted]
        case .heartsick: return [.sad, .lonely, .disappointed, .guilty, .ashamed]
        case .melancholy: return [.drained, .discouraged, .frustrated, .anxious, .jealous]
        case .glum: return [.annoyed, .irritated, .stressed, .worried, .embarrassed]
        case .even: return [.calm, .peaceful, .indifferent]
        case .content: return [.content, .satisfied, .relieved, .grateful]
        case .joyful: return [.happy, .joyful, .amused, .hopeful]
        case .radiant: return [.confident, .proud, .brave, .passionate]
        case .overjoyed: return [.excited, .amazed, .surprised]
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .drained: return "疲惫"
        case .stressed: return "压力大"
        case .worried: return "担心"
        case .anxious: return "焦虑"
        case .sad: return "难过"
        case .lonely: return "孤独"
        case .annoyed: return "心烦"
        case .irritated: return "烦躁"
        case .frustrated: return "挫败"
        case .disappointed: return "失望"
        case .discouraged: return "泄气"
        case .overwhelmed: return "不堪重负"
        case .angry: return "生气"
        case .scared: return "害怕"
        case .guilty: return "内疚"
        case .ashamed: return "羞愧"
        case .embarrassed: return "尴尬"
        case .jealous: return "嫉妒"
        case .disgusted: return "厌恶"
        case .hopeless: return "绝望"
        case .happy: return "开心"
        case .calm: return "平静"
        case .content: return "满足"
        case .grateful: return "感恩"
        case .peaceful: return "安宁"
        case .relieved: return "释然"
        case .satisfied: return "满意"
        case .hopeful: return "满怀希望"
        case .excited: return "兴奋"
        case .joyful: return "喜悦"
        case .amused: return "被逗乐"
        case .surprised: return "惊讶"
        case .amazed: return "惊叹"
        case .confident: return "自信"
        case .proud: return "自豪"
        case .brave: return "勇敢"
        case .passionate: return "热情"
        case .indifferent: return "无感"
        }
    }
}
