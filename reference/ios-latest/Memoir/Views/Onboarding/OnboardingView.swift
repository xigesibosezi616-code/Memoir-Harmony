import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompleted = false
    /// 没有默认名：首启必须起名才能进（2026-10-24 产品定，见 `PenPalName`）
    @AppStorage(PenPalName.storageKey) private var penPalName: String = ""
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
                    themeOption(id: "polar", name: "极夜", bg: Color(hex: "#000000"), fg: Color(hex: "#8FA8BF"))
                }
            }

            Spacer().frame(height: 40)

            // 笔友起名：必填，不能跳过
            VStack(spacing: 10) {
                Text("给笔友起个名字")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .tracking(theme.letterSpacingWide)

                TextField("写一个名字", text: $penPalName)
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
                    .onChange(of: penPalName) { _, new in
                        if new.count > PenPalName.maxLength { penPalName = String(new.prefix(PenPalName.maxLength)) }
                    }

                Text("笔友会用这个名字给你写信，之后在设置里也能改")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            // CTA：没起名点不了
            Button {
                penPalName = PenPalName.normalized(penPalName)
                themeManager.currentThemeID = selectedTheme
                // 新手指引从头开始，Sinara 的欢迎信放进信箱（见 `FirstStep`）
                FirstStep.begin(in: modelContext, toName: nil)
                hasCompleted = true
            } label: {
                Text("开始书写")
                    .font(theme.headingFont)
                    .foregroundStyle(theme.cardBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(PenPalName.needsNaming(penPalName) ? 0.4 : 1)
            }
            .disabled(PenPalName.needsNaming(penPalName))
            .animation(.easeInOut(duration: 0.2), value: PenPalName.needsNaming(penPalName))
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
        .background(theme.background)
    }

    /// `name` 必须是 `LocalizedStringKey`：原来是 `String`，`Text(String)` 不查翻译表，主题名在任何语言下都显示中文（2026-10-17 加极夜时修）
    private func themeOption(id: String, name: LocalizedStringKey, bg: Color, fg: Color) -> some View {
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
