import SwiftUI
import AVFoundation
import UIKit

/// 启动页。**当前用的是按主题的静态封面**（`SplashCoverPool`）。
///
/// 视频轮播那套（`SplashVideoPool` + `SplashVideoPlayerView`）**已封存但没有删** ——
/// 把 `style` 改回 `.video` 就能整套复活，详见 `Style` 的注释与
/// `Memoir/MEMOIR_DEV_SPEC.md` 的「已封存的功能」一节。
///
/// ## 时间线（封面模式）
///
/// ```
///  封面   ├──淡入──┤────停留────┤
///  淡出                      ├──淡出──┤
///  主界面                     ░░▒▒▓▓█
/// ```
///
/// `coverDuration`（0.7s）是**从开始淡入到开始淡出**的总时长 —— 也就是用户说的
/// 「0.7 秒的启动画面」。淡出的 `fadeOutDuration` 叠在它后面，不算在 0.7 秒里。
///
/// 两条兜底，任何一条不成立都不能把用户卡在开场：
/// 1. **当前主题没有封面图 / 图读不出来** → 立刻进 App（正常情况下 `MemoirApp` 那层就拦掉了）
/// 2. **用户点一下** → 立即跳过
struct SplashView: View {
    @Environment(ThemeManager.self) private var themeManager

    let onFinish: () -> Void

    // MARK: - 开场样式（feature toggle）

    /// 开场用哪种素材。
    ///
    /// 🔒 **`.video` 是已封存的实现，当前不启用。**
    /// 代码整套保留且**参与编译**（不是注释掉的死代码）——
    /// 这样重构、改 API、升 SDK 时它会跟着一起被修，解封时不会已经烂掉。
    /// 解封只需把 `style` 改成 `.video` 并把视频放回 `Resources/SplashVideos/`。
    enum Style {
        /// 按主题的静态封面（当前启用）
        case cover
        /// 视频轮播池（🔒 已封存，见 `SplashVideoPool`）
        case video
    }

    /// 🔴 改这一行即可切换开场形态。
    static let style: Style = .cover

    // MARK: - 时长

    /// 封面淡入时长
    static let coverFadeInDuration: TimeInterval = 0.25

    /// **「0.7 秒的启动画面」就是这个数** —— 从开始淡入到开始淡出的总时长。
    /// 觉得长了短了直接改这里，其余不用动。
    static let coverDuration: TimeInterval = 0.7

    /// 淡出时长。封面模式下接在 `coverDuration` 之后；
    /// 视频模式下它同时是**提前量**（视频还剩这么久时就开始淡出，两者必须相等）。
    static let fadeOutDuration: TimeInterval = 0.3

    /// 读不到视频时长时的硬兜底。**仅视频模式用得到**。
    private static let fallbackTimeout: TimeInterval = 20

    // MARK: - 状态

    @State private var coverImage: UIImage?
    /// 封面自身的透明度 —— **淡入只作用在图上**，底下的主题背景色始终不透明，
    /// 免得启动瞬间先闪一下白/黑再变成主题色。
    @State private var coverOpacity: Double = 0

    @State private var videoURL: URL?
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

            switch Self.style {
            case .cover:
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        // 🔴 用 `fit` 而不是 `fill`：封面底部有 Sinara 标识，
                        // `fill` 在比例不同的机型上会把它裁掉。`fit` 的留白由
                        // 底下那层主题背景补齐，而图片底色与它一致 —— 看不出接缝。
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .opacity(coverOpacity)
                }
            case .video:
                if let videoURL {
                    // 播放结束通知在这里只当兜底：正常路径下计时器会先在
                    // "还剩 fadeOutDuration"时就触发退场，轮不到它
                    SplashVideoPlayerView(url: videoURL, onFinish: finish)
                        .ignoresSafeArea()
                }
            }
        }
        .opacity(opacity)
        // 点任意处跳过
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task {
            switch Self.style {
            case .cover: await runCover()
            case .video: await runVideo()
            }
        }
    }

    // MARK: - 封面模式（当前启用）

    private func runCover() async {
        guard let url = SplashCoverPool.coverForCurrentTheme,
              let image = await Self.loadImage(at: url) else {
            // 当前主题没配封面：直接进 App，别让用户对着一块纯色背景发呆
            finish()
            return
        }
        coverImage = image
        withAnimation(.easeOut(duration: Self.coverFadeInDuration)) {
            coverOpacity = 1
        }
        try? await Task.sleep(for: .seconds(Self.coverDuration))
        finish()
    }

    /// 在后台线程解码，别把启动的主线程堵住。
    private static func loadImage(at url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
    }

    // MARK: - 视频模式（🔒 已封存，保留可编译）

    private func runVideo() async {
        guard let picked = SplashVideoPool.videoForToday() else {
            finish()
            return
        }
        videoURL = picked

        guard let duration = await Self.duration(of: picked) else {
            // 读不到时长：退回"等播放结束通知"，同时留一个硬超时防止永远卡住。
            // 这条留着 —— 走到这里用户要对着开场干等 20 秒，属于必须能查到的失败。
            NSLog("🔴[Boot] 读不到视频时长（%@），退回 %.0f 秒硬超时",
                  picked.lastPathComponent, Self.fallbackTimeout)
            try? await Task.sleep(for: .seconds(Self.fallbackTimeout))
            finish()
            return
        }

        // 提前 fadeOutDuration 开始退场，让淡出叠在视频的尾巴上。
        // 视频本身不会被打断 —— 淡出期间播放器还在播，
        // 直到过渡动画结束、这一层被真正移除时才停（见 SplashVideoPlayerView.dismantleUIView）。
        let playBeforeFade = max(0, duration - Self.fadeOutDuration)
        try? await Task.sleep(for: .seconds(playBeforeFade))
        finish()
    }

    /// 视频实际时长；读不到（或不是有效数值）返回 nil。
    private static func duration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    // MARK: - 退场

    /// 到点淡出 / 播放结束兜底 / 点击跳过都走这里，`didFinish` 保证只生效一次。
    ///
    /// **先把自己淡掉，淡完了再通知父视图移除**。视频模式下播放器要等这一层
    /// 真正被移除时才停（见 `SplashVideoPlayerView.dismantleUIView`）。
    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        withAnimation(.easeInOut(duration: Self.fadeOutDuration)) {
            opacity = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.fadeOutDuration))
            onFinish()
        }
    }
}
