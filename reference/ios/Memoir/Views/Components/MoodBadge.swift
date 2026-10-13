import SwiftUI

struct MoodBadge: View {
    @Environment(ThemeManager.self) private var themeManager
    let name: String
    var colorHex: String?

    /// 尝试翻译默认心情 key，非默认直接显示
    private var displayText: String {
        let translated = MoodTag.localizedName(for: name)
        // 如果翻译结果和原文一样且不是英文 key，说明不是默认心情
        return translated
    }

    var body: some View {
        let theme = themeManager.current
        Text(displayText)
            .font(theme.labelFont)
            .tracking(theme.letterSpacingWide)
            .foregroundStyle(colorHex != nil ? .white.opacity(0.9) : theme.moodText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(colorHex.map { Color(hex: $0).opacity(0.6) } ?? theme.moodBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(colorHex.map { Color(hex: $0).opacity(0.8) } ?? theme.moodBorder, lineWidth: 0.5)
            )
    }
}
