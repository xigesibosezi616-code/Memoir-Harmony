import SwiftUI
import SwiftData
import AVFoundation

/// 大屏展示模式 —— 一屏一篇日记，左右滑动翻篇。
///
/// 与列表模式的分工：列表用来**找**某一篇，大屏用来**重看**。所以这里放大照片、留白，
/// 让一篇日记像一张唱片封面那样被重新看见。
struct ShowcaseView: View {
    @Environment(ThemeManager.self) private var themeManager
    let entries: [JournalEntry]
    let onOpen: (JournalEntry) -> Void

    @State private var currentIndex = 0

    var body: some View {
        GeometryReader { geo in
            // 尺寸显式算好传下去：卡片内部任何一处都不再依赖「可用宽度」的推断，
            // 避免大图把布局撑破（会表现为卡片顶到屏幕边、圆角丢失）
            let cardSize = CGSize(
                width: max(0, geo.size.width - 36),
                height: max(0, geo.size.height - 16)
            )
            TabView(selection: $currentIndex) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    ShowcaseCard(entry: entry, size: cardSize)
                        .frame(width: geo.size.width, alignment: .center)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(entry) }
                        .tag(index)
                }
            }
            // 不显示底部页码点
            .tabViewStyle(.page(indexDisplayMode: .never))
            // 铺一层主题底色，防 UIPageViewController 自带系统底色露出来。
            // ⚠️ 这一行**不是**那条色差带的解药 —— 色差带的真凶是卡片阴影被 TabView 裁掉，
            // 已在 `ShowcaseCard` 里去掉阴影修复（2026-09-14，见那边的注释）。
            .background(themeManager.current.background)
        }
        .background(themeManager.current.background)
    }
}

// MARK: - 单篇卡片


private struct ShowcaseCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let entry: JournalEntry
    let size: CGSize

    @State private var photoIndex = 0
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var rotationTask: Task<Void, Never>?

    private static let rotationInterval: Duration = .seconds(4)
    private static let cornerRadius: CGFloat = 26

    private var photos: [String] { entry.showcasePhotoFilenames }

    /// 文字区的染色 —— 取自照片底部主色，取不到就退回心情色
    private var tint: Color {
        if photoIndex < photos.count,
           let image = PhotoPaperIO.loadCoverImage(photos[photoIndex]) {
            return DominantColor.extract(from: image, cacheKey: photos[photoIndex])
        }
        if let hex = entry.moodColorHex { return Color(hex: hex) }
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
        switch entry.textPreview.count {
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
            // 底色：毛玻璃 + 主色。文字直接压在这层上，所以它必须够「实」，
            // 半透明到能看见页面底色时，文字就会像之前那样糊掉。
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
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
        // 卡片外面包着 `TabView(.page)`，**TabView 会按自己的边框裁掉内容**，
        // 而卡片只比 TabView 小 16pt（上下各 8pt），阴影却往外扩了近 40pt ——
        // 于是阴影被一刀切成一个矩形，卡片所在那一整条比页面深一截，上下两条硬边肉眼可见。
        //
        // 2026-09-14 在模拟器里做过对照实验（开 / 关阴影逐像素比）：
        // 开阴影时色带内色差 Δ11、贴卡片边 Δ22，关掉后三个主题**全部 Δ0、硬边消失**。
        // 另外试过「阴影不变、卡片内缩 38pt」，仍然有硬边，还白白把卡片缩小了一圈。
        //
        // 真要加阴影，半径 + 偏移必须收在 8pt 边距以内（实测半径 6 / 不透明度 0.10 刚好不被切）。
        .animation(.easeInOut(duration: 0.6), value: photoIndex)
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
            } else {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, filename in
                    if let image = PhotoPaperIO.loadCoverImage(filename) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size.width, height: height)
                            .clipped()
                            .opacity(index == photoIndex ? 1 : 0)
                    }
                }
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
        let base = entry.moodColorHex.map { Color(hex: $0) } ?? themeManager.current.accent
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
                        if !entry.mood.isEmpty {
                            Text("·").font(theme.captionFont).foregroundStyle(metaColor)
                            Text(MoodTag.localizedName(for: entry.mood))
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

            if layout.textLines > 0, !entry.textPreview.isEmpty {
                Text(entry.textPreview)
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

    private func startRotationIfNeeded() {
        guard photos.count > 1, rotationTask == nil else { return }
        rotationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.rotationInterval)
                guard !Task.isCancelled else { return }
                photoIndex = (photoIndex + 1) % photos.count
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
