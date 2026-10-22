import SwiftUI

// MARK: - 火漆印

/// 一枚火漆印：深红的蜡、边缘不规则地溢开一圈，中间压一个字。
///
/// 真的火漆印压的是主人的姓名首字母，所以压谁的字看这枚印是谁的（2026-10-10 产品定）：
/// - 付费页、会员页：**用户自己的名字**（笔友回信时称呼他的那个昵称）的第一个字
/// - 火漆信的封口：**笔友名字**的第一个字 —— 信是笔友封的，现实里是寄信人用自己的印
///
/// 没有可用的名字时压「素」
struct WaxSeal: View {
    var size: CGFloat = 64
    /// 压在中间的字；nil = 「素」
    var mark: String? = nil

    /// 名字 → 印上的字：中文取第一个字，拉丁字母取首字母并大写。
    /// 没名字、或以 emoji / 符号 / 数字开头的，返回 nil（压「素」）—— 火漆上压个表情不像样
    static func initial(of name: String?) -> String? {
        guard let first = name?.trimmingCharacters(in: .whitespacesAndNewlines).first,
              first.isLetter else { return nil }
        return String(first).uppercased()
    }

    private var text: String { mark ?? "素" }

    var body: some View {
        ZStack {
            // 溢开的蜡：几个错开的圆叠出不规则的边
            ForEach(0..<7, id: \.self) { i in
                let angle = Double(i) / 7 * 2 * .pi
                Circle()
                    .fill(Self.wax)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .offset(x: cos(angle) * size * 0.31, y: sin(angle) * size * 0.31)
            }
            Circle()
                .fill(RadialGradient(colors: [Self.waxLight, Self.wax], center: .init(x: 0.38, y: 0.32),
                                     startRadius: 1, endRadius: size * 0.5))
                .frame(width: size * 0.84, height: size * 0.84)
            // 压印的内圈
            Circle()
                .stroke(Color.black.opacity(0.22), lineWidth: size * 0.02)
                .frame(width: size * 0.62, height: size * 0.62)
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: size * 0.015)
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(x: size * 0.008, y: size * 0.008)
            Text(verbatim: text)
                .font(.system(size: size * 0.32, weight: .semibold, design: .serif))
                .foregroundStyle(Color.black.opacity(0.28))
                .overlay {
                    Text(verbatim: text)
                        .font(.system(size: size * 0.32, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.22))
                        .offset(x: size * 0.012, y: size * 0.012)
                }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
        .accessibilityHidden(true)
    }

    private static let wax = Color(hex: "#8E2B24")
    private static let waxLight = Color(hex: "#B54A3E")
}
