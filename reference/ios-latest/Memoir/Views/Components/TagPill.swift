import SwiftUI

struct TagPill: View {
    @Environment(ThemeManager.self) private var themeManager
    let name: String

    var body: some View {
        let theme = themeManager.current
        Text("#\(name)")
            .font(theme.captionFont)
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.surfaceBackground)
            .clipShape(Capsule())
    }
}
