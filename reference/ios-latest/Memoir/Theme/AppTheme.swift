import SwiftUI

protocol AppTheme: Sendable {
    // Backgrounds
    var background: Color { get }
    var cardBackground: Color { get }
    var surfaceBackground: Color { get }
    var sidebarBackground: Color { get }

    // Text
    var textPrimary: Color { get }
    var textSecondary: Color { get }
    var textTertiary: Color { get }

    // Borders
    var border: Color { get }
    var borderAccent: Color { get }

    // Accent
    var accent: Color { get }
    var accentBackground: Color { get }

    // Mood
    var moodBackground: Color { get }
    var moodBorder: Color { get }
    var moodText: Color { get }

    // Destructive
    var destructive: Color { get }

    // 明暗
    /// 这个主题要求 App 整体用哪种系统明暗。**`nil` = 不指定，跟随系统**（和纸、北欧都是 nil，保持原样）。
    ///
    /// 深色主题必须设 `.dark`。App 没有强制浅色，但绝大多数用户手机是浅色模式，于是：
    /// - 底栏、导航按钮、提示框、菜单、弹窗这些**系统玻璃按浅色渲染** —— 压在深色页面上一块发白
    /// - 状态栏是深色字，时间和电量在深色页面上几乎看不见
    /// - 🔴 用户开了「**降低透明度**」时最严重：玻璃全退化成**浅色实心块**
    ///   （2026-09-15 皮革主题真机截图的底栏就是这个，iOS 27 模拟器打开该设置后复现）
    ///
    /// 逐个表面去补 `toolbarColorScheme` 补不全（底栏在降低透明度下补了也不生效），
    /// 所以在 App 根部统一用 `.preferredColorScheme` 处理，见 `MemoirApp`。
    var preferredColorScheme: ColorScheme? { get }

    // 插画
    /// 邮筒页的邮筒图（Assets 里的 imageset 名）。
    ///
    /// **写成协议要求而不是查表**：每个主题都必须配一个邮筒（2026-09-14 产品决策），
    /// 新增主题时漏配的话，这里直接编译报错，不会上线后才发现邮筒页是空的。
    /// 图的底色不用对齐主题背景 —— 邮筒页运行时会取图片边角的像素当页面底色。
    var mailboxImageName: String { get }

    // Typography
    var titleFont: Font { get }
    var headingFont: Font { get }
    var bodyFont: Font { get }
    var bodyLineSpacing: CGFloat { get }
    var captionFont: Font { get }
    var labelFont: Font { get }
    var letterSpacingWide: CGFloat { get }
}
