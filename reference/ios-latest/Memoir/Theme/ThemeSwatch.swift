import SwiftUI

/// 每个主题的「两个主色」：主题列表左边那两块颜色。
///
/// 桌面图标（底色 + 手写 m.）和开场写字动画都**严格用这两个色**（2026-10-24 产品定），
/// 所以收在这一处。改了这里，要用 `Scripts/make_app_icon.py`（`THEMES` 里同样的色值）重出图标
enum ThemeSwatch {
    /// `background` = 纸（图标底色），`ink` = 字
    static func colors(for themeID: String) -> (background: Color, ink: Color) {
        switch themeID {
        case "leather": (Color(hex: "#1C1410"), Color(hex: "#C8A87C"))
        case "kent": (Color(hex: "#FFFFFF"), Color(hex: "#1A1A1A"))
        case "polar": (Color(hex: "#000000"), Color(hex: "#8FA8BF"))
        default: (Color(hex: "#FAF7F2"), Color(hex: "#8B7E6A"))   // bamboo
        }
    }
}
