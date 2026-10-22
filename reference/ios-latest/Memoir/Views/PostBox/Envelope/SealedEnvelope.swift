import SwiftUI

/// 火漆封口的信封，背面（封舌那一面）朝上。
///
/// `progress` 0 = 封着，1 = 信纸已经抽出来。拆信照着实物分三段：
/// 火漆沿封舌边裂开 → 封舌翻上去（上半块火漆跟着走）→ 信纸往上抽出。
/// 每段都是不过冲的平滑曲线，没有回弹（见记忆「交互贴着实物」）。
///
/// 抽出来的信纸会超出信封的上沿，外面要留出约 0.8 个信封高的空间
///
/// ## 封舌像纸页一样卷（2026-10-21 产品定）
/// 封舌动的时候不再整片绕上沿直直地翻，而是像电子书翻页那样卷（着色器 `FlapCurl.metal`）：
/// 卷轴这边平铺，那边卷过去、翻过来露里面的衬纸。路线见 `FlapCurl`；手指捏着拉见 `dragGrab`。
/// 只有打开了 `curls` 的地方（拆信、投信）才卷 —— 要先截两张封舌的贴图；信箱列表里的小信封照原来画。
/// 合着、翻开到底这两个静止的样子也照原来画（卷到头和原来一模一样，接得上）
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
    /// 投信时由调用方直接给封舌和信纸各走到哪（见 `EnvelopePose`），不走 `progress` 的分段；nil = 拆信，照 `progress` 走
    var pose: EnvelopePose? = nil
    /// 封舌动的时候卷（要先截贴图，所以要调用方说一声）。false = 照原来整片翻（信箱列表里的小信封）
    var curls: Bool = false
    /// 封舌走哪条路线卷
    var curl: FlapCurl = .straight
    /// 手指捏着封舌拉（拆信第二步）：捏住的那一点，封舌合着时的位置，按信封宽高的比例；nil = 没在拉
    var dragGrab: CGPoint? = nil
    /// 手指现在在哪（按信封宽高的比例）。跟 `dragGrab` 一起用；能插值 —— 松手后自己卷开 / 落回去
    var dragFinger: CGPoint = .zero

    @Environment(\.displayScale) private var displayScale
    @State private var faces: FlapFaces?

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, CGPoint.AnimatableData> {
        get { AnimatablePair(AnimatablePair(progress, sealPress), dragFinger.animatableData) }
        set {
            progress = newValue.first.first
            sealPress = newValue.first.second
            dragFinger.animatableData = newValue.second
        }
    }

    /// 宽高比，接近常见的西式信封
    static let aspect: CGFloat = 1.56
    /// 封舌尖落在信封高度的哪里
    private static let flapDepth: CGFloat = 0.58
    /// 口袋上沿 V 口的深度（比封舌浅一点，封舌才盖得住）
    private static let notchDepth: CGFloat = 0.5
    /// 信封里面上沿那道信封色的边有多高（点）。
    ///
    /// 卷着画的封舌（着色器那块画布）和内衬各自对齐像素，封舌上沿会比信封上沿低一两个像素，
    /// 缝里露出来的是内衬 —— 极夜的内衬是浅蓝，黑底上一道亮线，别的主题也有（2026-10-21 真机）。
    /// 所以封舌合着、卷着的时候，内衬上沿垫一道信封色，缝里露的就是信封色；封舌整片翻开以后撤掉，内衬照旧铺到上沿。
    /// 缝最多差到 1 点出头（画布按整点对齐时），留 2 点
    private static let hemHeight: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let crack = pose == nil ? Self.phase(progress, 0, 0.14) : 0
            let lift = pose?.flap ?? Self.phase(progress, 0.12, 0.55)
            let slide = pose?.letter ?? Self.phase(progress, 0.55, 1)
            let angle = lift * 180
            let sealSize = w * 0.2
            let sealCenter = CGPoint(x: w / 2, y: h * Self.flapDepth - sealSize * 0.12)
            let curling = faces != nil && curls && (dragGrab != nil || (lift > 0.0005 && lift < 0.9995))
            let faceKey = FaceKey(width: w, height: h, scale: displayScale, palette: palette, sealMark: sealMark,
                                  sealOnFlap: hasSeal && sealPress > 0.999)

            ZStack(alignment: .topLeading) {
                // 1. 信封里面：内衬，越往下越暗。封舌还盖着上沿时，上沿垫一道信封色（见 `hemHeight`）
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(palette.liner)
                    .overlay(
                        LinearGradient(colors: [.black.opacity(0), .black.opacity(0.28)],
                                       startPoint: .top, endPoint: .center)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    )
                    // 方角，和封舌上沿一样：裁成圆角的话，角上那几个半透明的像素还会透出内衬
                    .overlay(alignment: .top) {
                        if curling || lift <= 0.0005 {
                            palette.envelope
                                .frame(height: Self.hemHeight)
                        }
                    }
                    // 影子跟着信封大小走：信箱里那枚小信封不该拖一大片影子
                    .shadow(color: .black.opacity(0.16), radius: w * 0.03, x: 0, y: w * 0.018)

                // 2. 翻过去的封舌，露出内衬那一面。卷着的时候：折痕以上那部分（在信纸后面）
                if curling, let faces {
                    curlLayer(faces, part: 0, width: w, height: h, lift: lift)
                } else if angle > 90 {
                    flap(width: w, height: h, inside: true, sealCenter: sealCenter, sealSize: sealSize, crack: crack)
                        .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.35)
                }

                // 3. 信纸
                FoldedLetter(palette: palette)
                    .frame(width: w * 0.9, height: h * 0.9)
                    .offset(x: w * 0.05, y: h * 0.05 - slide * h * 0.8)

                // 4. 口袋（两侧和底下的折边）
                pocket(width: w, height: h)

                // 5. 还没翻过 90° 的封舌，带着上半块火漆。卷着的时候：折痕以下那部分（在口袋前面）
                if curling, let faces {
                    curlLayer(faces, part: 1, width: w, height: h, lift: lift)
                } else if angle <= 90 {
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
            // 封舌要卷：先把外面 / 里面截成两张贴图（尺寸、配色、封舌上有没有火漆变了才重截）
            .task(id: curls ? faceKey : nil) {
                guard curls, w > 1, h > 1 else { return }
                faces = makeFaces(faceKey)
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
    }

    // MARK: - 卷

    /// 封舌卷起来的那一层（画在比信封大的画布上：翻过去的封舌在信封上沿以上，转着卷时还会往两边甩）
    private func curlLayer(_ faces: FlapFaces, part: Int, width w: CGFloat, height h: CGFloat, lift: Double) -> some View {
        let origin = CGPoint(x: w * 0.3, y: h * 0.75)
        let g = curlGeometry(width: w, height: h, lift: lift)
        // 画布比信封大，但不能撑大信封的布局（撑大了，内衬那些没写死尺寸的会跟着铺满整块画布）：挂在一块信封大小的空地上
        return Color.clear
            .frame(width: w, height: h)
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(.white)
                    .colorEffect(ShaderLibrary.flapCurl(
                        .image(faces.front), .image(faces.back),
                        .float4(origin.x, origin.y, w, h),
                        .float4(g.point.x + origin.x, g.point.y + origin.y, g.normal.dx, g.normal.dy),
                        .float(g.radius),
                        .float(origin.y),
                        .float(Float(part))
                    ))
                    .frame(width: w * 1.6, height: h * 1.85)
                    .shadow(color: .black.opacity(0.14), radius: 1.5, x: 0, y: 1)
                    .offset(x: -origin.x, y: -origin.y)
            }
            .allowsHitTesting(false)
    }

    /// 卷轴在哪（信封坐标）、往哪边卷、卷多粗。`lift` 0 = 合着，1 = 翻开到底
    private func curlGeometry(width w: CGFloat, height h: CGFloat, lift: Double) -> CurlGeometry {
        // 卷得最粗是在半路；合着、翻开到底时不卷（半径 0），和原来的样子接得上
        let thickest = w * 0.075
        if let grab = dragGrab {
            // 手指拉：捏住的那一点跟着手指走 —— 卷轴是两点连线的中垂线（再往手指那边挪半截卷掉的纸，捏住的点才正好在手指下面）
            let g = CGPoint(x: grab.x * w, y: grab.y * h)
            let f = CGPoint(x: dragFinger.x * w, y: dragFinger.y * h)
            let dx = g.x - f.x, dy = g.y - f.y
            let dist = (dx * dx + dy * dy).squareRoot()
            guard dist > 0.5 else {
                return CurlGeometry(point: CGPoint(x: g.x, y: h * 2), normal: CGVector(dx: 0, dy: 1), radius: 0)
            }
            let n = CGVector(dx: dx / dist, dy: dy / dist)
            // 翻开到底时捏住的点落在它沿上沿的倒影上，两点相距 2·g.y
            let open = min(1, dist / max(2 * g.y, 1))
            let r = thickest * sin(.pi * open)
            let a = (dist + .pi * r) / 2
            return CurlGeometry(point: CGPoint(x: g.x - n.dx * a, y: g.y - n.dy * a), normal: n, radius: r)
        }
        let r = thickest * sin(.pi * lift)
        switch curl {
        case .straight:
            // 卷轴横着，从封舌尖（连同挂在尖上的半块火漆）外面一路往上走到上沿
            let reach = h * Self.flapDepth + w * 0.12
            return CurlGeometry(point: CGPoint(x: w / 2, y: (1 - lift) * reach), normal: CGVector(dx: 0, dy: 1), radius: r)
        case .sweep(let pivot):
            // 卷轴绕上沿的一头转：转到 46° 时整片都平了（比封舌斜边的 36.6° 再留一点余量给卷和火漆）
            let alpha = (1 - lift) * 46 * Double.pi / 180
            if pivot == .leading {
                return CurlGeometry(point: .zero, normal: CGVector(dx: -sin(alpha), dy: cos(alpha)), radius: r)
            }
            return CurlGeometry(point: CGPoint(x: w, y: 0), normal: CGVector(dx: sin(alpha), dy: cos(alpha)), radius: r)
        }
    }

    /// 截两张封舌贴图：外面（信封纸、边线，封舌上有火漆的话连上半块火漆）、里面（衬纸）。都是合着时的样子
    @MainActor
    private func makeFaces(_ key: FaceKey) -> FlapFaces? {
        let w = key.width, h = key.height
        let sealSize = w * 0.2
        let sealCenter = CGPoint(x: w / 2, y: h * Self.flapDepth - sealSize * 0.12)
        let front = ImageRenderer(content: ZStack(alignment: .topLeading) {
            FlapShape(depth: Self.flapDepth)
                .fill(palette.envelope)
            FlapShape(depth: Self.flapDepth)
                .stroke(palette.envelopeEdge.opacity(0.35), lineWidth: 0.6)
            if key.sealOnFlap {
                // 拆信时封舌是在火漆裂开之后才动：上半块火漆已经歪了那一点
                WaxSeal(size: sealSize, mark: sealMark)
                    .clipShape(SealCrack(upper: true))
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1.5)
                    .frame(width: sealSize, height: sealSize)
                    .position(sealCenter)
                    .rotationEffect(.degrees(-1.2), anchor: .init(x: sealCenter.x / w, y: sealCenter.y / h))
            }
        }
        .frame(width: w, height: h))
        let back = ImageRenderer(content: ZStack(alignment: .topLeading) {
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
        }
        .frame(width: w, height: h))
        front.scale = key.scale
        back.scale = key.scale
        guard let f = front.uiImage, let b = back.uiImage else {
            NSLog("⚠️ [SealedEnvelope] 封舌贴图没截出来 %.0f×%.0f，封舌照原来整片翻", w, h)
            return nil
        }
        return FlapFaces(front: Image(uiImage: f), back: Image(uiImage: b))
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

