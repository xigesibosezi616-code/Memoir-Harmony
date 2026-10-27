import SwiftUI

/// 设置页里一行的标准样式（SF Symbol + 文字）。
///
/// **为什么从 `SettingsView` 里抽出来**：设置页拆成一级 + 七个二级页之后，
/// 七个文件都要用同一种行样式。留在 `SettingsView` 里当私有方法的话，
/// 每个二级页都得复制一份 —— 复制出去就会各自漂移，最后每页长得不一样。
///
/// 🔴 **`title` 必须是 `LocalizedStringKey`，不能是 `String`**（见 `CLAUDE.md` 多语言第 6 条）：
/// ① `Text(String)` 不查本地化表；
/// ② 参数是 `String` 时，Xcode 的提取器**根本不会**把调用处的中文收进 catalog，
///    于是连「漏翻了」都看不见。设置页整页在外语下显示中文就是这么来的（2026-08-08 修）。
///
/// 内容是**用户数据**（昵称、脱敏手机号、地名）时用 `dynamicTitle:` 那个版本 ——
/// 单独一个参数标签，让「这行不该翻译」在调用处就看得见。
struct SettingsRow: View {
    let icon: String
    private let label: Text
    let theme: any AppTheme

    init(icon: String, title: LocalizedStringKey, theme: any AppTheme) {
        self.icon = icon
        self.label = Text(title)
        self.theme = theme
    }

    init(icon: String, dynamicTitle: String, theme: any AppTheme) {
        self.icon = icon
        self.label = Text(dynamicTitle)
        self.theme = theme
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 20)
            label
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
        }
    }
}

/// 二级页的统一外壳：主题背景 + 居中的小标题。
///
/// 七个二级页的导航栏样式必须一致，各写一遍迟早会漂。
struct SettingsSubpage<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        List {
            content
        }
        .scrollContentBackground(.hidden)
        .background(themeManager.settingsPage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}
