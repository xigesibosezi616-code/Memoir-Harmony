import SwiftUI

/// 火漆封口的信封，背面（封舌那一面）朝上。
///
/// `progress` 0 = 封着，1 = 信纸已经抽出来。拆信照着实物分三段：
/// 火漆沿封舌边裂开 → 封舌翻上去（上半块火漆跟着走）→ 信纸往上抽出。
/// 每段都是不过冲的平滑曲线，没有回弹（见记忆「交互贴着实物」）。
///
/// 抽出来的信纸会超出信封的上沿，外面要留出约 0.8 个信封高的空间
struct SealedEnvelope: View, Animatable {
    let palette: LetterPalette
    /// 火漆上压的字；nil = 「素」
    let sealMark: String?
    /// 信封背面下方的一行小字（「来自 青鸟」）
    var sender: Text? = nil
    var progress: Double = 0
    /// 有没有火漆。免费用户寄出去的信封只是普通封口（投信时用）
    var hasSeal: Bool = true
    /// 火漆按下去到哪：0 = 还没盖，1 = 盖好了。投信时会员的信封在封舌合上之后才盖火漆；
    /// 拆信时一直是 1
    var sealPress: Double = 1

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, sealPress) }
        set {
            progress = newValue.first
            sealPress = newValue.second
        }
    }

    /// 宽高比，接近常见的西式信封
    static let aspect: CGFloat = 1.56
    /// 封舌尖落在信封高度的哪里
    private static let flapDepth: CGFloat = 0.58
    /// 口袋上沿 V 口的深度（比封舌浅一点，封舌才盖得住）
    private static let notchDepth: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let crack = Self.phase(progress, 0, 0.14)
            let lift = Self.phase(progress, 0.12, 0.55)
            let slide = Self.phase(progress, 0.55, 1)
            let angle = lift * 180
            let sealSize = w * 0.2
            let sealCenter = CGPoint(x: w / 2, y: h * Self.flapDepth - sealSize * 0.12)

            ZStack(alignment: .topLeading) {
                // 1. 信封里面：内衬，越往下越暗
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(palette.liner)
                    .overlay(
                        LinearGradient(colors: [.black.opacity(0), .black.opacity(0.28)],
                                       startPoint: .top, endPoint: .center)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    )
                    // 影子跟着信封大小走：信箱里那枚小信封不该拖一大片影子
                    .shadow(color: .black.opacity(0.16), radius: w * 0.03, x: 0, y: w * 0.018)

                // 2. 翻过去的封舌，露出内衬那一面
                if angle > 90 {
                    flap(width: w, height: h, inside: true, sealCenter: sealCenter, sealSize: sealSize, crack: crack)
                        .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.35)
                }

                // 3. 信纸
                FoldedLetter(palette: palette)
                    .frame(width: w * 0.9, height: h * 0.9)
                    .offset(x: w * 0.05, y: h * 0.05 - slide * h * 0.8)

                // 4. 口袋（两侧和底下的折边）
                pocket(width: w, height: h)

                // 5. 还没翻过 90° 的封舌，带着上半块火漆
                if angle <= 90 {
                    flap(width: w, height: h, inside: false, sealCenter: sealCenter, sealSize: sealSize, crack: crack)
                        .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.35)
                }

                // 6. 下半块火漆粘在口袋上，不跟封舌走
                if hasSeal {
                    sealPiece(upper: false, size: sealSize)
                        .position(sealCenter)
                        .offset(y: crack * w * 0.005)
                }
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
    }

    // MARK: - 部件

    private func pocket(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            PocketShape(notch: Self.notchDepth)
                .fill(palette.envelope)
            // V 口的两道边（封着时被封舌盖住，拆开才看得见）
            NotchEdges(notch: Self.notchDepth)
                .stroke(palette.envelopeEdge.opacity(0.55), lineWidth: 0.7)
            // 底下那片折边，压在两侧上面，边上一道很淡的影子
            BottomFlapShape()
                .fill(palette.envelope)
                .shadow(color: .black.opacity(0.10), radius: 1.5, x: 0, y: -1)
            BottomFlapShape()
                .stroke(palette.envelopeEdge.opacity(0.45), lineWidth: 0.7)
            if let sender {
                sender
                    .font(.custom("Georgia", size: max(11, w * 0.036)).italic())
                    .foregroundStyle(palette.envelopeEdge)
                    .frame(width: w, alignment: .center)
                    .offset(y: h * 0.8)
            }
        }
        .frame(width: w, height: h)
    }

    private func flap(width w: CGFloat, height h: CGFloat, inside: Bool,
                      sealCenter: CGPoint, sealSize: CGFloat, crack: Double) -> some View {
        ZStack(alignment: .topLeading) {
            if inside {
                // 内面：内衬贴在封舌里面，四周留一圈信封纸
                FlapShape(depth: Self.flapDepth)
                    .fill(palette.envelope)
                FlapShape(depth: Self.flapDepth)
                    .fill(palette.liner)
                    .scaleEffect(x: 0.9, y: 0.86, anchor: .top)
                    .overlay(
                        FlapShape(depth: Self.flapDepth)
                            .fill(.black.opacity(0.12))
                            .scaleEffect(x: 0.9, y: 0.86, anchor: .top)
                    )
            } else {
                FlapShape(depth: Self.flapDepth)
                    .fill(palette.envelope)
                    .shadow(color: .black.opacity(0.14), radius: 1.5, x: 0, y: 1)
                FlapShape(depth: Self.flapDepth)
                    .stroke(palette.envelopeEdge.opacity(0.35), lineWidth: 0.6)
                if hasSeal {
                    sealPiece(upper: true, size: sealSize)
                        .position(sealCenter)
                        .rotationEffect(.degrees(-crack * 1.2), anchor: .init(x: sealCenter.x / w, y: sealCenter.y / h))
                }
            }
        }
        .frame(width: w, height: h)
    }

    /// 裂成两半的火漆之一。裂缝是一道横着的锯齿，大致沿着封舌的边
    private func sealPiece(upper: Bool, size: CGFloat) -> some View {
        // 盖火漆：蜡从上方落下、压平 —— 一路缩到原大，没有回弹
        let press = Self.phase(sealPress, 0, 1)
        return WaxSeal(size: size, mark: sealMark)
            .clipShape(SealCrack(upper: upper))
            // WaxSeal 自带的影子被裁掉了，裁完再补一道
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1.5)
            .frame(width: size, height: size)
            .scaleEffect(1 + 0.3 * (1 - press))
            .opacity(min(1, sealPress / 0.4))
    }

    /// 0…1 之间的一段，映射成 0…1 的平滑曲线（smoothstep，两头都缓，不过冲）
    static func phase(_ p: Double, _ start: Double, _ end: Double) -> Double {
        let t = min(max((p - start) / (end - start), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

// MARK: - 信封里的信纸（折好的，只露上半截）。投信动画收拢那一下也用它

struct FoldedLetter: View {
    let palette: LetterPalette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                Rectangle().fill(palette.paper)
                // 几道格线，抽出来时看得出是信纸
                ForEach(1..<7, id: \.self) { i in
                    Rectangle()
                        .fill(palette.rule)
                        .frame(width: w * 0.84, height: 0.6)
                        .offset(x: w * 0.08, y: h * 0.16 + CGFloat(i) * h * 0.11)
                }
                // 对折的折痕
                Rectangle()
                    .fill(LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.07), .black.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 6)
                    .offset(y: h * 0.5 - 3)
            }
            .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 0.5)
        }
    }
}

