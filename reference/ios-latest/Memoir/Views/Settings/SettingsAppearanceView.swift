import SwiftUI

/// 设置 →「外观」二级页。
///
/// 条目从原来的一级页原样搬过来（主题 / 应用图标 / 启动动画 / 手记页展示）。
/// **「语言」没有搬进来** —— 它在一级页单列一行直通选择页，少一层跳转。
struct SettingsAppearanceView: View {
    @Environment(ThemeManager.self) private var themeManager

    @AppStorage("showSplashAnimation") private var showSplashAnimation: Bool = true
    /// 手记页展示方式：列表 / 大屏
    @AppStorage(HomeDisplayMode.storageKey) private var homeDisplayModeRaw: String = HomeDisplayMode.list.rawValue

    private var currentHomeDisplayMode: HomeDisplayMode {
        HomeDisplayMode(rawValue: homeDisplayModeRaw) ?? .list
    }

    var body: some View {
        let theme = themeManager.current
        SettingsSubpage(title: "外观") {
            Section {
                NavigationLink {
                    ThemePickerView()
                } label: {
                    SettingsRow(icon: "paintbrush", title: "主题选择", theme: theme)
                }
                .listRowBackground(theme.cardBackground)

                NavigationLink {
                    AppIconPickerView()
                } label: {
                    HStack {
                        SettingsRow(icon: "app.badge", title: "应用图标", theme: theme)
                        Spacer()
                        Text(themeManager.isFollowingThemeIcon
                             ? "跟随主题"
                             : themeManager.resolvedAppIcon.displayName)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .listRowBackground(theme.cardBackground)

                HStack {
                    SettingsRow(icon: "sparkles", title: "启动动画", theme: theme)
                    Spacer()
                    Toggle("", isOn: $showSplashAnimation)
                        .labelsHidden()
                        .tint(theme.accent)
                }
                .listRowBackground(theme.cardBackground)
            }

            Section {
                HStack {
                    SettingsRow(icon: currentHomeDisplayMode.iconName, title: "手记页", theme: theme)
                    Spacer()
                    Picker("", selection: $homeDisplayModeRaw) {
                        ForEach(HomeDisplayMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .tint(theme.textTertiary)
                }
                .listRowBackground(theme.cardBackground)

                Text(currentHomeDisplayMode.detail)
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
                    .listRowBackground(theme.cardBackground)
            } header: {
                Text("展示")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            } footer: {
                Text("大屏模式下，长按写日记页里的照片可指定封面。")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}
