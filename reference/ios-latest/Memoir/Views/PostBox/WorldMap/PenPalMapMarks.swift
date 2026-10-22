import SwiftUI

/// 地图上的墨色：**跟着地图的白天黑夜走，不跟主题**（`MapDaylight`）。
/// 夜里的地图是深色，墨点、名字、航线就得是浅的才看得见；白天反过来。
/// 收件人用的邮戳色跟主题（素笺朱红、皮革赭黄、肯特灰蓝），夜里调亮一点
struct MapInk {
    /// 笔友的墨点、「你」
    let dot: Color
    /// 墨点外面那一圈
    let ring: Color
    /// 名字标签的底
    let tagPaper: Color
    /// 正在看、还没选的那一条航线
    let route: Color
    /// 收件人：墨点、航线、在路上的信
    let post: Color

    static func of(night: Bool, postInk: Color) -> MapInk {
        let dark = Color(hex: "#2B241E")
        let light = Color(hex: "#F6F1E6")
        return night
            ? MapInk(dot: light, ring: dark, tagPaper: dark.opacity(0.85), route: light.opacity(0.5),
                     post: postInk.mix(with: .white, by: 0.35))
            : MapInk(dot: dark, ring: light, tagPaper: light.opacity(0.92), route: dark.opacity(0.35),
                     post: postInk)
    }
}

/// 地图上的一位笔友：一个墨点，外面一圈对比色（像参考图那样压在地图上）。
///
/// - 平常：小墨点
/// - 在收件人里：换成邮戳色，大一点
/// - 正在看的那位（名片翻到他）：再大一点，下面写着姓
struct PenPalDot: View {
    let ink: MapInk
    let isRecipient: Bool
    let isFocused: Bool
    let name: String

    private var size: CGFloat { isFocused ? 16 : (isRecipient ? 13 : 10) }

    var body: some View {
        Circle()
            .fill(isRecipient ? ink.post : ink.dot)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(ink.ring, lineWidth: isFocused ? 2.5 : 2))
            .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 0.5)
            .overlay(alignment: .top) {
                if isFocused {
                    MapNameTag(text: Text(verbatim: name), ink: ink)
                        .fixedSize()
                        .offset(y: size + 4)
                }
            }
            // 点得准：墨点很小，手指点的范围放大到 44pt
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.25), value: isFocused)
            .animation(.easeInOut(duration: 0.25), value: isRecipient)
    }
}

/// 你在这里：一圈邮戳似的细环，中间一个点
struct YouMark: View {
    let ink: MapInk

    var body: some View {
        ZStack {
            Circle()
                .fill(ink.ring.opacity(0.85))
                .frame(width: 22, height: 22)
            Circle()
                .strokeBorder(ink.dot, lineWidth: 1.4)
                .frame(width: 22, height: 22)
            Circle()
                .fill(ink.dot)
                .frame(width: 7, height: 7)
        }
        .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 0.5)
        .overlay(alignment: .top) {
            MapNameTag(text: Text("你"), ink: ink)
                .fixedSize()
                .offset(y: 26)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("你在这里"))
    }
}

/// 在路上的信：航线上的一个小信封
struct TransitEnvelopeMark: View {
    let ink: MapInk

    var body: some View {
        Image(systemName: "envelope.fill")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(ink.post)
            .padding(3)
            .background(Circle().fill(ink.tagPaper))
            .rotationEffect(.degrees(-8))
            .shadow(color: .black.opacity(0.2), radius: 1.5, x: 0, y: 0.5)
            .accessibilityLabel(Text("在路上的信"))
    }
}

/// 墨点下面的小标签（姓、「你」）
struct MapNameTag: View {
    let text: Text
    let ink: MapInk

    var body: some View {
        text
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ink.dot)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(ink.tagPaper))
    }
}
