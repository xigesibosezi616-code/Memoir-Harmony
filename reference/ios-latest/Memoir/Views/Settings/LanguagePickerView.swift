import SwiftUI

struct LanguagePickerView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        let theme = themeManager.current
        List {
            // 六种语言，一个都不能少。
            //
            // ⚠️ 这里**不要**再出现「跟随系统」——首启时后台已按系统语言定了一个
            // （`LanguageManager.resolveInitialLanguage`），设置页只呈现明确的语言，
            // 不给用户一个"到底现在是哪种"说不清的选项。见 CLAUDE.md「多语言」一节。
            //
            // ⚠️ 也**不要**再 `.dropFirst()`：那是「跟随系统」还占着数组第一项时留下的写法，
            // 去掉那一项之后它吃掉的是**简体中文**——简中用户根本选不回自己的语言。
            Section {
                ForEach(LanguageManager.supportedLanguages) { lang in
                    Button {
                        languageManager.appLanguage = lang.id
                    } label: {
                        HStack {
                            Text(lang.displayName)
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            if languageManager.appLanguage == lang.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(theme.accent)
                            }
                        }
                    }
                    .listRowBackground(themeManager.settingsCard)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(themeManager.settingsPage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("语言 / Language")
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}
