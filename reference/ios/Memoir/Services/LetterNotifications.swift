import Foundation
import UserNotifications

/// 回信到达的本地通知。
///
/// **不需要服务器推送**：回信在寄出那一刻就写好了、到达时刻也已算好（见 `LetterDelivery`），
/// 直接在本机预约一条定时通知即可。
///
/// 🔴 **未授权时预约的通知会被系统静默丢弃**（调用不报错）。所以寄信时必须先申请权限再预约，
/// 另外 App 每次回到前台都会用 `rescheduleInTransit` 补排一遍。
enum LetterNotifications {

    /// 点通知后要去的地方，写在 `userInfo` 里给 `AppDelegate` 读
    static let routeKey = "route"
    static let letterboxRoute = "letterbox"

    /// 申请通知权限。**只在用户第一次寄信成功之后调** —— 那是他最能理解「为什么要通知」的时刻。
    /// 已经问过的（无论同意与否）系统不会再弹，直接返回当前结果。
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// 在路上的一封信，传给 `rescheduleInTransit` 的值快照（SwiftData 模型不能跨并发边界传）
    struct InTransit: Sendable {
        let id: UUID
        let arrivesAt: Date
        let penPalName: String
    }

    /// 把所有在路上的信的到达通知重新排一遍。App 每次回到前台时调。
    ///
    /// 同一封信用同一个标识，重排是**覆盖**，不会重复弹。兜住这几种情况：
    /// - 用户第一次寄信时拒了通知，后来在系统设置里打开了
    /// - 权限弹窗还没点，App 就被杀掉了
    /// - 信是从**另一台设备**经 iCloud 同步过来的 —— 那台设备不会替这台排通知
    /// - 用户切换了 App 语言 —— 顺带把通知文案换成新语言
    ///
    /// **只在已授权时排，不在这里弹权限申请**：启动时突然要权限，用户不知道为什么
    static func rescheduleInTransit(_ letters: [InTransit]) async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        for l in letters where l.arrivesAt > .now {
            await scheduleArrival(letterID: l.id, arrivesAt: l.arrivesAt, penPalName: l.penPalName)
        }
    }

    /// 为一封在路上的信预约「到达」通知。
    ///
    /// - Parameters:
    ///   - penPalName: 写进通知正文。**预约时就取好**：这是当时的笔友名快照
    static func scheduleArrival(letterID: UUID, arrivesAt: Date, penPalName: String) async {
        let content = UNMutableNotificationContent()
        // 标题 / 正文在**预约这一刻**按 App 语言取好。之后用户切换语言，
        // 已经预约的通知不会跟着变 —— 系统存的是字符串，不是 key
        content.title = NSLocalizedString("你有一封新的回信", bundle: .appLanguage, comment: "回信到达通知标题")
        content.body = String(
            format: NSLocalizedString("%@的回信到了，去信箱看看吧", bundle: .appLanguage, comment: "回信到达通知正文，%@ 是笔友名"),
            penPalName
        )
        content.sound = .default
        content.userInfo = [routeKey: letterboxRoute]

        // 系统要求时间间隔 > 0；到达时刻已过（比如开了加速、写信又很慢）就 1 秒后弹
        let interval = max(1, arrivesAt.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: "letter-arrival-\(letterID.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // 预约失败不影响信本身 —— 信照样会按时出现在信箱里，只是没有提醒。
            // 打完整 error，别只打 localizedDescription（CLAUDE.md 调试方法）
            let ns = error as NSError
            NSLog("🔴[LetterNotifications] 预约失败 domain=%@ code=%ld error=%@",
                  ns.domain, ns.code, String(describing: error))
        }
    }
}
