import SwiftUI

/// 设置 →「笔友」二级页。
struct SettingsPenPalView: View {
    @Environment(ThemeManager.self) private var themeManager

    /// 用户给笔友起的名字 —— 共享 key（`PenPalName.storageKey`），邮筒、首启页也读这个
    @AppStorage(PenPalName.storageKey) private var penPalName: String = ""
    /// 正在改的名字。不直接绑存储：清空了离开页面时名字会变成空的（笔友没有默认名可退）
    @State private var draft = ""

    var body: some View {
        let theme = themeManager.current
        SettingsSubpage(title: "笔友") {
            Section {
                HStack {
                    SettingsRow(icon: "person.crop.circle", title: "笔友名", theme: theme)
                    Spacer()
                    TextField("写一个名字", text: $draft)
                        .font(theme.captionFont)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(theme.textPrimary)
                        .submitLabel(.done)
                        .onSubmit(commit)
                        .onChange(of: draft) { _, new in
                            if new.count > PenPalName.maxLength { draft = String(new.prefix(PenPalName.maxLength)) }
                        }
                }
                .listRowBackground(themeManager.settingsCard)
            } footer: {
                Text("用户给笔友起的名字会出现在新来信的署名上。改名只影响之后的新信，历史信件的署名不变。")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .onAppear { draft = PenPalName.needsNaming(penPalName) ? "" : penPalName }
        // 没按「完成」就离开也算数；清空了就当没改
        .onDisappear(perform: commit)
    }

    /// 有名字才存；空的恢复原名
    private func commit() {
        let name = PenPalName.normalized(draft)
        if PenPalName.needsNaming(name) {
            draft = PenPalName.needsNaming(penPalName) ? "" : penPalName
        } else {
            penPalName = name
            draft = name
        }
    }
}
