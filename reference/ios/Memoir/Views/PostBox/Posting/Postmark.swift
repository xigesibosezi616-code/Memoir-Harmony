import SwiftUI

/// 一枚邮戳（日戳）：两道圆圈，中间一条横带压着寄出日期，上沿一圈是寄出的地点。
///
/// 地点取自这封信里日记记下的地方（见 `Postmark.place(from:)`），没有地点的只盖日期。
/// 油墨颜色跟着主题的邮筒走：素笺朱红、肯特灰蓝、皮革浅棕（深色底上看得清）
struct Postmark: View {
    let date: Date
    let place: String?
    let ink: Color
    var size: CGFloat = 84

    var body: some View {
        let r = size / 2
        let line = max(1, size * 0.02)
        ZStack {
            Circle().stroke(ink, lineWidth: line)
            Circle().stroke(ink, lineWidth: line * 0.6).padding(size * 0.07)

            // 中间的横带：上下两道线，夹着日期
            VStack(spacing: size * 0.2) {
                Rectangle().fill(ink).frame(height: line * 0.7)
                Rectangle().fill(ink).frame(height: line * 0.7)
            }
            .frame(width: size * 0.86)
            Text(verbatim: Self.dateText(date))
                .font(.system(size: size * 0.125, weight: .semibold, design: .monospaced))
                .tracking(-size * 0.004)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: size * 0.78)

            if let place, !place.isEmpty {
                ArcText(text: place, radius: r * 0.64, fontSize: size * 0.12, color: ink, top: true)
            }
            // 下沿一颗小星，邮戳都有个记号
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.08))
                .foregroundStyle(ink)
                .offset(y: r * 0.6)
        }
        .frame(width: size, height: size)
        // 盖歪一点，油墨不那么实
        .rotationEffect(.degrees(-9))
        .opacity(0.82)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [place, date.shortDate].compactMap { $0 }.joined(separator: " ")))
    }

    /// 2026.10.11 —— 邮戳上的日期各国写法差不多，统一用这种
    static func dateText(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d.%02d.%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 邮戳上写哪个地方：这封信里最近一篇记了地点的日记。
    ///
    /// 地名是按定位精度拼的（`WeatherManager.placeName`），区级是「城市 区」、街道级可能是地标名；
    /// 邮戳上只写第一段（城市或地标），太长的截短
    static func place(from locations: [String?]) -> String? {
        guard let raw = locations.lazy.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else { return nil }
        let first = raw.split(separator: " ").first.map(String.init) ?? raw
        let isWide = first.unicodeScalars.contains { $0.value >= 0x2E80 }
        let limit = isWide ? 8 : 16
        return first.count > limit ? String(first.prefix(limit)) : first
    }

    /// 邮戳的油墨色
    static func ink(themeID: String) -> Color {
        switch themeID {
        case "leather": return Color(hex: "#C8A87C")
        case "kent": return Color(hex: "#5F7896")
        default: return Color(hex: "#B5473A")
        }
    }
}

/// 沿圆弧排的一行字（邮戳上沿的地名）。逐字摆放，中日韩按方块字宽、拉丁字母按窄字宽估算
private struct ArcText: View {
    let text: String
    let radius: CGFloat
    let fontSize: CGFloat
    let color: Color
    let top: Bool

    var body: some View {
        let chars = Array(text)
        let advances = chars.map { c -> CGFloat in
            c.unicodeScalars.contains { $0.value >= 0x2E80 } ? fontSize * 1.05 : fontSize * 0.62
        }
        let total = advances.reduce(0, +)
        ZStack {
            ForEach(Array(chars.enumerated()), id: \.offset) { i, c in
                // 这个字中心离整行起点多远 → 对应的圆心角（弧度）
                let before = advances[..<i].reduce(0, +) + advances[i] / 2
                let angle = Double((before - total / 2) / radius)
                Text(String(c))
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(color)
                    .offset(y: top ? -radius : radius)
                    .rotationEffect(.radians(top ? angle : -angle))
            }
        }
    }
}
