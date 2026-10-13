import SwiftUI

struct OnboardingView: View {
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hasCompletedOnboarding") private var hasCompleted = false
    @AppStorage("penPalName") private var penPalName: String = "青鸟"
    @State private var selectedTheme = "bamboo"
    @FocusState private var penPalFieldFocused: Bool

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            Spacer()

            // Brand
            VStack(spacing: 12) {
                Text("Memoir · 尺素")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)

                Text("写给自己的日记")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(theme.bodyLineSpacing)
            }

            Spacer().frame(height: 48)

            // Theme selection
            VStack(spacing: 12) {
                Text("选择你的纸张")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .tracking(theme.letterSpacingWide)

                HStack(spacing: 16) {
                    themeOption(id: "bamboo", name: "素笺", bg: Color(hex: "#FAF7F2"), fg: Color(hex: "#8B7E6A"))
                    themeOption(id: "leather", name: "皮革", bg: Color(hex: "#1C1410"), fg: Color(hex: "#C8A87C"))
                    themeOption(id: "kent", name: "肯特", bg: Color(hex: "#FFFFFF"), fg: Color(hex: "#1A1A1A"))
                }
            }

            Spacer().frame(height: 40)

            // 笔友起名（可跳过 → 默认"青鸟"）
            VStack(spacing: 10) {
                Text("给笔友起个名字")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .tracking(theme.letterSpacingWide)

                TextField("青鸟", text: $penPalName)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.border, lineWidth: 0.5)
                    )
                    .padding(.horizontal, 60)
                    .focused($penPalFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { penPalFieldFocused = false }

                Text("可跳过，之后在设置里也能改")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            // CTA
            Button {
                // 提交时 trim + 空了恢复默认"青鸟"
                let trimmed = penPalName.trimmingCharacters(in: .whitespacesAndNewlines)
                penPalName = trimmed.isEmpty ? "青鸟" : trimmed
                themeManager.currentThemeID = selectedTheme
                hasCompleted = true
            } label: {
                Text("开始书写")
                    .font(theme.headingFont)
                    .foregroundStyle(theme.cardBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
        .background(theme.background)
    }

    private func themeOption(id: String, name: String, bg: Color, fg: Color) -> some View {
        let theme = themeManager.current
        let isSelected = selectedTheme == id

        return Button {
            withAnimation(.spring(duration: 0.25)) {
                selectedTheme = id
            }
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(bg)
                    .frame(width: 72, height: 96)
                    .overlay(
                        Text("文")
                            .font(.system(size: 24, weight: .light, design: .serif))
                            .foregroundStyle(fg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? theme.accent : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 0.5)
                    )
                Text(name)
                    .font(theme.labelFont)
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
