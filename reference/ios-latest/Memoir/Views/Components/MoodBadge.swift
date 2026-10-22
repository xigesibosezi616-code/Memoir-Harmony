import SwiftUI

/// 日记上的心情（2026-10-17 换成九档，旧的心情标签药丸已删）：这一档颜色的小圆点 + 档名，
/// 详情页再跟上情绪词（「满心欢喜 · 开心、感恩」）。没记心情的日记（心情页上线之前写的）调用方不放它。
struct MoodBadge: View {
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("appLanguage") private var appLanguage: String = ""
    let level: MoodLevel
    /// 详情页带上情绪词，列表那行只要档名
    var labels: [MoodLabel] = []

    /// 情绪词之间的分隔：中日用顿号，其他语言用逗号
    private var separator: String {
        appLanguage.hasPrefix("zh") || appLanguage.hasPrefix("ja") ? "、" : ", "
    }

    var body: some View {
        let theme = themeManager.current
        HStack(spacing: 6) {
            Circle()
                .fill(level.tint)
                .frame(width: 7, height: 7)
            Text(level.title)
            if !labels.isEmpty {
                Text(verbatim: "·")
                    .opacity(0.6)
                HStack(spacing: 0) {
                    ForEach(Array(labels.enumerated()), id: \.element) { index, label in
                        if index > 0 {
                            Text(verbatim: separator)
                        }
                        Text(label.title)
                    }
                }
            }
        }
        // 不加主题的宽字距：四字的档名一拉开就成了「郁 郁 寡 欢」
        .font(theme.labelFont)
        .foregroundStyle(theme.textSecondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
