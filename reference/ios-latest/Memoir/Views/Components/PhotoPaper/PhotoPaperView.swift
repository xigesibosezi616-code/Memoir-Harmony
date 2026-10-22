import SwiftUI
import UIKit

/// 相纸包装器：根据 `ContentBlock.paperStyle` 分发到对应样式，
/// 应用固定倾斜角度（来自 `ContentBlock.rotationAngle`）以及按压反馈。
///
/// 阴影由各 `*Paper` 组件自行控制（不同样式阴影特征不同，避免叠加）。
///
/// **手势（2026-08-06 起）**：点击和长按**都是打开全屏查看**。
/// Live Photo 只在全屏页按住播放 —— 正文里的相纸太小，在那么一格里播没什么意思；
/// 照片的编辑操作（换边 / 换相纸 / 删除）也统一挪到了全屏页右上角的「⋯」，
/// 不再靠长按，省得用户去记「哪种照片长按会出什么」。
///
/// 当 `onReposition != nil` 时，启用**拖拽换位模式**（仅和纸主题）：
/// - 长按 0.4s → 中等震动 → 进入可拖动状态（scale 1.05 / 加深阴影 / 透明度 0.85）
/// - 原位置显示淡棕色虚线"松手放置在此"占位
/// - 拖动结束按触点全局 x 坐标：左半屏 → `.left`，右半屏 → `.right`
struct PhotoPaperView: View {
    let photo: ContentBlock

    /// 可选：传入已有 UIImage（用于相纸选择器预览，避免先写盘再读盘）
    var previewImage: UIImage? = nil

    var onTap: (() -> Void)? = nil
    /// 拖拽结束后吸附到新位置的回调；nil 时禁用拖拽模式
    var onReposition: ((PhotoPosition) -> Void)? = nil

