import SwiftUI
import PhotosUI

/// 正文里的 Live Photo。
///
/// **最重要的一条约定：这个 View 永远不会渲染成空白。**
///
/// 6 个相纸组件都是 `if let livePhotoContent { ... } else if let uiImage { ... }` 的结构 ——
/// 只要是 Live Photo，静态图那条分支就永远走不到。所以一旦 `PHLivePhoto` 配对失败，
/// 光秃秃的 `PHLivePhotoView`（`livePhoto == nil`）就会渲染成**一片空白**，
/// 用户看到的是「照片没了，只剩一个删除按钮」。2026-08-02 陈总反馈的就是这个。
///
/// 因此兜底放在这里而不是外面：加载中、配对失败、文件损坏 —— 一律退回静态图。
/// 退化成一张不会动的照片是可以接受的，凭空消失不行。
struct LivePhotoView: View {
    /// 与 .mov 配对用的静态图。相机拍的是**未裁原图**，相册选的就是原始字节。
    let staticImageURL: URL
    /// 配对失败时用来兜底显示的图。正文里应传**裁过的方图**，才和相纸尺寸一致。
    /// 不传则退回用 `staticImageURL`。
    var displayImageURL: URL? = nil
    let videoURL: URL
    @Binding var isPlaying: Bool
    /// 正文相纸里要填满方框（`.fill`）；全屏查看要完整看到整张（`.fit`）
    var contentMode: ContentMode = .fill

    @State private var livePhoto: PHLivePhoto?

    var body: some View {
        // 刻意**不加 LIVE 角标**（2026-08-06 决策）：相纸是「实体照片」的隐喻，
        // 贴一个 iOS 风格的标签就破功了；而且预告了的惊喜就不是惊喜 ——
        // live 静静存着，用户哪天长按了自己发现，才是这个功能该有的样子。
        // 🔴 **布局尺寸永远由静态图决定，播放器只是叠上去填满。**
        //
        // 之前是 `if let livePhoto { 播放器 } else { 静态图 }` 二选一。
        // 问题在于 `PHLivePhotoView` 是 `UIViewRepresentable`，**没有固有内容尺寸**
        // （intrinsic content size）—— SwiftUI 问它「你的理想尺寸是多少」它不回答，
        // 于是变成**贪婪视图（greedy view）**：吃掉父容器给的一切空间，
        // 还让外层的 `.aspectRatio` 失去参照。
        //
        // 表现就是：配对**失败**时正常（走静态图，有固有尺寸），
        // 配对**成功**时整个相纸尺寸失控 —— 照片铺满屏幕还塞不下，
        // 连固定尺寸的相框都被撑破（2026-09-05 实机反馈）。
        //
        // 曾试过把静态图的比例读出来喂给 `.aspectRatio`，但那依赖读取成功；
        // 读不到（文件缺失、元数据异常）就退回原样失控。
        // 现在改成**静态图常驻打底**：它有固有尺寸，永远负责撑出正确的布局，
        // 播放器盖在它上面填满同一块区域。尺寸再也不依赖任何一次读取是否成功。
        ZStack {
            staticFallback

            if let livePhoto {
                LivePhotoPlayer(livePhoto: livePhoto, isPlaying: $isPlaying, contentMode: contentMode)
            }
        }
        .task(id: staticImageURL) {
            await load()
        }
    }

    // MARK: - 兜底静态图

    @ViewBuilder
    private var staticFallback: some View {
        if let image = UIImage(contentsOfFile: (displayImageURL ?? staticImageURL).path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            PhotoPaperPlaceholder()
        }
    }

    // MARK: - 加载

    private func load() async {
        let still = staticImageURL
        let video = videoURL
        let resolved: PHLivePhoto? = await withCheckedContinuation { cont in
            var resumed = false
            PHLivePhoto.request(
                withResourceFileURLs: [still, video],
                placeholderImage: nil,
                targetSize: .zero,
                contentMode: .aspectFill
            ) { livePhoto, info in
                // 这个回调可能被调用多次（先降级版本、后完整版本）。
                // 拿到非降级结果、或明确失败时才收口，且只收一次。
                let isDegraded = (info[PHLivePhotoInfoIsDegradedKey] as? Bool) ?? false
                guard !isDegraded, !resumed else { return }
                resumed = true
                cont.resume(returning: livePhoto)
            }
        }

        if resolved == nil {
            // 这个失败**不抛错、不报警**，只是安静地回 nil —— 不打出来就永远查不到。
            // 最常见的原因是静态图被重编码过、丢了 Apple maker note 里的 content identifier
            // （详见 `LivePhotoAssets` 注释）。旧版本存下来的 Live Photo 都属于这种，
            // 它们会一直配对失败，靠上面的静态图兜底显示。
            print("🔴 [LivePhoto] 配对失败，退回静态图显示。still=\(still.lastPathComponent) video=\(video.lastPathComponent)")
        }
        livePhoto = resolved
    }
}

// MARK: - PHLivePhotoView 包装

/// 只负责播放一个**已经加载好**的 `PHLivePhoto`。
/// 加载与失败兜底都在 `LivePhotoView` 里做完了，这里拿到的一定是有效值。
private struct LivePhotoPlayer: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    @Binding var isPlaying: Bool
    let contentMode: ContentMode

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
        view.clipsToBounds = true
        view.delegate = context.coordinator
        view.livePhoto = livePhoto
        // 装上照片后它的固有尺寸 = 照片像素尺寸。抗压缩优先级降到最低，
        // 万一哪天 sizeThatFits 没生效，也不会顶着固有尺寸不肯缩
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            view.setContentCompressionResistancePriority(.defaultLow, for: axis)
            view.setContentHuggingPriority(.defaultLow, for: axis)
        }
        return view
    }

    /// 🔴 **给多大就是多大，绝不报自己的固有尺寸。**
    ///
    /// 不实现这个的话，SwiftUI 会拿 `PHLivePhotoView` 的固有尺寸（= 照片像素尺寸，几千 pt）
    /// 当成它想要的大小，详情页里的照片格就被撑满屏幕（2026-10-09 真机，见 `PhotoPaperImageArea`）。
    /// 没给尺寸的方向报 0：布局尺寸一律由下面那层静态图决定，播放器只负责盖在上面。
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PHLivePhotoView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        if uiView.livePhoto !== livePhoto {
            uiView.livePhoto = livePhoto
        }
        // 只在状态真的翻转时动播放器：SwiftUI 会反复调 updateUIView，
        // 每次都 startPlayback 会把动画不断重启，看起来就是抽搐。
        guard isPlaying != context.coordinator.isPlayingNow else { return }
        context.coordinator.isPlayingNow = isPlaying
        if isPlaying {
            uiView.startPlayback(with: .full)
        } else {
            // 原来只有 start 没有 stop —— 松开手指后会一直播到片尾，与「按住才播」的设计不符
            uiView.stopPlayback()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(isPlaying: $isPlaying) }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        private let isPlaying: Binding<Bool>
        /// 播放器当前的实际状态，用来把 `updateUIView` 的重复调用滤掉
        var isPlayingNow = false

        init(isPlaying: Binding<Bool>) { self.isPlaying = isPlaying }

        func livePhotoView(
            _ livePhotoView: PHLivePhotoView,
            didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle
        ) {
            isPlayingNow = false
            Task { @MainActor in
                isPlaying.wrappedValue = false
            }
        }
    }
}
