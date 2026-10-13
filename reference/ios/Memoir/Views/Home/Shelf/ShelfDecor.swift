import SwiftUI

// MARK: - 书架木板

/// 一层层的书架板。画在格子**后面**，位置由格子实际排出来的位置决定，
/// 而不是自己按行数算 —— 这样列数、间距、书的尺寸怎么改，板子都正好托在书底下。
///
/// 颜色全取自主题：板面用 `surfaceBackground`，前沿用 `border` → `borderAccent` 的渐变，
/// 深色主题（皮革）下自然变成深色木板，不用单独适配。
struct ShelfPlanks: View {
    /// 每一层书底的 y（与格子同一个坐标空间）
    let rowBottoms: [CGFloat]
    let theme: any AppTheme

    /// 板面厚度（书站在上面的那一面）与前沿高度
    private let topDepth: CGFloat = 7
    private let frontHeight: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            ForEach(rowBottoms, id: \.self) { bottom in
                plank
                    .frame(width: geo.size.width - 16, height: topDepth + frontHeight)
                    // 书底压在板面中间偏后：板面上沿比书底高一点，看起来是"站在板上"
                    .position(x: geo.size.width / 2, y: bottom - 2 + (topDepth + frontHeight) / 2)
            }
        }
        .allowsHitTesting(false)
    }

    private var isDark: Bool { theme.preferredColorScheme == .dark }

    private var plank: some View {
        VStack(spacing: 0) {
            // 板面：从后往前略微变亮，像光从前方打过来
            LinearGradient(
                colors: [theme.surfaceBackground.opacity(0.9), theme.surfaceBackground],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: topDepth)
            .overlay(alignment: .bottom) {
                // 板面与前沿交界的一道高光
                Rectangle()
                    .fill(Color.white.opacity(isDark ? 0.08 : 0.6))
                    .frame(height: 0.5)
            }

            LinearGradient(
                colors: [theme.border, theme.borderAccent],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: frontHeight)
        }
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
        .shadow(color: .black.opacity(isDark ? 0.4 : 0.14), radius: 7, x: 0, y: 6)
    }
}
