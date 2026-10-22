import SwiftUI

/// 极夜：纯黑的深色主题（2026-10-17 产品定），像聊天软件的深色模式。
///
/// 底是真正的 `#000000` —— OLED 屏上黑色的像素直接熄灭；卡片、浮层只比底色抬一点点。
/// 字不用纯白（`#E5E5EA`），满屏纯白字在黑底上晃眼。强调色是肯特图标上那一支蓝（`#8FA8BF`），
/// 图标也是肯特的那个本子换了颜色：纯黑底、灰线框、肯特的浅蓝书签带。
struct PolarTheme: AppTheme {
    let background = Color(hex: "#000000")
    let cardBackground = Color(hex: "#0E0E10")
    let surfaceBackground = Color(hex: "#1C1C1E")
    let sidebarBackground = Color(hex: "#000000")

    let textPrimary = Color(hex: "#E5E5EA")
    let textSecondary = Color(hex: "#8E8E93")
    let textTertiary = Color(hex: "#636366")

    let border = Color(hex: "#2C2C2E")
    let borderAccent = Color(hex: "#8FA8BF").opacity(0.35)

    let accent = Color(hex: "#8FA8BF")
    let accentBackground = Color(hex: "#1C1C1E")
    let preferredColorScheme: ColorScheme? = .dark
    let mailboxImageName = "Mailbox_Polar"

    let moodBackground = Color(hex: "#1C1C1E")
    let moodBorder = Color(hex: "#2C2C2E")
    let moodText = Color(hex: "#8FA8BF")

    let destructive = Color(hex: "#FF453A")

    let titleFont = Font.custom("Georgia", size: 22)
    let headingFont = Font.custom("Georgia", size: 18)
    let bodyFont = Font.custom("Georgia", size: 14)
    let bodyLineSpacing: CGFloat = 8
    let captionFont = Font.system(size: 12, weight: .regular)
    let labelFont = Font.system(size: 10, weight: .regular)
    let letterSpacingWide: CGFloat = 2
}
