import SwiftUI

/// 日记本主页顶部的大图（参考图 ① / ④）。高度由外面定。和书架上的封面一一对应：
///
/// - **满版**：照片铺满，往下渐渐融进页面底色；书名用正文色写在融化的那一段上（参考图 ④），
///   顶部压一层浅暗，状态栏和返回键在亮照片上也看得清
/// - **白框**（P3b）：整幅米白纸，照片嵌在中间，书名写在照片下面 —— 一页杂志（参考图 ②）
/// - **贴照片**（P3b）：布面铺满，正中贴一张带白边、压着相角的照片，书名烫在下面
/// - **纯色亚麻**（2026-10-08 产品定「布面铺满」）：把这本的布面放大铺满，书名像烫在布面正中，
///   上下各一道细线 —— 一本布面精装书的封面放大来看。
///   布面取的是封面图中间偏上那一块，四周的压边框、左侧书脊阴影、右下角的 M·S 烫标都裁在外面
///
/// 只有满版往下渐隐；其余三种底边干净地收住（深色布渐隐到米白会混出一段发灰的脏粉色）。
struct BookHeroView: View {
    /// 书名（「全部日记」由调用方翻译好再传进来）
    let title: String
    let subtitle: String?
    let color: BookColor
    let photo: CoverPhotoSource?
    var layout: CoverLayout = .fullBleed

    @Environment(ThemeManager.self) private var themeManager

    /// 满版底部融进页面底色的那一段有多高
    private let fadeHeight: CGFloat = 150
    /// 上面压着状态栏和导航栏，内容从这往下排
    private let topClearance: CGFloat = 104

    private enum Style { case cloth, fullBleed, framed, tipIn }

    private var style: Style {
        guard photo != nil else { return .cloth }
        switch layout {
        case .fullBleed: return .fullBleed
        case .framed:    return .framed
        case .tipIn:     return .tipIn
        }
    }

    var body: some View {
        let theme = themeManager.current
        // 照片 / 布面都是「铺满」的，按图的比例会把自己撑得比给定的高度更高，溢出到下面的目录上
        //（2026-10-08 实测：给 444pt，照片撑到约 550pt）。
        // 放进 `Color.clear` 的 overlay 里：尺寸由 Color.clear 决定（= 外面给的），图再怎么铺也只在这个框里
        Color.clear
            .overlay {
                switch style {
                case .fullBleed:
                    if let photo {
                        CoverPhotoView(source: photo, fallback: Color(hex: color.hex), fullResolution: true)
                            // 顶部压暗：状态栏、返回键压在亮照片上也看得清
                            .overlay(alignment: .top) {
                                LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 140)
                            }
                    }
                case .framed:
                    LinearGradient(colors: [Color(hex: "#F8F3EA"), BookCoverView.framedPaper], startPoint: .top, endPoint: .bottom)
                case .cloth, .tipIn:
                    cloth
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                if style == .fullBleed {
                    // 融进页面底色，和下面的目录接成一体（参考图 ④）
                    LinearGradient(
                        stops: [
                            .init(color: theme.background.opacity(0), location: 0),
                            .init(color: theme.background.opacity(0.85), location: 0.7),
                            .init(color: theme.background, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: fadeHeight)
                } else {
                    // 干净地收在一条边上：底边一点暗影 + 一道细亮线，像封面的下沿
                    let lightBase = style == .framed || color.isLight
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0), .black.opacity(lightBase ? 0.08 : 0.22)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 22)
                        Rectangle().fill(Color.white.opacity(lightBase ? 0.5 : 0.12)).frame(height: 0.5)
                    }
                }
            }
            .overlay {
                switch style {
                case .fullBleed:
                    photoTitle(theme: theme)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                case .framed:
                    if let photo { framedContent(photo) }
                case .tipIn:
                    if let photo { tipInContent(photo) }
                case .cloth:
                    clothTitle
                        .padding(.top, 60)
                }
            }
    }

    // MARK: - 满版

    private func photoTitle(theme: any AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 书名是用户数据，不查翻译表
            Text(verbatim: title)
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            subtitleText(color: theme.textSecondary)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    // MARK: - 白框

    private func framedContent(_ photo: CoverPhotoSource) -> some View {
        GeometryReader { geo in
            let ink = BookCoverView.framedInk
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(ink.opacity(0.3))
                    .frame(height: 0.5)
                Color.clear
                    .overlay { CoverPhotoView(source: photo, fallback: Color(hex: "#E8DDC9"), fullResolution: true) }
                    .clipped()
                    .padding(.top, 16)
                Text(verbatim: title)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 18)
                subtitleText(color: ink.opacity(0.6))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 26)
            .padding(.top, topClearance)
            .padding(.bottom, 30)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    // MARK: - 贴照片

    private func tipInContent(_ photo: CoverPhotoSource) -> some View {
        GeometryReader { geo in
            // 照片 + 书名要塞进导航栏以下的那段里：宽度按可用高度反推，免得矮屏上挤出去
            let available = geo.size.height - topClearance - 130
            let plateWidth = min(geo.size.width * 0.52, available / 1.1)
            VStack(spacing: 22) {
                MountedPhoto(photo: photo, width: plateWidth, fullResolution: true)
                clothTitle
            }
            .frame(width: geo.size.width)
            .padding(.top, topClearance)
        }
    }

    // MARK: - 布面

    private var cloth: some View {
        Image("Cover_\(color.rawValue)_\(BookTexture.linen.rawValue)")
            .resizable()
            .aspectRatio(contentMode: .fill)
            // 放大 1.25、锚在中间偏上：可见范围约为横 10%–90%、纵 8%–88%，
            // 压边框（约 4%–96%）、书脊阴影（左 8%）、M·S 烫标（纵 90% 以下）都在外面
            .scaleEffect(1.25, anchor: UnitPoint(x: 0.5, y: 0.42))
    }

    /// 烫在布面上的颜色：象牙白布面压深棕（像压痕），其余烫金
    private var foil: Color {
        color.isLight ? Color(hex: "#6B5A3E") : Color(hex: "#D9C08A")
    }

    private var clothTitle: some View {
        VStack(spacing: 14) {
            Rectangle().fill(foil.opacity(0.7)).frame(width: 36, height: 0.8)
            Text(verbatim: title)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(foil)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                // 一点点压暗的投影，像烫金压进布里
                .shadow(color: .black.opacity(color.isLight ? 0.08 : 0.35), radius: 0.5, x: 0, y: 1)
            Rectangle().fill(foil.opacity(0.7)).frame(width: 36, height: 0.8)
            subtitleText(color: foil.opacity(0.85))
        }
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private func subtitleText(color: Color) -> some View {
        if let subtitle {
            Text(verbatim: subtitle)
                .font(.system(size: 11, weight: .medium))
                .tracking(2.4)
                .foregroundStyle(color)
        }
    }
}
