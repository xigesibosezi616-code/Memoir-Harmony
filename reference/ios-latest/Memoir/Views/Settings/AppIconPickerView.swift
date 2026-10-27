import SwiftUI

/// App 图标选择页。
///
/// 默认是**跟随主题** —— 换主题时图标自动跟着换（这是本来就有的行为）。
/// 用户一旦手动选了某个图标，就固定下来，之后换主题不再覆盖他的选择。
struct AppIconPickerView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var manager = themeManager
        let theme = themeManager.current

        ScrollView {
            VStack(spacing: 16) {
                followThemeRow(theme: theme)

                Divider()
                    .overlay(theme.textTertiary.opacity(0.25))
                    .padding(.vertical, 4)

                ForEach(AppIconOption.allCases) { option in
                    iconRow(option: option, theme: theme)
                }

                Text("每个主题配一个图标。以后新增主题时，这里也会多一个。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                    .padding(.horizontal, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(themeManager.settingsPage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("应用图标")
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    // MARK: - 行

    private func followThemeRow(theme: any AppTheme) -> some View {
        let isSelected = themeManager.isFollowingThemeIcon

        return Button {
            select(nil)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "paintbrush")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 56, height: 56)
                    .background(theme.accentBackground, in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 2) {
                    Text("跟随主题")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                    Text("换主题时图标自动跟着换")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(12)
            .background(themeManager.settingsCard, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func iconRow(option: AppIconOption, theme: any AppTheme) -> some View {
        // 选中态看的是「用户选的是不是这一个」，而不是「当前生效的是不是这一个」——
        // 跟随主题时当前生效的也是某一个图标，但那时候勾应该打在「跟随主题」上
        let isSelected = !themeManager.isFollowingThemeIcon
            && themeManager.appIconSelection == option.rawValue

        return Button {
            select(option)
        } label: {
            HStack(spacing: 14) {
                iconPreview(option: option, theme: theme)

                Text(option.displayName)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(12)
            .background(themeManager.settingsCard, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// 预览图。取不到资源时画一个占位框而不是留空 ——
    /// 空白会让人以为是加载中，占位框能看出「这个图标的素材还没放进来」
    @ViewBuilder
    private func iconPreview(option: AppIconOption, theme: any AppTheme) -> some View {
        if let image = UIImage(named: option.previewAsset) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                // 素笺图标的底和卡片同色，不描一圈就看不出图标的边
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(theme.border, lineWidth: 0.5))
        } else {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(theme.textTertiary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.textTertiary)
                }
        }
    }

    // MARK: - 选择

    /// `nil` = 跟随主题
    private func select(_ option: AppIconOption?) {
        // 用户手动点的，失败必须让他看见 —— 否则就是「点了没反应」，
        // 和之前 LeatherIcon 静默失败一模一样。
        // 走 `selectAppIcon` 而不是自己赋值再 apply：后者会切两次，弹两次系统提示
        withAnimation(.spring(duration: 0.3)) {
            themeManager.selectAppIcon(option) { error in
                env.errors.present(error, fallback: NSLocalizedString(
                    "图标切换失败，请稍后再试",
                    bundle: .appLanguage,
                    comment: "App 图标切换失败提示"
                ))
            }
        }
    }
}
