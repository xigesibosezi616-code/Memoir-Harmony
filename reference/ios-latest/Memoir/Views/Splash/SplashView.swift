import SwiftUI
import UIKit

/// 启动页：按主题的封面 + 现写一个「m.」（2026-10-24 产品定，设计见 `Memoir/MEMOIR_SPLASH.md`）。
/// 封面（`SplashCoverPool`）只剩主题底色和底部的「from Sinara」，中间那个旧笔记本已经抹掉；
/// 桌面图标上那一笔手写的 m. 在封面中间一笔写出来、落下句点，配笔尖的「刷刷刷」和落点的「砰」，
/// 然后淡进主界面。字和颜色同桌面图标（`HandwrittenMark`、`ThemeSwatch`）。
///
/// 更早的「视频轮播开场」封存了两个月、视频文件早就没了，2026-10-24 连代码一起删掉。
///
/// ## 时间线
///
/// ```
///  封面   ├淡入┤
///  写字      ├─m 四笔 0.42s─┤抬笔┤点┤停┤
///  声音      刷   刷   刷  刷      咚
///  淡出                                 ├──淡出──┤
///  主界面                                ░░▒▒▓▓█
/// ```
///
/// 写字的每一段时长都在 `HandwrittenMark.Script`，声音按同一张表合成；从显示到进主界面约 1.2 秒（第一版 1.4 秒用户嫌慢；压到 1 秒后又嫌点完立刻进去，写完多停 0.2 秒）。
/// 系统开了「减弱动态效果」时不写、不出声，直接显示写好的字，停一下就进。
///
/// 两条兜底，任何一条不成立都不能把用户卡在开场：
/// 1. **当前主题没有封面图 / 图读不出来** → 立刻进 App（正常情况下 `MemoirApp` 那层就拦掉了）
/// 2. **用户点一下** → 立即跳过
struct SplashView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinish: () -> Void

    // MARK: - 时长

    /// 封面淡入时长（封面底色和底下垫的主题背景同色，淡入的其实只有「from Sinara」）
    static let coverFadeInDuration: TimeInterval = 0.2

    /// 封面出来多久后落第一笔。写字本身的节奏在 `HandwrittenMark.Script`
    static let writeDelay: TimeInterval = 0.06

    /// 不写字（减弱动态效果）时，写好的字停多久
    static let stillDuration: TimeInterval = 0.6

    /// 字的位置：放在原来笔记本的地方 —— 封面宽度的 44%，中心在封面高度的 45%（1257 / 2796）
    static let markWidth: CGFloat = 0.44
    static let markCenterY: CGFloat = 0.4496

    /// 写完、停够之后整层淡出的时长
    static let fadeOutDuration: TimeInterval = 0.25

    // MARK: - 状态

    @State private var coverImage: UIImage?
    /// 封面自身的透明度 —— **淡入只作用在图上**，底下的主题背景色始终不透明，
    /// 免得启动瞬间先闪一下白/黑再变成主题色。
    @State private var coverOpacity: Double = 0
    /// 落第一笔的时刻；nil = 还没开始写
    @State private var writingStart: Date?

    @State private var didFinish = false

    /// 整层的透明度。**淡出由这一层自己做**，做完才通知父视图把自己移除。
    ///
    /// 一开始是交给父视图的 `.transition(.opacity)` 处理的，实测**根本没有过渡帧** ——
    /// 录屏抽帧看到上一帧还是纯开场、下一帧已经是纯主界面，就是硬切。
    /// 与其去猜 SwiftUI 为什么不认那个 transition，不如把淡出握在自己手里：
    /// 等这一层已经完全透明了再移除，观感就不依赖任何外部行为。
    @State private var opacity: Double = 1

    var body: some View {
        ZStack {
            // 封面解码出来之前垫住画面，避免闪一下白屏。
            // 图片自身的底色应与主题背景一致 —— `.scaledToFit` 的留白处露的就是这一层。
            themeManager.current.background
                .ignoresSafeArea()

            if let coverImage {
                    GeometryReader { geo in
                        let cover = Self.fittedRect(coverImage.size, in: geo.size)
                        ZStack {
                            Image(uiImage: coverImage)
                                .resizable()
                                // 🔴 用 `fit` 而不是 `fill`：封面底部有 Sinara 标识，
                                // `fill` 在比例不同的机型上会把它裁掉。`fit` 的留白由
                                // 底下那层主题背景补齐，而图片底色与它一致 —— 看不出接缝。
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .opacity(coverOpacity)
                            // 字跟着封面走（不跟屏幕），比例不同的机型上也落在原来笔记本的位置
                            HandwritingView(ink: ThemeSwatch.colors(for: themeManager.currentThemeID).ink,
                                            start: writingStart,
                                            animated: !reduceMotion)
                                .frame(width: cover.width * Self.markWidth)
                                .position(x: cover.midX, y: cover.minY + cover.height * Self.markCenterY)
                        }
                    }
                    .ignoresSafeArea()
            }
        }
        .opacity(opacity)
        // 点任意处跳过
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await runCover() }
    }

    // MARK: - 封面 + 写字

    private func runCover() async {
        guard let url = SplashCoverPool.coverForCurrentTheme,
              let image = await Self.loadImage(at: url) else {
            // 当前主题没配封面：直接进 App，别让用户对着一块纯色背景发呆
            finish()
            return
        }
        coverImage = image
        if !reduceMotion { SplashSound.prepare() }
        withAnimation(.easeOut(duration: Self.coverFadeInDuration)) {
            coverOpacity = 1
        }
        guard !reduceMotion else {
            writingStart = Date()
            try? await Task.sleep(for: .seconds(Self.stillDuration))
            finish()
            return
        }
        try? await Task.sleep(for: .seconds(Self.writeDelay))
        guard !didFinish else { return }
        writingStart = Date()
        SplashSound.play()
        try? await Task.sleep(for: .seconds(HandwrittenMark.Script.total))
        finish()
    }

    /// 封面 `.scaledToFit` 之后实际占的框
    private static func fittedRect(_ image: CGSize, in bounds: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: bounds) }
        let scale = min(bounds.width / image.width, bounds.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// 在后台线程解码，别把启动的主线程堵住。
    private static func loadImage(at url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
    }

    // MARK: - 退场

    /// 到点淡出 / 点击跳过都走这里，`didFinish` 保证只生效一次。
    /// **先把自己淡掉，淡完了再通知父视图移除**；声音跟着一起淡掉
    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        withAnimation(.easeInOut(duration: Self.fadeOutDuration)) {
            opacity = 0
        }
        SplashSound.fadeOut(Self.fadeOutDuration)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.fadeOutDuration))
            SplashSound.release()
            onFinish()
        }
    }
}
