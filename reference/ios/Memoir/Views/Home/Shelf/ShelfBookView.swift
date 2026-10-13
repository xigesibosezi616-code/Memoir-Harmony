import SwiftUI

/// 书架上的一本书：封面 + 右侧露出的一条书口（纸页厚度）。
///
/// 格子里的书、拖起来浮在手指下的那本，都用这一个视图 —— 两者必须长得一模一样，
/// 否则拿起、放下的那一下会"换了一本书"。
struct ShelfBookView: View {
    let name: String
    let entryCount: Int
    let color: BookColor
    /// 照片封面；nil = 纯色亚麻
    var photo: CoverPhotoSource? = nil
    var layout: CoverLayout = .fullBleed

    /// 书口露出的宽度。格子要为它留出这么宽，`NewBookButton` 也要同样留，书架上才对得齐
    static let pageEdge: CGFloat = 5

    var body: some View {
        BookCoverView(name: name, entryCount: entryCount, color: color, photo: photo, layout: layout)
            // 纸页块和封面一样大，往右错开一点，只露出右边一条
            .background(alignment: .trailing) {
                PageBlock()
                    .padding(.vertical, 3)
                    .offset(x: Self.pageEdge)
            }
            .padding(.trailing, Self.pageEdge)
    }
}

/// 书口：米白纸色 + 几道竖向细纹（一页页纸叠起来的边）
private struct PageBlock: View {
    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color(hex: "#ECE4D3")))
            // 细纹只画在露出来的最右边那几 pt
            for i in 0..<4 {
                let x = size.width - 0.8 - CGFloat(i) * 0.9
                var line = Path()
                line.move(to: CGPoint(x: x, y: 2))
                line.addLine(to: CGPoint(x: x, y: size.height - 2))
                ctx.stroke(line, with: .color(.black.opacity(0.05 + Double(i) * 0.02)), lineWidth: 0.4)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 2.5, x: 1, y: 1)
    }
}

// MARK: - 拿起来的那本：有厚度、能同轴转

/// 被长按拿起的那本书。和格子里的 `ShelfBookView` 一样大，多了左边的书脊，
/// 能绕自己的竖轴转过去露出书脊，再转回正面（投影见 `BookBox`）。
///
/// 转角为 0 时书脊正好侧对着人、不画，看起来和格子里那本完全一样 ——
/// 所以拿起、放回的瞬间可以直接换成它，不会"换了一本书"。
///
/// 遵守 `Animatable`：投影矩阵不能直接插值（线性插值两个旋转矩阵，书会先缩小再变大），
/// 所以让 SwiftUI 插值的是角度，每一帧按角度重新算投影。
struct ShelfBook3D: View, Animatable {
    let name: String
    let entryCount: Int
    let color: BookColor
    var photo: CoverPhotoSource? = nil
    var layout: CoverLayout = .fullBleed
    /// 整本书的尺寸（含书口那一条），与格子里的书相同
    let size: CGSize
    /// 绕竖轴的转角（弧度）。0 = 正面
    var angle: CGFloat

    /// 书的厚度（pt）
    static let depth: CGFloat = 14

    var animatableData: CGFloat {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        // 盒子的正面是封面本身，不含右边露出的书口
        let cover = CGSize(width: size.width - ShelfBookView.pageEdge, height: size.height)
        let boxCenter = CGPoint(x: cover.width / 2, y: cover.height / 2)
        ZStack(alignment: .topLeading) {
            if BookBox.isVisible(face: .spine, angle: angle) {
                BookSpine(color: spineColor)
                    .frame(width: Self.depth, height: cover.height)
                    .projectionEffect(ProjectionTransform(BookBox.transform(
                        face: .spine, angle: angle, coverSize: cover, depth: Self.depth,
                        faceCenter: CGPoint(x: Self.depth / 2, y: cover.height / 2), boxCenter: boxCenter
                    )))
            }
            if BookBox.isVisible(face: .cover, angle: angle) {
                ShelfBookView(name: name, entryCount: entryCount, color: color, photo: photo, layout: layout)
                    .frame(width: size.width, height: size.height)
                    .projectionEffect(ProjectionTransform(BookBox.transform(
                        face: .cover, angle: angle, coverSize: cover, depth: Self.depth,
                        faceCenter: boxCenter, boxCenter: boxCenter
                    )))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// 书脊颜色跟着封面走：
    /// - 满版：照片的主色（书架上那本已经读过缩略图，缓存里一定有）
    /// - 白框：纸色（白框的书是纸面精装，书脊也是纸）
    /// - 贴照片 / 纯色：布面颜色
    private var spineColor: Color {
        guard let photo else { return Color(hex: color.hex) }
        switch layout {
        case .fullBleed:
            if case .file(let name) = photo, let thumb = NotebookCoverStore.cachedThumbnail(name) {
                return thumb.averageColor
            }
            return Color(hex: color.hex)
        case .framed:
            return Color(hex: "#DCD3C2")
        case .tipIn:
            return Color(hex: color.hex)
        }
    }
}

/// 书脊：封面色压暗，圆脊的明暗（中间略亮、两边暗），上下各一道烫线
private struct BookSpine: View {
    let color: Color

    var body: some View {
        ZStack {
            color
            LinearGradient(
                colors: [.black.opacity(0.38), .white.opacity(0.06), .black.opacity(0.28)],
                startPoint: .leading, endPoint: .trailing
            )
            VStack {
                band
                Spacer()
                band
            }
            .padding(.vertical, 16)
        }
    }

    private var band: some View {
        Rectangle()
            .fill(Color(hex: "#D9C08A").opacity(0.45))
            .frame(height: 1)
    }
}
