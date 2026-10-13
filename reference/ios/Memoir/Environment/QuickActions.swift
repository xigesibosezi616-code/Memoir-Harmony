import Combine   // @Published 需要；项目开了 MemberImportVisibility，不会从 SwiftUI 顺带拿到
import SwiftUI
import UIKit

/// 桌面长按 App 图标弹出的快捷操作。
///
/// 目前只有一项「应用图标」：点了直接打开 App、进到换图标那一页（2026-09-14）。
enum QuickAction: String {
    case appIcon = "com.sinaratech.memoir.quickaction.appIcon"

    init?(_ item: UIApplicationShortcutItem) {
        self.init(rawValue: item.type)
    }

    /// 把快捷操作登记给系统。
    ///
    /// 🔴 **用代码动态登记，不写进 Info.plist 的 `UIApplicationShortcutItems`。**
    /// 静态那种的标题只能按**系统**语言翻译；而尺素的语言是用户在 App 里自己选的，
    /// 两者可以不一样（系统繁体、App 里选了简体）。只有代码登记时用
    /// `Bundle.appLanguage` 取译文，标题才跟得上 App 的语言。
    ///
    /// 代价：装完之后要**先打开一次** App，长按才会出现这一项。
    /// **切换语言后必须重新调用一次**，否则长按菜单还是旧语言。
    @MainActor
    static func registerShortcutItems() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: QuickAction.appIcon.rawValue,
                localizedTitle: NSLocalizedString("应用图标", bundle: .appLanguage, comment: "桌面长按图标的快捷操作"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "app.badge"),
                userInfo: nil
            )
        ]
    }
}

// MARK: - 系统回调的桥接

// App 委托在 `AppDelegate.swift`，它负责把场景交给下面这个类。

/// 接住快捷操作，挂在 `pendingAction` 上等界面来取。
///
/// 🔴 **两条系统回调都必须接，只接一条就会「有时点了没反应」：**
/// - **冷启动**（App 没在后台，点了才启动）→ 系统把快捷操作塞在
///   `scene(_:willConnectTo:options:)` 的 `connectionOptions.shortcutItem` 里
/// - **热启动**（App 在后台被唤起）→ 走 `windowScene(_:performActionFor:completionHandler:)`
///
/// 用 `ObservableObject` 而不是 `@Observable`：这个对象是 **UIKit 创建的**，
/// 不经过 SwiftUI 的手。只有遵守 `ObservableObject`，SwiftUI 才会把它自动放进
/// 界面的环境里（`@EnvironmentObject` 取用）—— 这正是 CLAUDE.md 里
/// 「桥接 UIKit 可以用 ObservableObject」那条例外。
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    /// 还没被界面处理掉的快捷操作。界面处理完要置回 nil。
    @Published var pendingAction: QuickAction?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let item = connectionOptions.shortcutItem {
            pendingAction = QuickAction(item)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let action = QuickAction(shortcutItem)
        pendingAction = action
        completionHandler(action != nil)
    }
}
