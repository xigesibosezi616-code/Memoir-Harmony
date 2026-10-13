import SwiftUI

/// 会员款上的小标记：一枚小火漆印。只给**还不是会员**的人看 —— 会员看到满屏的标记没有意义
struct MemberBadge: View {
    var size: CGFloat = 18

    var body: some View {
        WaxSeal(size: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("尺素会员"))
    }
}

extension View {
    /// 统一用全屏弹出付费页（`PaywallView`）
    func paywallCover(isPresented: Binding<Bool>) -> some View {
        fullScreenCover(isPresented: isPresented) {
            PaywallView()
        }
    }
}
