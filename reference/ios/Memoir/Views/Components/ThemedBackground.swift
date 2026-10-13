import SwiftUI

struct ThemedBackground: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager

    func body(content: Content) -> some View {
        content
            .background(themeManager.current.background)
    }
}

extension View {
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }
}
