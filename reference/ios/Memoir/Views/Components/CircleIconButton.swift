import SwiftUI

/// 圆形图标按钮的两种分量 —— 与 iOS 26 起的系统按钮一一对应
/// （系统「日记」App 用的就是这两种：右下角实心的加号、左上角半透明的返回）。
enum CircleButtonProminence {
    /// 实心：页面的主行动（首页的加号）
    case prominent
    /// 半透明玻璃：次级操作（返回、完成）
    case glass
}

/// 导航栏 / 浮层上的圆形图标按钮。
///
/// 🔴 **不要再自己画圆底。** iOS 26 起系统会给工具栏按钮自动套一层玻璃，
/// 我们再画一个 `.background(theme.accent, in: Circle())` 会被它盖在下面 ——
/// 结果三套主题下都糊成一个看不清的浅色圆（2026-09-22 真机反馈，
/// 首页加号、写日记页的返回与完成全中招）。
///
/// 这里统一走系统的 `.glass` / `.glassProminent`：外观、明暗适配、按压反馈
/// 都交给系统，和原生 App 一致。**低于 iOS 26 时**才退回自绘的圆底。
struct CircleIconButton: View {
    let systemName: String
    let prominence: CircleButtonProminence
    let theme: any AppTheme
    /// 图标字号。系统样式下只影响字形，圆底由系统按内容撑开
    var size: CGFloat = 15
    var action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            switch prominence {
            case .prominent:
                // 实心：底色取主题强调色，字形颜色由系统按对比度自动定
                Button(action: action) { glyph }
                    .buttonStyle(.glassProminent)
                    .tint(theme.accent)
            case .glass:
                Button(action: action) { glyph.foregroundStyle(theme.textSecondary) }
                    .buttonStyle(.glass)
            }
        } else {
            legacy
        }
    }

    private var glyph: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
    }

    /// iOS 18–25 的退路：保持改造前的样子
    private var legacy: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(prominence == .prominent ? theme.cardBackground : theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(prominence == .prominent ? theme.accent : theme.cardBackground, in: Circle())
        }
    }
}
