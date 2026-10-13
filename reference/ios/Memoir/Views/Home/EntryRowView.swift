import SwiftUI

struct EntryRowView: View {
    @Environment(ThemeManager.self) private var themeManager
    let entry: JournalEntry

    private var hasContext: Bool {
        WeatherLocationBadge.hasContent(entry.weatherCode, entry.weatherInfo, entry.locationInfo)
    }

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.date.dayAndWeekday)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                if !entry.mood.isEmpty {
                    MoodBadge(name: entry.mood, colorHex: entry.moodColorHex)
                }
            }

            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(theme.headingFont)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
            }

            Text(entry.content.prefix(60) + (entry.content.count > 60 ? "..." : ""))
                .font(theme.bodyFont)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(theme.bodyLineSpacing)
                .lineLimit(2)

            // 底部一行：标签在左，此时此地在右 —— 元信息聚在一起，不跟标题抢视线
            if !entry.tags.isEmpty || hasContext {
                HStack(spacing: 4) {
                    ForEach(entry.tags.prefix(3), id: \.self) { tag in
                        TagPill(name: tag)
                    }
                    Spacer(minLength: 8)
                    WeatherLocationBadge(
                        weatherCode: entry.weatherCode,
                        weatherInfo: entry.weatherInfo,
                        locationInfo: entry.locationInfo,
                        font: theme.labelFont,
                        color: theme.textTertiary,
                        iconSize: 10
                    )
                }
            }
        }
        .padding(16)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.border, lineWidth: 0.5)
        )
    }
}
