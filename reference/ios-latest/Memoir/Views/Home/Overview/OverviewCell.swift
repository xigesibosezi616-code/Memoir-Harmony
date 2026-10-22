import SwiftUI

/// 总览里的一格：缩小了的大卡片，越密越简（见 `ShowcaseZoom`）。
///
/// 一屏可能有六七十格、滚动时不停地新建，所以这里**什么重活都不做**：文字取 `EntryDigest`（算好的），
/// 照片在后台解（`EntryPhotoStore`），底色是照片解好时一起算的。
/// 也不用毛玻璃（大卡片那层 `.ultraThinMaterial`）：几十格各糊一次很费 GPU，换成页面底色垫底 —— 看着一样
struct OverviewCell: View {
    let digest: EntryDigest
    let zoom: ShowcaseZoom
    /// 格子多大：外面算好传进来，格子里不再用 GeometryReader 量（几十格一起新建时省一大截）
    let size: CGSize

    @Environment(ThemeManager.self) private var themeManager
    @State private var photo: EntryPhotoStore.Photo?

    init(digest: EntryDigest, zoom: ShowcaseZoom, size: CGSize) {
        self.digest = digest
        self.zoom = zoom
        self.size = size
        // 解过的直接用上：滚回来、换级时格子一出来就有图，不闪底色
        _photo = State(initialValue: digest.cover.flatMap {
            EntryPhotoStore.cached($0, pixels: Self.pixels(zoom)) ?? EntryPhotoStore.anyCached($0)
        })
    }

    /// 照片解多大：格子多宽（点）× 3 倍屏，不多解
    static func pixels(_ zoom: ShowcaseZoom) -> CGFloat {
        switch zoom {
        case .one: return 1400
        case .four: return 600
        case .sixteen: return 300
        case .sixtyFour: return 160
        }
    }

    /// 染色：和大卡片一样取照片底部的主色，没照片取心情那一档的颜色
    private var tint: Color {
        if let photo { return Color(uiColor: photo.tint) }
        if let cover = digest.cover, let known = EntryPhotoStore.knownTint(cover) { return Color(uiColor: known) }
        if let mood = digest.mood { return mood.tint }
        return themeManager.current.accent
    }

