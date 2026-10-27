import SwiftData
import SwiftUI

/// 底栏是系统画的，量不到每一格图标的位置：按 iPhone 上实测的比例估（2026-10-27，iOS 26.4 / 27 模拟器量过）。
/// 新手指引指 tab（`GuideTabHint`）和邮筒上的小红点共用这一份
enum TabBarLayout {
    /// 四格的中心占屏宽的比例：只有四格时胶囊铺满一行；右边有搜索圆时胶囊变窄
    static func centers(showsSearch: Bool) -> [CGFloat] {
        showsSearch ? [0.157, 0.326, 0.497, 0.669] : [0.181, 0.388, 0.604, 0.813]
    }
    /// 图标中心离屏幕底边多高（点）
    static let iconFromBottom: CGFloat = 57
}

/// 邮筒 tab 上「有到了还没读的信」的小红点（2026-10-27 用户定：像「信箱」那颗一样克制的小点，
/// 不用系统的 badge —— 系统的是一枚和数字一样大的红圆，空字的也一样大）。
///
/// - 叠在底栏上方，估在信封图标的右上角；不接点按
/// - 在路上的信到点了要自己亮：每 15 秒看一次
/// - 搜索打开时底栏会收起来，外面传 `visible = false`
struct PostBoxUnreadDot: View {
    let showsSearch: Bool
    let color: Color
    var visible = true

    @Query private var letters: [Letter]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if visible, letters.contains(where: { LetterDelivery.isUnread($0, now: context.date) }) {
                GeometryReader { proxy in
                    let x = proxy.size.width * TabBarLayout.centers(showsSearch: showsSearch)[2]
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .position(x: x + 14, y: proxy.size.height - TabBarLayout.iconFromBottom - 12)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
