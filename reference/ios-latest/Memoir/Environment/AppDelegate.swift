import Combine   // @Published 需要；项目开了 MemberImportVisibility，不会从 SwiftUI 顺带拿到
import SwiftUI
import UIKit
import UserNotifications

/// 桥接回 UIKit 的 App 委托。SwiftUI 的 App 生命周期接不住下面两类系统回调：
///
/// 1. **桌面长按图标的快捷操作** —— 这里只负责把场景交给 `QuickActionSceneDelegate`，
///    具体见 `QuickActions.swift`
/// 2. **点击「回信到了」通知** —— 这里接住，挂在 `openLetterboxRequested` 上等界面来取
///
/// 遵守 `ObservableObject`：由 `@UIApplicationDelegateAdaptor` 创建的委托只要遵守它，
/// SwiftUI 就会自动放进环境（`@EnvironmentObject` 取用）。这是 CLAUDE.md
/// 「桥接 UIKit 可以用 ObservableObject」那条例外。
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {

    /// 用户点了回信通知、还没被界面处理掉。界面处理完要置回 false
    @Published var openLetterboxRequested = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 🔴 **必须在启动完成前设好**。晚了的话，冷启动（App 没开着、点通知才启动）
        // 那一次点击系统已经派发过了，会被直接丢掉
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }

    // MARK: - 通知

    /// App 开着时回信到了：照样弹横幅。不写这个的话，前台时系统默认什么都不显示
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// 用户点了通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = response.notification.request.content.userInfo[LetterNotifications.routeKey] as? String
        guard route == LetterNotifications.letterboxRoute else { return }
        await MainActor.run { openLetterboxRequested = true }
    }
}