    var body: some View {
        let tint = tint
        let light = UIColor(tint).isLightColor
        let colors = TextColors(light: light)
        // 格子的尺寸定死，内容放在 overlay 里：照片怎么铺都撑不大格子
        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay {
                switch zoom {
                case .one, .four: card(tint: tint, colors: colors)
                case .sixteen: tile(tint: tint, colors: colors)
                case .sixtyFour: chip(tint: tint)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: zoom.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: zoom.cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: zoom == .sixtyFour ? 0.5 : 0.8)
            )
            .task(id: TaskKey(name: digest.cover, pixels: Self.pixels(zoom))) { await loadPhoto() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: digest.accessibilityText))
            .accessibilityAddTraits(.isButton)
    }

    private struct TaskKey: Hashable {
        let name: String?
        let pixels: CGFloat
    }

    private struct TextColors {
        let title: Color
        let meta: Color
        let body: Color
        init(light: Bool) {
            title = light ? Color(white: 0.10) : .white
            meta = light ? Color(white: 0.36) : Color(white: 0.84)
            body = light ? Color(white: 0.22) : Color(white: 0.92)
        }
    }

    private func loadPhoto() async {
        guard let name = digest.cover else { return }
        let pixels = Self.pixels(zoom)
        if let hit = EntryPhotoStore.cached(name, pixels: pixels) {
            photo = hit
            return
        }
        guard let loaded = await EntryPhotoStore.load(name, pixels: pixels) else { return }
        // 一屏四篇格子大、少，照片淡入；16 / 64 篇时几十格一起到，每格各放一段淡入动画会把主线程占满 —— 直接出来（「照片」App 也是这样）
        if photo == nil, zoom == .four {
            withAnimation(.easeOut(duration: 0.2)) { photo = loaded }
        } else {
            photo = loaded
        }
    }

    // MARK: 一屏 4 篇：小一号的大卡片

    private func card(tint: Color, colors: TextColors) -> some View {
        ZStack(alignment: .top) {
                background(tint)
            VStack(alignment: .leading, spacing: 0) {
                cover
                    .frame(width: size.width, height: size.height * 0.58)
                    .clipped()
                    // 照片下缘溶进底色（和大卡片一样用 mask）。一屏只有四格，mask 的离屏绘制花得起
                    .mask(Self.dissolve)
                VStack(alignment: .leading, spacing: 4) {
                    digest.titleText
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(colors.title)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(verbatim: digest.dayAndWeekday)
                        if let mood = digest.mood {
                            Text(verbatim: "·")
                            Text(mood.title)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(colors.meta)
                    .lineLimit(1)
                    if !digest.preview.isEmpty {
                        Text(verbatim: digest.preview)
                            .font(.system(size: 12))
                            .foregroundStyle(colors.body)
                            .lineSpacing(2)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .frame(width: size.width, alignment: .leading)
            }
        }
    }

    // MARK: 一屏 16 篇：方形照片 + 标题一行 + 几号

    private func tile(tint: Color, colors: TextColors) -> some View {
        ZStack(alignment: .top) {
                background(tint)
            VStack(alignment: .leading, spacing: 0) {
                // 不做溶边（16 格各一次离屏绘制太费）：照片和字条直接分开，小格子里看着反而干净
                cover
                    .frame(width: size.width, height: size.width)
                    .clipped()
                VStack(alignment: .leading, spacing: 1) {
                    digest.titleText
                        .font(.system(size: 10, weight: .semibold, design: .serif))
                        .foregroundStyle(colors.title)
                        .lineLimit(1)
                    Text(verbatim: digest.dayWithWeekday)
                        .font(.system(size: 9))
                        .foregroundStyle(colors.meta)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .frame(width: size.width, alignment: .leading)
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: 一屏 64 篇：照片 / 心情色 + 几号

    private func chip(tint: Color) -> some View {
        ZStack(alignment: .bottomLeading) {
            background(tint)
            // 照片铺满格子，但不能把这一层撑得比格子大（撑大了，左下角的几号就被裁到格子外面去了）
            Color.clear
                .overlay { cover }
                .clipped()
            // 几号压在照片上：底下垫一层淡淡的暗，浅色照片上也看得清
            LinearGradient(colors: [.black.opacity(0), .black.opacity(photo == nil ? 0.12 : 0.38)],
                           startPoint: .center, endPoint: .bottom)
            Text(verbatim: "\(digest.day)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                .padding(.leading, 4)
                .padding(.bottom, 3)
        }
    }

    // MARK: 共用

    /// 和大卡片同一套底色：页面底色垫底 + 主色渐变（大卡片垫的是毛玻璃，透出来的也是页面底色）
    private func background(_ tint: Color) -> some View {
        ZStack {
            themeManager.current.background
            LinearGradient(colors: [tint.opacity(0.72), tint.opacity(0.94)], startPoint: .top, endPoint: .bottom)
        }
    }

    /// 照片铺满；没照片是心情色的渐变（和大卡片一样）；照片还在解就先空着，解好了淡入
    @ViewBuilder
    private var cover: some View {
        if let photo {
            Image(uiImage: photo.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if digest.cover == nil {
            let base = digest.mood?.tint ?? themeManager.current.accent
            LinearGradient(colors: [base.opacity(0.7), base.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color.clear
        }
    }

    private static let dissolve = LinearGradient(
        stops: [
            .init(color: .white, location: 0),
            .init(color: .white, location: 0.72),
            .init(color: .white.opacity(0.35), location: 0.9),
            .init(color: .clear, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
