import SwiftUI

/// 手记页的展示方式。
///
/// 两种模式服务不同目的，不是简单的视觉偏好：
/// - `list` 用来**找**某一篇（信息密度高，一屏多条）
/// - `showcase` 用来**重看**一篇（照片放大、留白，像翻唱片）
///
/// 2026-10-22 起新用户默认大屏，列表是可选项（设置里大屏排前面）。手动选过的照旧记着
enum HomeDisplayMode: String, CaseIterable {
    case showcase
    case list

    static let storageKey = "homeDisplayMode"
    /// 没选过时用哪种（`@AppStorage` 的默认值都用它，别各写各的）
    static let defaultMode: HomeDisplayMode = .showcase

    /// 🔴 返回 `LocalizedStringKey` 而**不是** `String`。
    ///
    /// 两者都能翻译，差别在**响应性**：`Text(String)` 拿到的是一个已经算好的值，
    /// 用户在设置里切换语言时它不会自己变（`NSLocalizedString` 是调用那一刻读一次）；
    /// `Text(LocalizedStringKey)` 由 SwiftUI 在渲染时按环境里的 `\.locale` 查表，
    /// **语言一变当场跟着变**。
    ///
    /// 常驻在界面上的文案一律用这个；只有必须交给非 `Text` 调用方的（`LocalizedError`
    /// 的 `errorDescription` 那类一次性消息）才退回 `String` + `NSLocalizedString`。
    var displayName: LocalizedStringKey {
        switch self {
        case .list:     return "列表"
        case .showcase: return "大屏"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .list:     return "一屏多条，便于翻找"
        case .showcase: return "一屏一篇，左右滑动，照片大图展示"
        }
    }

    var iconName: String {
        switch self {
        case .list:     return "list.bullet"
        case .showcase: return "rectangle.on.rectangle"
        }
    }
}
