import SwiftUI
import SwiftData
import AVFoundation

/// 大屏展示模式 —— 一屏一篇日记，左右滑动翻篇。
///
/// 与列表模式的分工：列表用来**找**某一篇，大屏用来**重看**。所以这里放大照片、留白，
/// 让一篇日记像一张唱片封面那样被重新看见。
///
/// 双指捏小换成总览（一屏 4 篇左右翻 `ShowcaseQuadPager`，16 / 64 篇上下滚 `ShowcaseOverview`）；
/// 张开回到这里时停在手指底下那篇 —— 所以翻到哪篇记在 `HomeView` 给的 `pages` 里。
///
/// 🔴 **横向分页的 ScrollView + LazyHStack，不用 TabView**（2026-10-21）：日记多了以后（几百篇），
/// TabView 翻一页会把很多页的 body 都算一遍；现在只建眼前这一两页。照片在后台解（`EntryPhotoStore`），
/// 翻到哪页就把左右两页的照片先解出来
struct ShowcaseView: View {
    @Environment(ThemeManager.self) private var themeManager
    let entries: [JournalEntry]
    /// 翻到的那篇（`pages.single`）。`@Observable`：翻页只重画这一块，不重画首页
    @Bindable var pages: ShowcasePages
    /// 换一屏放几篇（读屏的动作用；手指捏合在 `HomeView`）：换到哪一级、以哪篇为准
    let onZoom: (ShowcaseZoom?, UUID) -> Void
    let onOpen: (JournalEntry) -> Void

    var body: some View {
        GeometryReader { geo in
            // 尺寸显式算好传下去：卡片内部任何一处都不再依赖「可用宽度」的推断，
            // 避免大图把布局撑破（会表现为卡片顶到屏幕边、圆角丢失）
            let cardSize = CGSize(
                width: max(0, geo.size.width - 36),
                height: max(0, geo.size.height - 16)
            )
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(entries) { entry in
                        ShowcaseCard(entry: entry, size: cardSize)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen(entry) }
                            .accessibilityAction(named: Text("一屏看更多篇")) { onZoom(ShowcaseZoom.one.zoomedOut, entry.id) }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $pages.single)
            // 外面整页的上下滚动锁着（`HomeView`），锁是往下传的：这里自己放开，左右照样翻
            .scrollDisabled(false)
            .scrollIndicators(.hidden)
            // 卡片不加阴影（见 `ShowcaseCard` 的注释），这里不裁也没东西露出去
            .background(themeManager.current.background)
        }
        .background(themeManager.current.background)
        .onChange(of: pages.single, initial: true) { _, id in prefetch(around: id) }
    }

    /// 左右各两页的照片先在后台解出来，翻过去就有
    private func prefetch(around id: UUID?) {
        guard let index = id.flatMap({ id in entries.firstIndex { $0.id == id } }) ?? (entries.isEmpty ? nil : 0) else { return }
        let range = max(0, index - 2)...min(entries.count - 1, index + 2)
        let names = range.compactMap { EntryDigest.of(entries[$0]).cover }
        EntryPhotoStore.prefetch(names, pixels: ShowcaseCard.photoPixels)
    }
}

// MARK: - 单篇卡片


