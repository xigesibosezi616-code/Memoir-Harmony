import SwiftUI

/// 日记本封面。没有照片是纯色亚麻；有照片按版式（`CoverLayout`）分三种：
///
/// - **纯色亚麻**：预渲染精修图方案（2026-10 起只剩亚麻，8 色 8 张）。
///   视觉细节（颜色 / 纹理颗粒 / 光照 / 凹陷压痕 / M·S 烫金标 / 书脊弧面 / 边缘磨砂）全部在 PNG 里，
///   SwiftUI 只加载 `Cover_{Color}_Linen` 并叠加标题与篇数。
/// - **满版**（2026-10 P2）：照片铺满，SwiftUI 补上精装书的样子 ——
///   左侧书脊的明暗与一道压痕、上下各压暗一层让文字在任何照片上都看得清。
/// - **白框**（P3b）：米白纸封面，照片嵌在上半部，书名写在照片下面。
/// - **贴照片**（P3b）：亚麻布面中间贴一张带白边的照片、四角压着相角，书名烫在照片下面。
///
/// 白框、贴照片的各部分按封面宽度的比例摆，书架上的小书和编辑页的大预览长得一样。
struct BookCoverView: View {
    let name: String
    let entryCount: Int
    let color: BookColor
    /// 照片封面；nil = 纯色亚麻
    var photo: CoverPhotoSource? = nil
    /// 照片封面的版式；没有照片时不起作用
    var layout: CoverLayout = .fullBleed

    private var assetName: String {
        "Cover_\(color.rawValue)_\(BookTexture.linen.rawValue)"
    }

    /// 中日韩标题按每 4 字断行。
    ///
    /// 带拉丁字母的（英文名、外语界面下「全部日记」的译名）不手动断 —— 按 4 个字符硬切
    /// 会把「All Entries」切成「All 」「Entr」「ies」，交给系统按词换行。
    private var displayName: String {
        guard name.count > 4,
              !name.contains(where: { $0.isASCII && $0.isLetter }) else { return name }
        var result = ""
        for (i, char) in name.enumerated() {
            if i > 0 && i % 4 == 0 { result += "\n" }
            result.append(char)
        }
        return result
    }

    var body: some View {
        // 尺寸由 Color.clear 按比例定，各版式的内容放 overlay 里 —— 铺满的照片撑不大封面
        Color.clear
            .aspectRatio(0.73, contentMode: .fit)
            .overlay {
                if let photo {
                    switch layout {
                    case .fullBleed: fullBleedCover(photo)
                    case .framed:    framedCover(photo)
                    case .tipIn:     tipInCover(photo)
                    }
                } else {
                    clothCover
                }
            }
            .shadow(color: .black.opacity(0.20), radius: 10, x: 2, y: 6)
            .shadow(color: .black.opacity(0.12), radius: 3,  x: 0, y: 2)
    }

    // MARK: - 共用：标题与篇数

    /// 左上的书名（纯色、满版用）。名字是用户数据，不查翻译表
    private func cornerTitle(color: Color, shadow: Color, shadowRadius: CGFloat) -> some View {
        Text(verbatim: displayName)
            .font(.system(size: 14, weight: .medium, design: .serif))
            .foregroundColor(color)
            .shadow(color: shadow, radius: shadowRadius, x: 0, y: 0.5)
            .lineLimit(3)
            .lineSpacing(4)
            .multilineTextAlignment(.leading)
            .padding(.leading, 16)
            .padding(.top, 28)
            .padding(.trailing, 16)
    }

