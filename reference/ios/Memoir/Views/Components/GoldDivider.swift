import SwiftUI

struct GoldDivider: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Rectangle()
            .fill(themeManager.current.border)
            .frame(height: 0.5)
    }
}