private struct ShowcaseCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let entry: JournalEntry
    let size: CGSize
    /// 轮播的照片、正文预览：正文是 JSON，建卡片时解一次，别在 body 里反复解
    private let photos: [String]
    private let preview: String

    @State private var photoIndex = 0
    /// 正在显示的那张（后台解好的，连同底色）
    @State private var photo: EntryPhotoStore.Photo?
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var rotationTask: Task<Void, Never>?

    private static let rotationInterval: Duration = .seconds(4)
    private static let cornerRadius: CGFloat = 26
    /// 大卡片的照片解到多大（最长边，像素）
    static let photoPixels: CGFloat = 1400

    init(entry: JournalEntry, size: CGSize) {
        self.entry = entry
        self.size = size
        let photos = entry.showcasePhotoFilenames
        self.photos = photos
        preview = entry.textPreview
        // 解过的直接用上（翻回来、从总览张开时一出来就有图）
        _photo = State(initialValue: photos.first.flatMap {
            EntryPhotoStore.cached($0, pixels: Self.photoPixels) ?? EntryPhotoStore.anyCached($0)
        })
    }

    /// 文字区的染色 —— 取自照片底部主色（后台和照片一起算好的），取不到就退回心情那一档的颜色（`MoodLevel.tint`）。
    /// 🔴 不能在这里读盘取色：原来就是这一行在主线程上同步解原图，真机翻一页卡好几秒（2026-10-21）
    private var tint: Color {
        if let photo { return Color(uiColor: photo.tint) }
        if let first = photos.first, let known = EntryPhotoStore.knownTint(first) { return Color(uiColor: known) }
        if let level = entry.moodLevel { return level.tint }
        return themeManager.current.accent
    }

    /// 染色偏暗时用浅字，偏亮时用深字。
    /// **不能用主题的文字色** —— 那套色是给奶油底设计的，压在深蓝夜景染出的底上会糊成一片。
    private var onTintIsLight: Bool { UIColor(tint).isLightColor }
    private var titleColor: Color { onTintIsLight ? Color(white: 0.10) : .white }
    private var bodyColor: Color { onTintIsLight ? Color(white: 0.26) : Color(white: 0.94) }
    private var metaColor: Color { onTintIsLight ? Color(white: 0.40) : Color(white: 0.82) }

    /// 图文配比：字越多，照片让位越多；正文行数同步收紧，超出以 `…` 截断。
    private var layout: (imageRatio: CGFloat, textLines: Int) {
        switch preview.count {
        case 0:         return (0.86, 0)
        case 1..<40:    return (0.70, 3)
        case 40..<120:  return (0.60, 5)
        case 120..<240: return (0.52, 8)
        default:        return (0.46, 11)
        }
    }

    var body: some View {
        let imageHeight = size.height * layout.imageRatio

        ZStack(alignment: .top) {
            // 底色：页面底色垫底 + 主色。文字直接压在这层上，所以它必须够「实」，
            // 半透明到能看见页面底色时，文字就会像之前那样糊掉。
            // 原来垫的是毛玻璃（`.ultraThinMaterial`）：卡片后面只有纯色的页面，糊出来就是页面底色，
            // 但真机上每翻出一张新卡片都要建一层实时模糊，翻页掉帧（2026-10-21 测帧）—— 换成页面底色，看着一样
            ZStack {
                themeManager.current.background
                LinearGradient(
                    colors: [tint.opacity(0.72), tint.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack(spacing: 0) {
                cover(height: imageHeight)
                textArea
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
        )
        // 🔴 **卡片不加阴影，不要加回来。**
        //
        // 原先这里是 `.shadow(color: .black.opacity(0.18), radius: 20, y: 10)`。
        // 卡片外面包着分页的容器（原来是 `TabView(.page)`，现在是横向分页的 ScrollView，**一样会按自己的边框裁掉内容**），
        // 而卡片只比 TabView 小 16pt（上下各 8pt），阴影却往外扩了近 40pt ——
        // 于是阴影被一刀切成一个矩形，卡片所在那一整条比页面深一截，上下两条硬边肉眼可见。
        //
        // 2026-09-14 在模拟器里做过对照实验（开 / 关阴影逐像素比）：
        // 开阴影时色带内色差 Δ11、贴卡片边 Δ22，关掉后三个主题**全部 Δ0、硬边消失**。
        // 另外试过「阴影不变、卡片内缩 38pt」，仍然有硬边，还白白把卡片缩小了一圈。
        //
        // 真要加阴影，半径 + 偏移必须收在 8pt 边距以内（实测半径 6 / 不透明度 0.10 刚好不被切）。
        .animation(.easeInOut(duration: 0.6), value: photoIndex)
        .task { await loadFirstPhoto() }
        .onAppear { startRotationIfNeeded() }
        .onDisappear {
            rotationTask?.cancel()
            rotationTask = nil
            stopPlayback()
        }
    }

    // MARK: 封面

    @ViewBuilder
    private func cover(height: CGFloat) -> some View {
        ZStack {
            if photos.isEmpty {
                moodGradient
            } else if let photo {
                // 换下一张时新旧两张交叠淡入淡出（`.id` 换了就是另一张图）
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: height)
                    .clipped()
                    .id(photoIndex)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: height)
        .clipped()
        // 关键：用 mask 让照片下缘**溶解**进底色，而不是在上面盖一层渐变色块。
        // 盖色块会因为两侧不完全同色而留下一道可见的分界；溶解是直接露出同一张底，天然无缝。
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.70),
                    .init(color: .white.opacity(0.35), location: 0.90),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .topTrailing) {
            if photos.count > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<photos.count, id: \.self) { i in
                        Circle()
                            .fill(.white.opacity(i == photoIndex ? 0.95 : 0.4))
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.28), in: Capsule())
                .padding(14)
            }
        }
    }

    private var moodGradient: some View {
        let base = entry.moodLevel?.tint ?? themeManager.current.accent
        return LinearGradient(
            colors: [base.opacity(0.7), base.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: 文字区

    private var textArea: some View {
        let theme = themeManager.current
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if !entry.title.isEmpty {
                        Text(entry.title)
                            .font(theme.headingFont)
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                    }
                    HStack(spacing: 5) {
                        Text(entry.date.dayAndWeekday)
                            .font(theme.captionFont)
                            .foregroundStyle(metaColor)
                        if let level = entry.moodLevel {
                            Text(verbatim: "·").font(theme.captionFont).foregroundStyle(metaColor)
                            Text(level.title)
                                .font(theme.captionFont)
                                .foregroundStyle(metaColor)
                        }
                    }
                }

                Spacer(minLength: 0)

                if entry.hasAudio {
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(onTintIsLight ? .white : Color(white: 0.12))
                            .frame(width: 46, height: 46)
                            .background(titleColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if layout.textLines > 0, !preview.isEmpty {
                Text(preview)
                    .font(theme.bodyFont)
                    .foregroundStyle(bodyColor)
                    .lineSpacing(theme.bodyLineSpacing)
                    .lineLimit(layout.textLines)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            WeatherLocationBadge(
                weatherCode: entry.weatherCode,
                weatherInfo: entry.weatherInfo,
                locationInfo: entry.locationInfo,
                font: theme.labelFont,
                color: metaColor
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(width: size.width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: 轮播

    /// 第一张：后台解，解好淡入（解过的在 init 里就拿到了）
    private func loadFirstPhoto() async {
        guard let first = photos.first, photoIndex == 0 else { return }
        if photo != nil, EntryPhotoStore.cached(first, pixels: Self.photoPixels) == nil {
            // 先拿着别的尺寸顶着，正好的解好了再换
            if let loaded = await EntryPhotoStore.load(first, pixels: Self.photoPixels), photoIndex == 0 { photo = loaded }
            return
        }
        guard photo == nil, let loaded = await EntryPhotoStore.load(first, pixels: Self.photoPixels), photoIndex == 0 else { return }
        withAnimation(.easeOut(duration: 0.25)) { photo = loaded }
    }

    /// 多张照片轮播：下一张先在后台解好，再和这一张交叠换过去
    private func startRotationIfNeeded() {
        guard photos.count > 1, rotationTask == nil else { return }
        rotationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.rotationInterval)
                guard !Task.isCancelled else { return }
                let next = (photoIndex + 1) % photos.count
                guard let loaded = await EntryPhotoStore.load(photos[next], pixels: Self.photoPixels),
                      !Task.isCancelled else { continue }
                photoIndex = next
                photo = loaded
            }
        }
    }

    // MARK: 录音播放

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            guard let first = entry.audioURLs.first,
                  let p = AudioRecorderManager.playAudio(from: first) else { return }
            player = p
            p.play()
            isPlaying = true
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }
}

// MARK: - 明暗判定

extension UIColor {
    /// 感知亮度是否偏亮（决定压在这个颜色上的文字用深色还是浅色）。
    /// 用 ITU-R BT.601 加权，不是简单的 (r+g+b)/3 —— 人眼对绿最敏感、对蓝最迟钝，
    /// 平均值会把饱和的蓝判成「亮」，压上白字就看不清了。
    var isLightColor: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return true }
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
    }
}
