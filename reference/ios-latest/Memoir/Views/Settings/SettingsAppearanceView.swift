import SwiftUI

/// 设置 →「外观」二级页。
///
/// 条目从原来的一级页原样搬过来（主题 / 应用图标 / 启动动画 / 手记页展示）；2026-10-27 加「搜索日记」开关（底栏出不出搜索圆，默认关）。
/// **「语言」没有搬进来** —— 它在一级页单列一行直通选择页，少一层跳转。
struct SettingsAppearanceView: View {
    @Environment(ThemeManager.self) private var themeManager

    @AppStorage("showSplashAnimation") private var showSplashAnimation: Bool = true
    @AppStorage(DiarySearch.tabStorageKey) private var showSearchTab = false
    /// 手记页展示方式：大屏（默认）/ 列表
    @AppStorage(HomeDisplayMode.storageKey) private var homeDisplayModeRaw: String = HomeDisplayMode.defaultMode.rawValue

    private var currentHomeDisplayMode: HomeDisplayMode {
        HomeDisplayMode(rawValue: homeDisplayModeRaw) ?? .defaultMode
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
                .listRowBackground(themeManager.settingsCard)

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
                .listRowBackground(themeManager.settingsCard)

                HStack {
                    SettingsRow(icon: "sparkles", title: "启动动画", theme: theme)
                    Spacer()
                    Toggle("", isOn: $showSplashAnimation)
                        .labelsHidden()
                        .tint(theme.accent)
                }
                .listRowBackground(themeManager.settingsCard)

                // 打开了底栏右边才多一颗搜索圆；关着就是原来四个 tab（默认关）
                HStack {
                    SettingsRow(icon: "magnifyingglass", title: "搜索日记", theme: theme)
                    Spacer()
                    Toggle("", isOn: $showSearchTab)
                        .labelsHidden()
                        .tint(theme.accent)
                }
                .listRowBackground(themeManager.settingsCard)
            } footer: {
                Text("打开后，底栏右边多一个搜索按钮，可以按关键字找写过的日记。")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
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
                .listRowBackground(themeManager.settingsCard)

                Text(currentHomeDisplayMode.detail)
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
                    .listRowBackground(themeManager.settingsCard)
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
