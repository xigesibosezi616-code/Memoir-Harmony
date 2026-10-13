import SwiftUI
import UIKit

/// 会员信纸：一张摊在桌上的信笺。字一行一格落在格线上，四周（素笺）有一圈细框。
struct LetterStationery: View {
    let palette: LetterPalette
    /// 信头右上角的日期
    let date: String
    /// 抬头「致 XXX」—— 由调用方给出本地化好的 `Text`
    let salutation: Text
    /// 正文（已含开头、结尾、签名）
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: date)
                .font(.custom("Georgia", size: 13))
                .foregroundStyle(palette.ink.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 22)

            salutation
                .font(.custom("Georgia", size: 22))
                .foregroundStyle(palette.ink)
                .padding(.bottom, 6)

            RuledText(text: content, ink: UIColor(palette.ink), rule: UIColor(palette.rule))

            Text(verbatim: "MEMOIR · 尺素")
                .font(.custom("Georgia", size: 10))
                .tracking(3)
                .foregroundStyle(palette.rule)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .background {
            ZStack {
                Rectangle().fill(palette.paper)
                PaperGrain(color: palette.ink)
                if palette.framed {
                    Rectangle()
                        .strokeBorder(palette.rule, lineWidth: 0.8)
                        .padding(12)
                    Rectangle()
                        .strokeBorder(palette.rule, lineWidth: 0.5)
                        .padding(15)
                }
            }
            .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 3)
        }
    }
}

// MARK: - 纸的纤维

/// 很淡的纸纤维。用固定种子，每次画出来都一样（不然滚动重绘时纸会「闪」）
private struct PaperGrain: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 20261010)
            let count = Int(size.width * size.height / 70)
            for _ in 0..<count {
                let x = rng.next() * size.width
                let y = rng.next() * size.height
                let length = 1 + rng.next() * 3
                let angle = rng.next() * .pi
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
                context.stroke(path, with: .color(color.opacity(0.03 + rng.next() * 0.05)), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    /// 0..<1
    mutating func next() -> CGFloat {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}

// MARK: - 一行一格的正文

/// 字落在格线上的正文。
///
/// 用 UIKit 排版而不是 SwiftUI `Text`：`Text` 没法固定行高，中英混排时每行高度不一样
/// （中文回落到苹方，行高比 Georgia 大），格线就会和字错开。这里每行固定同一个高度，
/// 格线按 TextKit 量出来的**每一行的实际基线**来画，一行都不会错位。
struct RuledText: UIViewRepresentable {
    let text: String
    let ink: UIColor
    let rule: UIColor
    var font: UIFont = UIFont(name: "Georgia", size: 17) ?? .systemFont(ofSize: 17)
    var lineHeight: CGFloat = 34
    /// 正文之后再多画几格空行，信纸不至于写到底就断
    var blankLines = 2

    func makeUIView(context: Context) -> RuledTextView {
        RuledTextView()
    }

    func updateUIView(_ view: RuledTextView, context: Context) {
        view.configure(text: text, font: font, lineHeight: lineHeight, ink: ink, rule: rule, blankLines: blankLines)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RuledTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: uiView.height(forWidth: width))
    }
}

final class RuledTextView: UITextView {
    private var ruleColor: UIColor = .clear
    private var lineHeight: CGFloat = 34
    private var blankLines = 2
    /// 格线在基线下面多少 —— 中文字的底比英文基线略低，留几点才不压字
    private let ruleGap: CGFloat = 5

    init() {
        // 自己搭 TextKit 1 的三件套：要用 NSLayoutManager 逐行量基线
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        super.init(frame: .zero, textContainer: container)

        isEditable = false
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        contentMode = .redraw
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, font: UIFont, lineHeight: CGFloat, ink: UIColor, rule: UIColor, blankLines: Int) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: ink,
            .paragraphStyle: paragraph,
        ])
        if attributedText != attributed {
            attributedText = attributed
        }
        self.lineHeight = lineHeight
        self.ruleColor = rule
        self.blankLines = blankLines
        setNeedsDisplay()
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        let fitted = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return ceil(fitted.height) + CGFloat(blankLines) * lineHeight
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(ruleColor.cgColor)
        context.setLineWidth(0.7)

        func stroke(at y: CGFloat) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
        }

        var lastY: CGFloat?
        let glyphs = layoutManager.glyphRange(for: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, range, _ in
            let baseline = fragment.minY + self.layoutManager.location(forGlyphAt: range.location).y
            let y = self.textContainerInset.top + baseline + self.ruleGap
            stroke(at: y)
            lastY = y
        }
        // 没有字时，第一格的基线在行底往上一个下伸部的位置
        var y = lastY ?? (lineHeight + (font?.descender ?? -4) + ruleGap)
        for _ in 0..<blankLines {
            y += lineHeight
            stroke(at: y)
        }
        context.strokePath()
    }
}