// MARK: - 形状

/// 上面的封舌：一个倒三角，尖儿磨圆
private struct FlapShape: Shape {
    let depth: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tip = CGPoint(x: rect.midX, y: rect.height * depth)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addArc(tangent1End: tip, tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: rect.width * 0.05)
        p.closeSubpath()
        return p
    }
}

/// 口袋：整张信封减去上面的 V 口
private struct PocketShape: Shape {
    let notch: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.height * notch))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 口袋 V 口的两道边
private struct NotchEdges: Shape {
    let notch: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.height * notch))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// 底下那片折边：从两个下角往中间收，顶上是一道缓弧
private struct BottomFlapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                       control: CGPoint(x: rect.midX, y: rect.height * 0.18))
        p.closeSubpath()
        return p
    }
}

/// 火漆的一半。裂缝横穿中间偏下，带几道锯齿。
///
/// 裁剪范围要比火漆的框大一圈：蜡溢开的边本来就超出框，按框裁会把左右两边裁平
private struct SealCrack: Shape {
    let upper: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let crack: [CGPoint] = [
            (-0.20, 0.54), (0.00, 0.54), (0.16, 0.50), (0.27, 0.57), (0.40, 0.51),
            (0.52, 0.58), (0.63, 0.52), (0.76, 0.57), (0.88, 0.51), (1.00, 0.55), (1.20, 0.55),
        ].map { CGPoint(x: rect.minX + $0.0 * w, y: rect.minY + $0.1 * h) }

        var p = Path()
        p.move(to: crack[0])
        for point in crack.dropFirst() { p.addLine(to: point) }
        let outer = upper ? rect.minY - h * 0.2 : rect.maxY + h * 0.2
        p.addLine(to: CGPoint(x: rect.maxX + w * 0.2, y: outer))
        p.addLine(to: CGPoint(x: rect.minX - w * 0.2, y: outer))
        p.closeSubpath()
        return p
    }
}
