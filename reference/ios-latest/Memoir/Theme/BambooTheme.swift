import SwiftUI

struct BambooTheme: AppTheme {
    let background = Color(hex: "#FAF7F2")
    let cardBackground = Color(hex: "#FAF7F2")
    let surfaceBackground = Color(hex: "#F5F0E7")
    let sidebarBackground = Color(hex: "#F0EBE1")

    let textPrimary = Color(hex: "#3D3428")
    let textSecondary = Color(hex: "#8B7E6A")
    let textTertiary = Color(hex: "#C8BDA8")

    let border = Color(hex: "#E8E2D6")
    let borderAccent = Color(hex: "#D4C9B8")

    let accent = Color(hex: "#8B7E6A")
    let accentBackground = Color(hex: "#F0EBE1")
    let preferredColorScheme: ColorScheme? = nil
    let mailboxImageName = "Mailbox_Bamboo"

    let moodBackground = Color(hex: "#F0EBE1")
    let moodBorder = Color(hex: "#D4C9B8")
    let moodText = Color(hex: "#8B7E6A")

    let destructive = Color(hex: "#E8453A")

    let titleFont = Font.custom("Georgia", size: 22)
    let headingFont = Font.custom("Georgia", size: 18)
    let bodyFont = Font.custom("Georgia", size: 14)
    let bodyLineSpacing: CGFloat = 8
    let captionFont = Font.system(size: 12, weight: .regular)
    let labelFont = Font.system(size: 10, weight: .regular)
    let letterSpacingWide: CGFloat = 3
}
