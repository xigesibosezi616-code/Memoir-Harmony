import SwiftUI

struct KentTheme: AppTheme {
    let background = Color(hex: "#FFFFFF")
    let cardBackground = Color(hex: "#FFFFFF")
    let surfaceBackground = Color(hex: "#F8F8F8")
    let sidebarBackground = Color(hex: "#1A1A1A")

    let textPrimary = Color(hex: "#1A1A1A")
    let textSecondary = Color(hex: "#666666")
    let textTertiary = Color(hex: "#999999")

    let border = Color(hex: "#E5E5E5")
    let borderAccent = Color(hex: "#1A1A1A")

    let accent = Color(hex: "#1A1A1A")
    let accentBackground = Color(hex: "#F0F0F0")
    let preferredColorScheme: ColorScheme? = nil
    let mailboxImageName = "Mailbox_Kent"

    let moodBackground = Color(hex: "#F0F0F0")
    let moodBorder = Color(hex: "#E5E5E5")
    let moodText = Color(hex: "#1A1A1A")

    let destructive = Color(hex: "#E8453A")

    let titleFont = Font.custom("Georgia", size: 22)
    let headingFont = Font.custom("Georgia", size: 18)
    let bodyFont = Font.custom("Georgia", size: 14)
    let bodyLineSpacing: CGFloat = 8
    let captionFont = Font.system(size: 12, weight: .regular)
    let labelFont = Font.system(size: 10, weight: .regular)
    let letterSpacingWide: CGFloat = 2
}