    /// 左下的篇数
    private func countBadge(color: Color, opacity: Double) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.55))
                .frame(width: 5, height: 5)
            Text("\(entryCount)")
                .font(.system(size: 11, design: .serif))
                .foregroundColor(color.opacity(opacity))
        }
    }

    /// 书脊处的明暗 + 一道压痕（精装书封面靠近书脊处的那条凹槽）
    private func hinge(strength: Double) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.45 * strength), .black.opacity(0.12 * strength)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 9)
            Rectangle().fill(Color.black.opacity(0.22 * strength)).frame(width: 0.8)
            Rectangle().fill(Color.white.opacity(0.22)).frame(width: 0.6)
        }
    }

    // MARK: - 纯色亚麻

    private var clothCover: some View {
        // 浅底（只有象牙白）用深棕字，其余米白
        let text = color.isLight ? Color(hex: "#3D3428") : Color(hex: "#F5F0E6")
        let shadow = color.isLight ? Color.white.opacity(0.5) : Color.black.opacity(0.4)
        return Image(assetName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .overlay(alignment: .topLeading) {
                cornerTitle(color: text, shadow: shadow, shadowRadius: 1)
            }
            .overlay(alignment: .bottomLeading) {
                countBadge(color: text, opacity: 0.65)
                    .padding(.leading, 16)
                    .padding(.bottom, 14)
            }
    }

    // MARK: - 满版

    private func fullBleedCover(_ photo: CoverPhotoSource) -> some View {
        let text = Color(hex: "#F5F0E6")
        return Color.clear
            .overlay {
                CoverPhotoView(source: photo, fallback: Color(hex: color.hex))
            }
            .clipped()
            // 上下压暗：上面给标题、下面给篇数，在任何照片上都读得清；中间留给照片本身
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.42), location: 0),
                        .init(color: .black.opacity(0), location: 0.45),
                        .init(color: .black.opacity(0), location: 0.75),
                        .init(color: .black.opacity(0.32), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .overlay(alignment: .leading) { hinge(strength: 1) }
            // 边缘一圈极细的暗线，压住照片的硬边，像布面包边
            .overlay {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            .overlay(alignment: .topLeading) {
                cornerTitle(color: text, shadow: .black.opacity(0.55), shadowRadius: 2)
            }
            .overlay(alignment: .bottomLeading) {
                countBadge(color: text, opacity: 0.8)
                    .padding(.leading, 16)
                    .padding(.bottom, 14)
            }
    }

    // MARK: - 白框

    /// 白框的纸与墨
    static let framedPaper = Color(hex: "#F4EEE2")
    static let framedInk = Color(hex: "#3D3428")

    private func framedCover(_ photo: CoverPhotoSource) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let margin = w * 0.1
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: "#F8F3EA"), Self.framedPaper], startPoint: .top, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 0) {
                    // 抬头：篇数 + 一道细线（参考图 ② 的刊头）
                    countBadge(color: Self.framedInk, opacity: 0.6)
                        .scaleEffect(0.85, anchor: .leading)
                        .frame(height: h * 0.11)
                    Rectangle()
                        .fill(Self.framedInk.opacity(0.35))
                        .frame(height: 0.5)

                    // 照片：方形
                    Color.clear
                        .frame(width: w - margin * 2, height: w - margin * 2)
                        .overlay { CoverPhotoView(source: photo, fallback: Color(hex: "#E8DDC9")) }
                        .clipped()
                        .padding(.top, h * 0.03)

                    Text(verbatim: displayName)
                        .font(.system(size: max(10, w * 0.1), weight: .medium, design: .serif))
                        .foregroundColor(Self.framedInk)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .padding(.top, h * 0.04)
                }
                .padding(.horizontal, margin)
            }
            .overlay(alignment: .leading) { hinge(strength: 0.35) }
            .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
            }
        }
    }

    // MARK: - 贴照片

    /// 烫在布面上的颜色：象牙白布面压深棕（像压痕），其余烫金
    private var foil: Color {
        color.isLight ? Color(hex: "#6B5A3E") : Color(hex: "#D9C08A")
    }

    private func tipInCover(_ photo: CoverPhotoSource) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let plateWidth = w * 0.6
            ZStack(alignment: .top) {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: w, height: h)
                    .clipped()

                VStack(spacing: h * 0.045) {
                    MountedPhoto(photo: photo, width: plateWidth)
                        .padding(.top, h * 0.13)
                    Text(verbatim: displayName)
                        .font(.system(size: max(10, w * 0.1), weight: .medium, design: .serif))
                        .foregroundColor(foil)
                        .shadow(color: .black.opacity(color.isLight ? 0.08 : 0.35), radius: 0.5, x: 0, y: 1)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, w * 0.12)
                }
                .frame(width: w)
            }
        }
    }
}

// MARK: - 贴在布面上的照片

/// 一张带白边、四角压着相角的照片 —— 老相册封面上贴的那种。贴照片版式的封面和日记本主页大图共用
struct MountedPhoto: View {
    let photo: CoverPhotoSource
    /// 连白边在内的宽度
    let width: CGFloat
    var fullResolution = false

    var body: some View {
        let height = width * 1.1
        let border = width * 0.05
        let corner = width * 0.15
        Color(hex: "#F6F1E6")
            .frame(width: width, height: height)
            .overlay {
                Color.clear
                    .overlay { CoverPhotoView(source: photo, fallback: Color(hex: "#E8DDC9"), fullResolution: fullResolution) }
                    .clipped()
                    .padding(border)
            }
            // 相角：四个深色小三角压住照片的角
            .overlay {
                Canvas { ctx, size in
                    let ink = GraphicsContext.Shading.color(Color(hex: "#2B2521").opacity(0.92))
                    let corners: [(CGPoint, CGPoint, CGPoint)] = [
                        (.zero, CGPoint(x: corner, y: 0), CGPoint(x: 0, y: corner)),
                        (CGPoint(x: size.width, y: 0), CGPoint(x: size.width - corner, y: 0), CGPoint(x: size.width, y: corner)),
                        (CGPoint(x: 0, y: size.height), CGPoint(x: corner, y: size.height), CGPoint(x: 0, y: size.height - corner)),
                        (CGPoint(x: size.width, y: size.height), CGPoint(x: size.width - corner, y: size.height), CGPoint(x: size.width, y: size.height - corner))
                    ]
                    for (a, b, c) in corners {
                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: b)
                        path.addLine(to: c)
                        path.closeSubpath()
                        ctx.fill(path, with: ink)
                    }
                }
            }
            .shadow(color: .black.opacity(0.32), radius: 1.5, x: 0, y: 1)
    }
}
