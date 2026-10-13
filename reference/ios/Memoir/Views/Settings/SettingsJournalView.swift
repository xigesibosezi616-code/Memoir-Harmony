import SwiftUI

/// 设置 →「日记」二级页。
///
/// 📌 2026-08-12 移除了「心情管理」入口：**心情是产品预设的，用户只能选、不能改。**
/// 连带删掉了 `MoodManagerView`，以及写日记页 `MoodSelector` 里的自建心情按钮。
///
/// **「写作统计」没有搬进来** —— 它是内容页不是设置项，留在一级页单列一行。
struct SettingsJournalView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(StoreKitManager.self) private var store

    @AppStorage("defaultPaperStyle") private var defaultPaperStyleRaw: String = PaperStyle.polaroid.rawValue
    /// 自动封条阈值（天）；超过该天数未打开 → 该日记本封面显示封条
    @AppStorage("dormantDaysThreshold") private var dormantThreshold: Int = 14

    private var defaultPaperStyleDisplay: LocalizedStringKey {
        // 显示实际生效的那个（会员到期后会员款退回宝丽来，见 `PaperStyle.defaultStyle`）
        PaperStyle.defaultStyle(raw: defaultPaperStyleRaw, isMember: store.isMember).displayName
    }

    var body: some View {
        let theme = themeManager.current
        SettingsSubpage(title: "日记") {
            Section {
                NavigationLink {
                    StampSettingsView()
                } label: {
                    SettingsRow(icon: "seal", title: "日记印章", theme: theme)
                }
                .listRowBackground(theme.cardBackground)

                NavigationLink {
                    DefaultPaperStylePickerView()
                } label: {
                    HStack {
                        SettingsRow(icon: "photo.on.rectangle", title: "照片相纸样式", theme: theme)
                        Spacer()
                        Text(defaultPaperStyleDisplay)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .listRowBackground(theme.cardBackground)

                // 封条提醒天数（10 / 14 / 21 / 30 天，默认 14）
                HStack {
                    SettingsRow(icon: "calendar.badge.exclamationmark", title: "封条提醒天数", theme: theme)
                    Spacer()
                    Picker("", selection: $dormantThreshold) {
                        Text("10 天").tag(10)
                        Text("14 天").tag(14)
                        Text("21 天").tag(21)
                        Text("30 天").tag(30)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(theme.textTertiary)
                }
                .listRowBackground(theme.cardBackground)
            }
        }
    }
}
