import ActivityKit
import Foundation
import SwiftData
import UserNotifications

/// 提醒写日记（2026-11-07 用户定，公测前三件之一，方案见 `Docs/BETA_FEATURES.md` ①）。
///
/// **全在本机排，不走服务器**：
/// - iOS 26 起：下一次提醒排成**定时实况**（`Activity.request(…start:)`），到点系统自己在锁屏和灵动岛拉起、响一声
///   （长什么样在扩展的 `WritingReminderLiveActivity`）；再往后的几天排普通通知兜底 —— 用户几天不开 App 也照样有提醒。
///   系统能让一个 App 提前排几个实况没写明，先只排最近的一个
/// - iOS 18–25：全是普通通知
/// - **当天写过就不提醒**：回到前台、改了设置、写完一篇都重排一遍，重排时跳过「今天已经写过」。
///   写完一篇时已经在锁屏上的实况马上收起、通知中心里的提醒也收掉
/// - 过了午夜还没收起的实况算过期（`staleDate`），扩展把它淡下去；系统最长 8 小时自己收
/// - 默认关；用户在设置 → 日记里打开时才问通知权限
///
/// 🔴 实况到点拉起时 App 不在运行，那句话、按钮上的字在**排的时候**就按 App 选的语言翻好放进去
enum WritingReminder {
    // MARK: 设置（`@AppStorage` 用同名 key）

    static let enabledKey = "writingReminderEnabled"
    /// 一天里的第几分钟
    static let minutesKey = "writingReminderMinutes"
    /// 哪几天提醒：`Calendar` 的 weekday（1 = 周日 … 7 = 周六）连成的字符串
    static let weekdaysKey = "writingReminderWeekdays"
    static let defaultMinutes = 21 * 60
    static let defaultWeekdays = "1234567"

    /// 点通知去写日记：`userInfo[LetterNotifications.routeKey]` 的值
    static let composeRoute = "compose"

    private static let notificationPrefix = "writing-reminder-"
    /// 普通通知往后排几天
    private static let daysAhead = 14

    /// 上一次重排。几处同时触发（回到前台、写完一篇）时排队一个个来，免得两边各排出一个实况
    private static var pending: Task<Void, Never>?

    /// 按现在的设置重排。回到前台、改了设置、换了主题 / 语言、写完一篇都调
    static func reschedule(context: ModelContext) async {
        let previous = pending
        let task = Task {
            await previous?.value
            await rescheduleNow(context: context)
        }
        pending = task
        await task.value
    }

    private static func rescheduleNow(context: ModelContext) async {
        let settings = Settings.current
        let writtenToday = hasEntryToday(context: context)
        let center = UNUserNotificationCenter.current()

        // 1. 收掉旧的：还没到点的实况、排着的通知全部重来；已经在锁屏上的，今天写过了或关了提醒才收
        for activity in Activity<WritingReminderAttributes>.activities {
            let showing = activity.activityState == .active && (activity.content.staleDate ?? .distantFuture) > .now
            if showing && settings.enabled && !writtenToday { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(notificationPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        if writtenToday || !settings.enabled {
            let shown = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(notificationPrefix) }
            center.removeDeliveredNotifications(withIdentifiers: shown)
        }
        guard settings.enabled, !settings.weekdays.isEmpty else {
            NSLog("[WritingReminder] 提醒关着，没排")
            return
        }

        // 2. 排新的
        var dates = upcoming(from: .now, minutes: settings.minutes, weekdays: settings.weekdays, skipToday: writtenToday)
        // 真机上「怎么没响」多半是这一句：当天写过就跳过今天（2026-11-07 就是凌晨写了一篇，白天怎么设都不响）
        NSLog("[WritingReminder] 重排：今天写过=%d，下一次 %@，通知权限 %d", writtenToday ? 1 : 0,
              String(describing: dates.first), await center.notificationSettings().authorizationStatus.rawValue)
        guard !dates.isEmpty else { return }
        if #available(iOS 26.0, *), scheduleLiveActivity(at: dates[0]) {
            dates.removeFirst()
        }
        for date in dates {
            await scheduleNotification(at: date)
        }
    }

    /// 设置页那三项（`@AppStorage` 用同名 key）
    private struct Settings {
        let enabled: Bool
        let minutes: Int
        let weekdays: Set<Int>

        static var current: Settings {
            let defaults = UserDefaults.standard
            return Settings(
                enabled: defaults.bool(forKey: enabledKey),
                minutes: defaults.object(forKey: minutesKey) as? Int ?? defaultMinutes,
                weekdays: Set((defaults.string(forKey: weekdaysKey) ?? defaultWeekdays).compactMap(\.wholeNumberValue)))
        }
    }

    // MARK: - 下一次（设置页显示）

    struct NextReminder {
        let date: Date
        /// 今天本来该提醒、因为今天已经写过才跳过的
        let skippedToday: Bool
    }

    /// 下一次提醒在什么时候。设置页提醒那一组下面显示，**不然「今天写过就不提醒」看起来就是坏了**
    /// （2026-11-07 真机：凌晨写了一篇，白天把时间设到几分钟后，实况和通知都不出）。关着提醒返回 nil
    static func next(context: ModelContext, now: Date = .now) -> NextReminder? {
        let settings = Settings.current
        guard settings.enabled, !settings.weekdays.isEmpty else { return nil }
        let writtenToday = hasEntryToday(context: context)
        guard let date = upcoming(from: now, minutes: settings.minutes, weekdays: settings.weekdays, skipToday: writtenToday).first
        else { return nil }
        let todayWouldRing = writtenToday
            && upcoming(from: now, minutes: settings.minutes, weekdays: settings.weekdays, skipToday: false)
                .first.map { Calendar.current.isDate($0, inSameDayAs: now) } == true
        return NextReminder(date: date, skippedToday: todayWouldRing)
    }

    // MARK: - 什么时候

    /// 接下来 `daysAhead` 天里该提醒的时刻（已经过了的不算）
    static func upcoming(from now: Date, minutes: Int, weekdays: Set<Int>, skipToday: Bool,
                         calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<daysAhead).compactMap { offset -> Date? in
            if offset == 0 && skipToday { return nil }
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let at = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  at > now else { return nil }
            return at
        }
    }

