import SwiftUI

/// 主题介绍弹窗 —— 点主题后先读一段纸史，再决定换不换。
///
/// 🔴 **整个弹窗用「即将切换过去的那套主题」的配色渲染，不是当前主题。**
/// 用户在按下确认之前就能看到这套主题长什么样，**弹窗本身就是预览**。
/// 所以这里的 `theme` 一律来自 `ThemeManager.theme(for:)`，
/// 不要图省事写成 `@Environment(ThemeManager.self).current`。
///
/// 弹窗只负责「读」和「选」，**不直接改主题**：选择通过 `onChoose` 抛给调用方，
/// 由调用方先关掉本弹窗、再执行切换 —— 换图标会触发一个系统弹窗，
/// 两层弹窗叠在一起很难看（详见 `ThemePickerView.applyPendingChoice`）。
struct ThemeIntroSheet: View {
    let paper: ThemePaper
    let onChoose: (ThemeSwitchChoice) -> Void

    /// 出处默认收起 —— 它是给想深究的人看的，不该占掉正文的位置
    @State private var showSource = false

    /// 系统当前实际生效的图标是否已经是这套主题的。
    /// 看的是**系统的真实状态**而不是我们以为的状态，两者可能不一致（比如上次切换失败了）
    private var iconAlreadyMatches: Bool {
        AppIconOption.current == paper.icon
    }

    var body: some View {
        let theme = ThemeManager.theme(for: paper.id)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(paper.name)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)

                // 让用户理解「图标也会跟着变」的关键视觉，不能省
                Image(paper.icon.previewAsset)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(theme.border, lineWidth: 0.5)
                    )

                // 这是给人读的内容，不是提示文字 —— 行距按阅读体验放宽
                Text(paper.story)
                    .font(theme.bodyFont)
                    .lineSpacing(theme.bodyLineSpacing + 4)
                    .foregroundStyle(theme.textPrimary)

                sourceSection(theme: theme)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .background(theme.background)
        .safeAreaInset(edge: .bottom) { bottomBar(theme: theme) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 出处

    private func sourceSection(theme: any AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showSource.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("出处")
                    Image(systemName: showSource ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
            }
            .buttonStyle(.plain)

            if showSource {
                Text(paper.source)
                    .font(theme.labelFont)
                    .lineSpacing(5)
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 底部

    private func bottomBar(theme: any AppTheme) -> some View {
        VStack(spacing: 10) {
            Divider().overlay(theme.border)

            // 陈述句，不是问句
            Text("这套主题也有一张对应的桌面图标。")
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)

            Button {
                onChoose(.themeAndIcon(paper.id))
            } label: {
                // 图标已经是这一套时置灰，文案跟着换成陈述当前状态。
                // 写成 if/else 而不是三元表达式，是为了让 `check_localization.py` 认得出这两条
                Group {
                    if iconAlreadyMatches {
                        Text("图标已是这一套")
                    } else {
                        Text("一并更换图标")
                    }
                }
                    .font(theme.bodyFont)
                    .foregroundStyle(iconAlreadyMatches ? theme.textSecondary : theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        iconAlreadyMatches ? theme.accentBackground : theme.accent,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
            .buttonStyle(.plain)
            .disabled(iconAlreadyMatches)

            // 🔴 **次按钮不要做成「取消」的样式。**
            // 只换主题是一个正当选择，不是放弃操作 —— 两个按钮是平等的两条路。
            // 同理，按钮文案不能是「是的 / 否」：用户读完一段长文后，
            // 「是的」已经脱离上下文，他得回头重看提示才知道自己在同意什么。
            Button {
                onChoose(.themeOnly(paper.id))
            } label: {
                Text("仅更换主题")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .background(theme.background)
    }
}