    @State private var isPressed = false
    @State private var isPlayingLive = false
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        if onReposition != nil {
            dragModeBody
        } else {
            standardBody
        }
    }

    // MARK: - 普通模式（皮革 / 北欧等主题）

    private var standardBody: some View {
        paperView
            .rotationEffect(.degrees(photo.rotationAngle ?? 0))
            .scaleEffect(isPressed ? 1.04 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
            .contentShape(Rectangle())
            // 点击和长按都进全屏：正文里的相纸太小，Live Photo 在这么小一格里播没什么意思，
            // 放大了看才对得起它。照片的编辑操作也统一挪到了全屏页（右上角「⋯」）。
            .onTapGesture {
                onTap?()
            }
            .onLongPressGesture(
                minimumDuration: 0.4,
                perform: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onTap?()
                },
                onPressingChanged: { pressing in
                    isPressed = pressing
                }
            )
    }

    // MARK: - 拖拽换位模式（和纸主题）

    private var dragModeBody: some View {
        ZStack {
            // 原位置占位提示（仅拖拽进行时可见）
            if isDragging {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        Color(hex: "#B8AD9C"),
                        style: StrokeStyle(lineWidth: 1.2, dash: [5, 3])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "#F0EBE1").opacity(0.35))
                    )
                    .overlay(
                        Text("松手放置在此")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#8B7E6A"))
                    )
                    .transition(.opacity)
            }

            paperView
                .rotationEffect(.degrees(photo.rotationAngle ?? 0))
                .offset(x: dragOffset.width, y: dragOffset.height)
                .scaleEffect(isDragging ? 1.05 : 1.0)
                .opacity(isDragging ? 0.85 : 1.0)
                .shadow(
                    color: .black.opacity(isDragging ? 0.22 : 0),
                    radius: isDragging ? 12 : 0,
                    x: 0,
                    y: isDragging ? 6 : 0
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isDragging else { return }
            onTap?()
        }
        .gesture(dragReposGesture)
    }

    /// 长按 0.4s 后激活，随后手指拖动实时跟随；松手按全局 x 坐标吸附左右
    private var dragReposGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isDragging = true
                }
            }
            .sequenced(before: DragGesture(coordinateSpace: .global))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    dragOffset = drag.translation
                }
            }
            .onEnded { value in
                if case .second(true, let drag?) = value {
                    let screenMidX = UIScreen.main.bounds.width / 2
                    let newPosition: PhotoPosition = drag.location.x < screenMidX ? .left : .right
                    // 只在目标位置与当前不同时触发回调（避免无意义写库）
                    if newPosition != photo.position {
                        onReposition?(newPosition)
                    }
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    dragOffset = .zero
                    isDragging = false
                }
            }
    }

    @ViewBuilder
    private var paperView: some View {
        // loadImage 内部已带诊断 print 和内存缓存
        //
        // 🔴 **Live Photo 必须拿「未裁原图」来定容器比例，不能用裁过的方图。**
        //
        // 相机为宝丽来相纸把照片居中裁成了方形（`photoFilename`），
        // 但**六个相纸里只有宝丽来是固定方形**，其余五个都按 `photoAspect`
        // ——也就是这里传进去的 `uiImage` 的真实比例——来定容器。
        //
        // 配对成功时 `PHLivePhotoView` 显示的是**配对用的未裁原图**（3:4 竖图），
        // 若容器比例仍按方图算（≈1:1），竖图配上 `.fill` 就会被放大裁切，
        // 用户看到的是照片中间一小块（2026-09-05 实机反馈）。
        // 讽刺的是配对**失败**时走方图兜底反而是正常的。
        //
        // 所以这里统一取原图：比例、兜底显示、实际播放的画面三者才是同一张。
        // 宝丽来那一版仍会把它裁成方形，那是相纸自己的设计，不是 bug。
        let image = livePhotoSourceImage ?? previewImage ?? PhotoPaperIO.loadImage(photo.photoFilename)
        let liveOverlay = makeLiveOverlay()
        switch photo.paperStyle ?? .polaroid {
        case .original:       OriginalPhotoPaper(uiImage: image, livePhotoContent: liveOverlay)
        case .polaroid:       PolaroidPaper(uiImage: image, livePhotoContent: liveOverlay)
        case .washiSticker:   WashiStickerPaper(uiImage: image, livePhotoContent: liveOverlay)
        case .minimalCard:    MinimalCardPaper(uiImage: image, livePhotoContent: liveOverlay)
        case .filmFrame:      FilmFramePaper(uiImage: image, livePhotoContent: liveOverlay)
        case .letterAttached: LetterAttachedPaper(uiImage: image, livePhotoContent: liveOverlay)
        }
    }

    /// Live Photo 的**未裁原图** —— 用来定相纸容器的比例。
    /// 非 Live Photo（或缺原图的老数据）返回 nil，走原来的 `photoFilename`。
    private var livePhotoSourceImage: UIImage? {
        guard photo.isLivePhoto, previewImage == nil,
              let pairingStill = photo.pairingStillFilename else { return nil }
        return PhotoPaperIO.loadImage(pairingStill)
    }

    /// Live Photo 时构建 LivePhotoView 的 AnyView 包装；静态照片返回 nil。
    private func makeLiveOverlay() -> AnyView? {
        guard photo.isLivePhoto,
              let videoFilename = photo.livePhotoVideoFilename,
              let pairingStill = photo.pairingStillFilename,
              photo.photoFilename != nil else { return nil }
        let dir = PhotoPaperIO.photosDirectory
        return AnyView(
            LivePhotoView(
                // 配对与兜底显示**都用未裁原图**：容器比例已按它来算（见 `paperView`），
                // 兜底若换成方图，配对失败时反而会和容器比例对不上。
                staticImageURL: dir.appendingPathComponent(pairingStill),
                displayImageURL: dir.appendingPathComponent(pairingStill),
                videoURL: dir.appendingPathComponent(videoFilename),
                isPlaying: $isPlayingLive
            )
        )
    }
}
