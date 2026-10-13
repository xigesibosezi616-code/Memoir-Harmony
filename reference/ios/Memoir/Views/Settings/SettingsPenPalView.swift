import SwiftUI

/// 设置 →「笔友」二级页。
struct SettingsPenPalView: View {
    @Environment(ThemeManager.self) private var themeManager

    /// 用户给笔友起的名字（默认"青鸟"）—— 共享 key，PostBoxView/Onboarding 也读这个
    @AppStorage("penPalName") private var penPalName: String = "青鸟"

    var body: some View {
        let theme = themeManager.current
        SettingsSubpage(title: "笔友") {
            Section {
                HStack {
                    SettingsRow(icon: "person.crop.circle", title: "笔友名", theme: theme)
                    Spacer()
                    TextField("青鸟", text: $penPalName)
                        .font(theme.captionFont)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(theme.textPrimary)
                        .submitLabel(.done)
                        .onSubmit {
                            let trimmed = penPalName.trimmingCharacters(in: .whitespacesAndNewlines)
                            penPalName = trimmed.isEmpty ? "青鸟" : trimmed
                        }
                }
                .listRowBackground(theme.cardBackground)
            } footer: {
                Text("用户给笔友起的名字会出现在新来信的署名上。改名只影响之后的新信，历史信件的署名不变。")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}
