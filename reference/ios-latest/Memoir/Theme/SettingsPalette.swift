import SwiftUI

/// 设置页的配色（2026-10-26，照苹果「设置」的分层做）。
///
/// - **页面底和卡片要分得开**：素笺、肯特原来卡片和页面同色，整页看不出一块一块的分组（苹果是灰底白卡）
/// - 每一行的图标**还是原来那套线条图标、原来的颜色**（主题的次要文字色），外面套一个细线方框（`SettingsTile`）。
///   试过苹果那样每格一种底色，用户不要：原来的更简洁
/// - 按主题 id 取；没认出来的主题按素笺
enum SettingsPalette {
    /// 页面底
    static func page(_ themeID: String) -> Color {
        switch themeID {
        case "leather": Color(hex: "#1C1410")
        case "kent": Color(hex: "#F2F2F5")
        case "polar": Color(hex: "#000000")
        default: Color(hex: "#F0EBE1")
        }
    }

    /// 卡片
    static func card(_ themeID: String) -> Color {
        switch themeID {
        case "leather": Color(hex: "#2A2019")
        case "kent": Color(hex: "#FFFFFF")
        case "polar": Color(hex: "#1C1C1E")
        default: Color(hex: "#FAF7F2")
        }
    }
}

/// 设置一级页每行前面的小方框：细线圆角框，里面是原色的图标。**不填底色**
struct SettingsTile<Glyph: View>: View {
    let theme: any AppTheme
    @ViewBuilder var glyph: Glyph

    static var size: CGFloat { 30 }

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(theme.border, lineWidth: 1)
            .frame(width: Self.size, height: Self.size)
            .overlay { glyph }
    }
}

extension ThemeManager {
    /// 设置各页（一级、二级、三级）的页面底 / 卡片色，见 `SettingsPalette`
    var settingsPage: Color { SettingsPalette.page(currentThemeID) }
    var settingsCard: Color { SettingsPalette.card(currentThemeID) }
}
