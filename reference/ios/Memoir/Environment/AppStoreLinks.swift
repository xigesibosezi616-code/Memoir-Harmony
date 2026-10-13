import Foundation

/// App Store 相关链接。
enum AppStoreLinks {
    /// App Store Connect 里的 **Apple ID**（纯数字，在「App 信息 → 通用信息」里）。
    ///
    /// ✅ 2026-09-27 由用户从 App Store Connect 提供，已填。
    ///
    /// 空着时的行为（留作参考）：Debug 包照样显示「给我们评分」、点了弹系统评分框；
    /// Release 包直接隐藏这一行 —— 不能带着一个点了没反应的按钮上架。
    ///
    /// ⚠️ App 正式上架之前，就算填了 ID，链接打开也是「此 App 目前不可用」—— 这是正常的
    static let appID: String? = "6796680063"

    /// 直达「撰写评论」页。
    ///
    /// **为什么不用系统的 `requestReview`**：那个评分框由系统决定弹不弹（每年最多 3 次），
    /// 挂在按钮上经常点了什么都不出现，Apple 的设计规范也明确说不要把它绑在按钮上。
    /// 用户主动点「去评分」，就该稳稳地跳过去。
    static var writeReviewURL: URL? {
        guard let appID, !appID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")
    }
}