    /// 今天写过没有（按写下的时刻算，另一台设备同步过来的也算）
    private static func hasEntryToday(context: ModelContext) -> Bool {
        let start = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return false }
        var descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.createdAt >= start && $0.createdAt < end })
        descriptor.fetchLimit = 1
        do {
            return try context.fetchCount(descriptor) > 0
        } catch {
            NSLog("[WritingReminder] 查今天写没写失败: %@", String(describing: error))
            return false
        }
    }

    // MARK: - 说什么

    /// 轮换的那一句，按日子轮（同一天不管重排几次都是同一句）。不催、不提连续天数
    private static func line(for date: Date) -> String {
        let lines = [
            NSLocalizedString("今天的那页还空着。", bundle: .appLanguage, comment: "提醒写日记：锁屏实况 / 通知里的一句话"),
            NSLocalizedString("笔在桌上，纸也铺好了。", bundle: .appLanguage, comment: "提醒写日记：锁屏实况 / 通知里的一句话"),
            NSLocalizedString("今天过得怎么样？写两句也好。", bundle: .appLanguage, comment: "提醒写日记：锁屏实况 / 通知里的一句话"),
            NSLocalizedString("趁今天还没过完，留一页给它。", bundle: .appLanguage, comment: "提醒写日记：锁屏实况 / 通知里的一句话"),
            NSLocalizedString("有什么想记下来的吗？", bundle: .appLanguage, comment: "提醒写日记：锁屏实况 / 通知里的一句话"),
            NSLocalizedString("停一下，给今天写几行。", bundle: .appLanguage, comment: "提醒写日记：锁屏实况 / 通知里的一句话"),
        ]
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return lines[day % lines.count]
    }

    private static var appName: String {
        NSLocalizedString("尺素", bundle: .appLanguage, comment: "App 名")
    }

    // MARK: - 怎么提醒

    /// 排一个到点拉起的实况。排不上（用户关了实况、系统拒了）返回 false，这一次改用普通通知
    @available(iOS 26.0, *)
    private static func scheduleLiveActivity(at date: Date) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            NSLog("[WritingReminder] 实况被关了，改用通知")
            return false
        }
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))
        let line = line(for: date)
        let state = WritingReminderAttributes.ContentState(
            line: line,
            action: NSLocalizedString("记录一下", bundle: .appLanguage, comment: "提醒写日记：锁屏实况上的按钮，点了去写日记"))
        // 到点亮屏那一下的标题和正文。字已经翻好了 —— 指一张不存在的表，系统查不到就原样显示，
        // 不然它会拿中文原文当 key 去按**系统**语言重新翻一遍，和用户在 App 里选的语言对不上
        let alert = AlertConfiguration(
            title: LocalizedStringResource(String.LocalizationValue(appName), table: "Verbatim"),
            body: LocalizedStringResource(String.LocalizationValue(line), table: "Verbatim"),
            sound: .default)
        do {
            let activity = try Activity.request(
                attributes: WritingReminderAttributes(themeID: UserDefaults.standard.string(forKey: "selectedTheme") ?? "bamboo"),
                content: ActivityContent(state: state, staleDate: midnight),
                pushType: nil,
                style: .standard,
                alertConfiguration: alert,
                start: date)
            NSLog("[WritingReminder] 排好实况 %@，到点 %@", activity.id, String(describing: date))
            return true
        } catch {
            NSLog("[WritingReminder] 排实况失败，改用通知: %@", String(describing: error))
            return false
        }
    }

    private static func scheduleNotification(at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = appName
        content.body = line(for: date)
        content.sound = .default
        content.threadIdentifier = "writing-reminder"
        content.userInfo = [LetterNotifications.routeKey: composeRoute]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let id = notificationPrefix + String(Int(date.timeIntervalSince1970))
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            NSLog("[WritingReminder] 排通知失败: %@", String(describing: error))
        }
    }
}
