import SwiftUI

/// 主题选择页 —— 「挑一种纸」，不是「选一个配色」。
///
/// 点主题**不再立刻生效**：先弹出 `ThemeIntroSheet` 讲这种纸的来历，
/// 用户在弹窗底部选「一并更换图标」还是「仅更换主题」，下滑关闭则什么都不做。
/// 已经选中的主题再点一次同样弹窗（用户可能想重读，或想补换图标）。
struct ThemePickerView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env

    /// 正在介绍哪张纸；非 nil 时弹窗出现，**此时主题尚未切换**
    @State private var previewingPaper: ThemePaper?
    /// 弹窗关闭后要执行的切换。下滑关闭时它是 nil —— 什么都不做
    @State private var pendingChoice: ThemeSwitchChoice?

    var body: some View {
        let theme = themeManager.current
        ScrollView {
            VStack(spacing: 16) {
                ForEach(ThemePaper.all) { paper in
                    themeRow(paper: paper, theme: theme)
                }

                Text("还在裁纸")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.top, 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("主题选择")
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        // 切换放在 onDismiss 里：必须**先关掉我们的弹窗再换图标**，
        // 否则系统那个关不掉的「您已更改图标」提示会和它叠在一起
        .sheet(item: $previewingPaper, onDismiss: applyPendingChoice) { paper in
            ThemeIntroSheet(paper: paper) { choice in
                pendingChoice = choice
                previewingPaper = nil
            }
        }
    }

    // MARK: - 切换

    private func applyPendingChoice() {
        // 下滑关闭 / 点关闭 —— 保持原主题，列表选中态不变
        guard let choice = pendingChoice else { return }
        pendingChoice = nil

        switch choice {
        case .themeAndIcon(let id):
            withAnimation(.spring(duration: 0.3)) {
                themeManager.switchTheme(to: id, alsoIcon: true) { error in
                    // 图标没换成不影响主题 —— 主题保持已切换的状态，只说图标这件事
                    env.errors.present(error, fallback: NSLocalizedString(
                        "主题已更换，图标没能跟着换",
                        bundle: .appLanguage,
                        comment: "主题切换成功但 App 图标切换失败"
                    ))
                }
            }
        case .themeOnly(let id):
            withAnimation(.spring(duration: 0.3)) {
                themeManager.switchTheme(to: id, alsoIcon: false)
            }
        }
    }

    // MARK: - 行

    private func themeRow(paper: ThemePaper, theme: any AppTheme) -> some View {
        let isSelected = themeManager.currentThemeID == paper.id

        return Button {
            previewingPaper = paper
        } label: {
            HStack(spacing: 14) {
                themePreview(id: paper.id)

                VStack(alignment: .leading, spacing: 3) {
                    Text(paper.name)
                        .font(theme.headingFont)
                        .foregroundStyle(theme.textPrimary)
                    // 允许两行，**不要截断成省略号** —— 不设 lineLimit，让它自己换行
                    Text(paper.subtitle)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(16)
            .background(theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func themePreview(id: String) -> some View {
        let colors: (bg: Color, fg: Color) = switch id {
        case "bamboo": (Color(hex: "#FAF7F2"), Color(hex: "#8B7E6A"))
        case "leather": (Color(hex: "#1C1410"), Color(hex: "#C8A87C"))
        case "kent": (Color(hex: "#FFFFFF"), Color(hex: "#1A1A1A"))
        case "polar": (Color(hex: "#000000"), Color(hex: "#8FA8BF"))
        default: (Color(hex: "#FAF7F2"), Color(hex: "#8B7E6A"))
        }

        return RoundedRectangle(cornerRadius: 8)
            .fill(colors.bg)
            .frame(width: 48, height: 48)
            .overlay(
                Text("文")
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .foregroundStyle(colors.fg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
            )
    }
}