/// 封舌卷的路线（2026-10-21：像电子书翻页那样卷，不再整片绕上沿直上直下）
enum FlapCurl: Equatable {
    /// 卷轴横着，从封舌尖往上卷（点一下、上滑拆信）
    case straight
    /// 卷轴绕上沿的一头转：`pivot` 那头最后动，另一头先动。
    /// 寄信合上时按信在邮筒中轴哪边定（产品定）：在左边就绕左头转、右边先落下；在右边反过来
    case sweep(pivot: HorizontalEdge)
}

/// 卷轴：一点、法向（指向卷起来的那边）、卷的半径。信封坐标（点）
private struct CurlGeometry {
    var point: CGPoint
    var normal: CGVector
    var radius: CGFloat
}

/// 截好的两张封舌贴图
private struct FlapFaces {
    let front: Image
    let back: Image
}

/// 贴图跟着这些变：尺寸、屏幕密度、配色、火漆印面、封舌上有没有火漆
private struct FaceKey: Equatable {
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let palette: LetterPalette
    let sealMark: String?
    let sealOnFlap: Bool
}

/// 投信时信封的样子：封舌翻开多少（1 = 翻开、0 = 合上）、信纸露在外面多少（1 = 抽出来、0 = 装好）。
///
/// 拆信是一段接一段（裂开 → 翻开 → 抽出，一个 `progress` 管到底）；投信要两段叠着走 ——
/// 信纸还剩一截在外面，封舌就开始往下合（2026-10-20：一段停稳再起下一段，真机上看着生硬）
struct EnvelopePose: Equatable {
    var flap: Double
    var letter: Double
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
