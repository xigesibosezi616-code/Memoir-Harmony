import SwiftUI

struct LeatherTheme: AppTheme {
    let background = Color(hex: "#1C1410")
    let cardBackground = Color(hex: "#241C16")
    let surfaceBackground = Color(hex: "#2A2019")
    let sidebarBackground = Color(hex: "#140E0A")

    let textPrimary = Color(hex: "#D4C4A8")
    let textSecondary = Color(hex: "#8A7B6A")
    let textTertiary = Color(hex: "#7A6B5A")

    let border = Color(hex: "#3A2E25")
    let borderAccent = Color(hex: "#C8A87C").opacity(0.3)

    let accent = Color(hex: "#C8A87C")
    let accentBackground = Color(hex: "#241C16")
    let preferredColorScheme: ColorScheme? = .dark
    let mailboxImageName = "Mailbox_Leather"

    let moodBackground = Color(hex: "#2D2219")
    let moodBorder = Color(hex: "#3A2E25")
    let moodText = Color(hex: "#C8A87C")

    let destructive = Color(hex: "#E8453A")

    let titleFont = Font.custom("Georgia", size: 22)
    let headingFont = Font.custom("Georgia", size: 18)
    let bodyFont = Font.custom("Georgia", size: 14)
    let bodyLineSpacing: CGFloat = 8
    let captionFont = Font.system(size: 12, weight: .regular)
    let labelFont = Font.system(size: 10, weight: .regular)
    let letterSpacingWide: CGFloat = 3
}
