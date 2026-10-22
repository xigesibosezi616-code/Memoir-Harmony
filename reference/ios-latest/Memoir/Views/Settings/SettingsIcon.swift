import SwiftUI

/// 设置页一级分组的自绘图标。
///
/// **为什么不用 SF Symbol**：一级分组是这一页的骨架，用系统符号就长得和所有 App 一样。
/// 这套图形是照尺素自己的调性画的 —— 线性、单色、笔画收在同一个粗细上，
/// 和设置页原有的行图标放在一起不会打架。
///
/// **画法约定**：所有路径都画在 **24×24 的设计网格**上，再整体缩放到目标尺寸。
/// 加新图标时照这个网格画，不要写死像素值，否则换尺寸就散架。
enum SettingsIcon: String, CaseIterable, Identifiable {
    case appearance   // 外观：明暗对分的圆
    case journal      // 日记：带书签的本子
    case penPal       // 笔友：信封
    case location     // 位置与天气：定位针
    case language     // 语言：地球
    case data         // 数据与备份：云
    case stats        // 写作统计：三根柱
    case rate         // 去 App Store 评分：五角星
    case about        // 关于：i

    var id: String { rawValue }
}

struct SettingsIconView: View {
    let icon: SettingsIcon
    var size: CGFloat = 22
    var color: Color = .primary

    /// 线宽跟着尺寸缩放，否则图标变小时线会显得越来越粗
    private var lineWidth: CGFloat { size / 24 * 1.7 }

    var body: some View {
        ZStack {
            if icon == .appearance {
                // 半边实心：唯一一个带填充的图标，用来表达「明与暗」
                SettingsIconFill().fill(color)
            }
            SettingsIconStroke(icon: icon)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 设计网格

/// 把 24×24 设计网格上的坐标映射到实际绘制区域
private func g(_ r: CGRect, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: r.minX + r.width * x / 24, y: r.minY + r.height * y / 24)
}
/// 把设计网格上的长度映射到实际尺寸
private func gs(_ r: CGRect, _ v: CGFloat) -> CGFloat { r.width * v / 24 }

private func gRect(_ r: CGRect, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(origin: g(r, x, y), size: CGSize(width: gs(r, w), height: gs(r, h)))
}

// MARK: - 描边路径

/// 单一 Shape 内部按 icon 分发。
///
/// **不能写成「`@ViewBuilder var shape: some Shape` + switch 返回不同类型」** ——
/// `@ViewBuilder` 构建的是 View 不是 Shape，而 `some Shape` 要求所有分支是同一个具体类型。
private struct SettingsIconStroke: Shape {
    let icon: SettingsIcon

    func path(in r: CGRect) -> Path {
        var p = Path()
        switch icon {

        case .appearance:
            p.addEllipse(in: gRect(r, 3, 3, 18, 18))

        case .journal:
            // 本子 + 书脊 + 一条书签（呼应 App 图标里那根丝带）
            p.addRoundedRect(in: gRect(r, 5, 3, 14, 18),
                             cornerSize: CGSize(width: gs(r, 2.5), height: gs(r, 2.5)))
            p.move(to: g(r, 8.5, 3)); p.addLine(to: g(r, 8.5, 21))
            p.move(to: g(r, 14.5, 3))
            p.addLine(to: g(r, 14.5, 13))
            p.addLine(to: g(r, 15.9, 11.6))
            p.addLine(to: g(r, 15.9, 3))

        case .penPal:
            // 信封
            p.addRoundedRect(in: gRect(r, 3, 5.5, 18, 13),
                             cornerSize: CGSize(width: gs(r, 2), height: gs(r, 2)))
            p.move(to: g(r, 4.2, 7))
            p.addLine(to: g(r, 12, 13.4))
            p.addLine(to: g(r, 19.8, 7))

        case .location:
            // 定位针（水滴）。
            // ⚠️ SwiftUI 的 y 轴朝下，角度按「0°=右、90°=下、270°=上」算，
            // 而 `clockwise` 说的是**视觉**方向，两者一叠加极易画反 ——
            // 稳妥写法是让角度**单调递增**并配 `clockwise: false`：
            // 145°(左下) → 180°(左) → 270°(上) → 360° → 395°(=35°，右下)，
            // 正好是绕过顶部的那段大弧，底部留口收到针尖。
            p.addArc(center: g(r, 12, 9.8), radius: gs(r, 6.4),
                     startAngle: .degrees(145), endAngle: .degrees(395), clockwise: false)
            p.addLine(to: g(r, 12, 21))
            p.closeSubpath()
            p.addEllipse(in: gRect(r, 9.6, 7.4, 4.8, 4.8))

        case .language:
            // 地球：外圈 + 经线（窄椭圆）+ 纬线
            p.addEllipse(in: gRect(r, 3, 3, 18, 18))
            p.addEllipse(in: gRect(r, 8.2, 3, 7.6, 18))
            p.move(to: g(r, 3.6, 12)); p.addLine(to: g(r, 20.4, 12))

        case .data:
            // 云 —— 三瓣外轮廓 + 平底。
            // 同样靠「角度单调递增 + clockwise: false」保证方向，见上面 .location 的说明。
            p.move(to: g(r, 6, 17.5))
            p.addArc(center: g(r, 8.8, 14.2), radius: gs(r, 3.3),
                     startAngle: .degrees(90), endAngle: .degrees(215), clockwise: false)
            p.addArc(center: g(r, 12.4, 11.2), radius: gs(r, 4.4),
                     startAngle: .degrees(200), endAngle: .degrees(330), clockwise: false)
            p.addArc(center: g(r, 16.4, 14.4), radius: gs(r, 3.1),
                     startAngle: .degrees(305), endAngle: .degrees(90), clockwise: false)
            p.closeSubpath()

        case .stats:
            // 三根高低不同的柱
            p.move(to: g(r, 7, 19));  p.addLine(to: g(r, 7, 13.5))
            p.move(to: g(r, 12, 19)); p.addLine(to: g(r, 12, 7.5))
            p.move(to: g(r, 17, 19)); p.addLine(to: g(r, 17, 11))

        case .rate:
            // 五角星：外圈 / 内圈各 5 个点交替连线。圆角由 lineJoin(.round) 负责
            let c = g(r, 12, 12.8)
            for i in 0..<10 {
                let radius = gs(r, i.isMultiple(of: 2) ? 9.4 : 4.0)
                let angle = (-90 + Double(i) * 36) * .pi / 180
                let pt = CGPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()

        case .about:
            p.addEllipse(in: gRect(r, 3, 3, 18, 18))
            p.move(to: g(r, 12, 11)); p.addLine(to: g(r, 12, 16.6))
            // 点：一段几乎为零长的线，靠 round cap 变成圆点
            p.move(to: g(r, 12, 7.7)); p.addLine(to: g(r, 12, 7.75))
        }
        return p
    }
}

// MARK: - 填充路径（只有「外观」用得上）

private struct SettingsIconFill: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // 左半圆：正上顺时针扫到正下，再直线收口
        p.move(to: g(r, 12, 3))
        p.addArc(center: g(r, 12, 12), radius: gs(r, 9),
                 startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        p.closeSubpath()
        return p
    }
}
