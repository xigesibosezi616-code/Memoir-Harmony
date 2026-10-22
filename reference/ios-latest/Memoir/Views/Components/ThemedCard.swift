import SwiftUI

struct ThemedCard<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        let theme = themeManager.current
        content()
            .padding(16)
            .background(theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.border, lineWidth: 0.5)
            )
    }
}
