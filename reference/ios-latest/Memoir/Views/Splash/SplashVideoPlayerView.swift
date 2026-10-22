import SwiftUI
import AVFoundation

/// 铺满全屏播放一条启动视频，播完回调。
///
/// 用 `AVPlayerLayer` 而不是 SwiftUI 的 `VideoPlayer`：后者自带播放控件和手势，
/// 启动页要的是一段纯画面，不该出现进度条和音量键。
///
/// 🔇 **静音播放，而且绝不打断用户正在听的音乐/播客。**
///
/// ⚠️ 这里有个反直觉的坑，踩过一次：**光把 player 静音是不够的**。
/// iOS 的默认 audio session category 是 `.soloAmbient` —— 顾名思义"独占"，
/// 只要 App 有音频活动就会中断别的 App，**跟播的内容静不静音无关**。
/// `AVPlayer` 起播时会隐式激活 session，于是用户的歌被掐掉；
/// 开场放完 player 释放、session 隐式停用，歌又自己回来了 ——
/// 「一打开尺素音乐就停，进主页又继续」正是这么来的。
///
/// 所以必须显式把 category 换成 `.ambient`（"背景"语义：与其他音频**混合**，不抢占），
/// 开场结束后再放回默认，别让这一层的临时设置影响到之后播放日记录音的行为。
struct SplashVideoPlayerView: UIViewRepresentable {
    let url: URL
    /// 视频自然播放结束时回调（超时由外层另行处理）
    let onFinish: () -> Void

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .clear

        // 必须赶在 player 起播**之前**设好 —— 起播那一刻 session 就被隐式激活了
        Self.allowMixingWithOtherAudio()

        let player = AVPlayer(url: url)
        player.isMuted = true
        // 播完停在最后一帧，别自动回到第一帧闪一下
        player.actionAtItemEnd = .pause
        view.playerLayer.player = player
        // 铺满：启动页不能出现黑边，宁可裁掉边缘
        view.playerLayer.videoGravity = .resizeAspectFill

        context.coordinator.observe(player: player, onFinish: onFinish)
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
        uiView.playerLayer.player = nil
        // ⚠️ **这里绝对不要"还原"成 `.soloAmbient`**。
        //
        // 曾经这么干过，结果是：开场没打断音乐，但**一进主页音乐就断、而且再也不恢复**。
        // 原因是此刻 session 还是激活状态（`AVPlayer` 起播时隐式激活的），
        // 把 category 改成独占的 `.soloAmbient` 会**立即生效**把别人踢掉；
        // 我们又没有 deactivate，别的 App 收不到"中断结束"的通知，于是不会自己恢复。
        //
        // 正确的做法是各用各的：需要音频的地方在**自己用的时候**声明自己要的 category
        // （`AudioRecorderManager` 录音设 `.playAndRecord`、播放设 `.soloAmbient`），
        // 而不是让开场这一层去猜后面的人想要什么、还得负责收拾。
    }

    // MARK: - Audio session

    /// 允许与其他 App 的音频**混合**，不抢占。
    ///
    /// 只改 category，**不调 `setActive(true)`** —— 激活留给 `AVPlayer` 起播时隐式完成，
    /// 我们要做的只是保证它激活时用的是"不抢占"的那一套规则。
    private static func allowMixingWithOtherAudio() {
        try? AVAudioSession.sharedInstance()
            .setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var endObserver: NSObjectProtocol?

        func observe(player: AVPlayer, onFinish: @escaping () -> Void) {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                onFinish()
            }
        }

        deinit {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
        }
    }

    /// 让 `AVPlayerLayer` 跟着 view 的 bounds 走。
    /// 不自己管这件事的话，旋转或 safe area 变化时视频不会重新铺满。
    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
