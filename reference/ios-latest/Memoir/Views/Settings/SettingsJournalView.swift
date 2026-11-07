import SwiftData
import SwiftUI
import UserNotifications

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

    // 提醒写日记（`WritingReminder`）
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @AppStorage(WritingReminder.enabledKey) private var reminderOn = false
    @AppStorage(WritingReminder.minutesKey) private var reminderMinutes = WritingReminder.defaultMinutes
    @AppStorage(WritingReminder.weekdaysKey) private var reminderWeekdays = WritingReminder.defaultWeekdays
    /// 用户在系统设置里关了尺素的通知：开着提醒也发不出来，要告诉他
    @State private var notificationsDenied = false

    private var defaultPaperStyleDisplay: LocalizedStringKey {
        // 显示实际生效的那个（会员到期后会员款退回宝丽来，见 `PaperStyle.defaultStyle`）
        PaperStyle.defaultStyle(raw: defaultPaperStyleRaw, isMember: store.isMember).displayName
    }

    var body: some View {
        let theme = themeManager.current
        SettingsSubpage(title: "日记") {
            Section {
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
                .listRowBackground(themeManager.settingsCard)

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
                .listRowBackground(themeManager.settingsCard)
            }

            reminderSection(theme: theme)
        }
        .task { await refreshNotificationStatus() }
    }

    // MARK: - 提醒写日记

    private func reminderSection(theme: any AppTheme) -> some View {
        Section {
            HStack {
                SettingsRow(icon: "bell", title: "提醒写日记", theme: theme)
                Spacer()
                Toggle("", isOn: Binding(get: { reminderOn }, set: { setReminder($0) }))
                    .labelsHidden()
                    .tint(theme.accent)
            }
            .listRowBackground(themeManager.settingsCard)

            if reminderOn {
                DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                    SettingsRow(icon: "clock", title: "时间", theme: theme)
                }
                .environment(\.locale, appLocale)
                .tint(theme.accent)
                .listRowBackground(themeManager.settingsCard)

                VStack(alignment: .leading, spacing: 10) {
                    SettingsRow(icon: "repeat", title: "重复", theme: theme)
                    WeekdayPicker(selection: weekdaySelection, theme: theme)
                }
                .padding(.vertical, 4)
                .listRowBackground(themeManager.settingsCard)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if reminderOn && notificationsDenied {
                    HStack(spacing: 6) {
                        Text("通知没有打开，提醒发不出来。")
                            .foregroundStyle(theme.destructive)
                        Button("去设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .foregroundStyle(theme.accent)
                    }
                }
                if #available(iOS 26.0, *) {
                    Text("到点在锁屏和灵动岛上轻轻提醒一下；那天写过了就不打扰。")
                } else {
                    Text("到点发一条通知提醒一下；那天写过了就不打扰。")
                }
            }
            .font(theme.labelFont)
            .foregroundStyle(theme.textTertiary)
        }
    }

    /// 打开时先问通知权限（就在用户自己想要提醒的这一刻问，他知道为什么）；拒了也照样记下「开」，
    /// 底下提示去系统设置里打开
    private func setReminder(_ on: Bool) {
        reminderOn = on
        Task {
            if on { await LetterNotifications.requestAuthorizationIfNeeded() }
            await refreshNotificationStatus()
            await WritingReminder.reschedule(context: modelContext)
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderMinutes = (parts.hour ?? 21) * 60 + (parts.minute ?? 0)
            Task { await WritingReminder.reschedule(context: modelContext) }
        }
    }

    private var weekdaySelection: Binding<Set<Int>> {
        Binding {
            Set(reminderWeekdays.compactMap(\.wholeNumberValue))
        } set: { days in
            reminderWeekdays = days.sorted().map(String.init).joined()
            Task { await WritingReminder.reschedule(context: modelContext) }
        }
    }

    private func refreshNotificationStatus() async {
        notificationsDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}

/// 一周七天的小圆点，点一下选上 / 去掉。至少留一天 —— 一天都不选等于关了提醒，那该去关开关
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    let theme: any AppTheme

    /// 按这台手机的一周从哪天开始排；字（「日 一 二…」/「S M T…」）跟 App 选的语言
    private var days: [(weekday: Int, symbol: String, name: String)] {
        var calendar = Calendar.current
        calendar.locale = appLocale
        return (0..<7).map { i in
            let weekday = (Calendar.current.firstWeekday - 1 + i) % 7 + 1
            return (weekday, calendar.veryShortStandaloneWeekdaySymbols[weekday - 1], calendar.standaloneWeekdaySymbols[weekday - 1])
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.weekday) { day in
                let on = selection.contains(day.weekday)
                Button {
                    if on {
                        guard selection.count > 1 else { return }
                        selection.remove(day.weekday)
                    } else {
                        selection.insert(day.weekday)
                    }
                } label: {
                    Text(day.symbol)
                        .font(.system(size: 14, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? theme.background : theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background {
                            if on {
                                Circle().fill(theme.accent)
                            } else {
                                Circle().strokeBorder(theme.border, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(verbatim: day.name))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
