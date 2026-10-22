import SwiftUI
import UIKit

/// 嵌入照片的全屏查看器：
/// - 点击任意处或拖下关闭
/// - 支持双指缩放（0.9x–4x）
/// - Live Photo 可按住播放（与正文里的手势一致）
struct PhotoFullScreenView: View {
    let photo: ContentBlock
    let onDismiss: () -> Void

    /// 照片编辑动作。全部可选 —— 写日记页只是预览，不给编辑入口。
    var onTogglePosition: (() -> Void)? = nil
    var onChangeStyle: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var dragOffsetY: CGFloat = 0
    @State private var isPlayingLive = false
    @State private var showDeleteConfirm = false

    private var hasEditActions: Bool {
        onTogglePosition != nil || onChangeStyle != nil || onDelete != nil
    }

    private var uiImage: UIImage? { PhotoPaperIO.loadImage(photo.photoFilename) }

    /// Live Photo 的两个文件都在时才走 Live 分支；`LivePhotoView` 自己会兜底成静态图。
    /// 全屏下兜底也用未裁原图 —— 这里本就该看到完整的一张，不是相纸里的方图。
    private var liveURLs: (still: URL, video: URL)? {
        guard let still = photo.pairingStillFilename, let video = photo.livePhotoVideoFilename else { return nil }
        let dir = PhotoPaperIO.photosDirectory
        return (dir.appendingPathComponent(still), dir.appendingPathComponent(video))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let liveURLs {
                LivePhotoView(
                    staticImageURL: liveURLs.still,
                    videoURL: liveURLs.video,
                    isPlaying: $isPlayingLive,
                    contentMode: .fit
                )
                .scaleEffect(scale)
                .offset(y: dragOffsetY)
                .gesture(zoomGesture)
                // 按住播放；松手停。与正文里 PhotoPaperView 的手势保持一致。
                .onLongPressGesture(
                    minimumDuration: 0.2,
                    perform: {},
                    onPressingChanged: { isPlayingLive = $0 }
                )
            } else if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    // 下拉关闭手势的位移
                    .offset(y: dragOffsetY)
                    .gesture(zoomGesture)
            } else {
                Text("照片加载失败")
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.system(size: 14))
            }
        }
        // 下拉关闭（图片未放大时生效）
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if scale <= 1.01, value.translation.height > 0 {
                        dragOffsetY = value.translation.height
                    }
                }
                .onEnded { value in
                    if scale <= 1.01, value.translation.height > 120 {
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffsetY = 0
                        }
                    }
                }
        )
        .onTapGesture {
            if scale > 1.01 {
                // 放大后点击：复位
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    scale = 1.0
                    lastScale = 1.0
                }
            } else {
                onDismiss()
            }
        }
        .overlay(alignment: .topTrailing) {
            if hasEditActions {
                editMenu
            }
        }
        .confirmationDialog("删除这张照片？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除照片", role: .destructive) {
                onDelete?()
                onDismiss()
            }
            Button("取消", role: .cancel) {}
        }
        .statusBar(hidden: true)
    }

    /// 照片编辑入口。原来挂在正文里长按 —— 现在长按用来放大，编辑就集中到这里，
    /// 所有照片一个入口，不用记「哪种照片长按会出什么」。
    private var editMenu: some View {
        Menu {
            if let onTogglePosition {
                Button(photo.position == .right ? "移到左侧" : "移到右侧", systemImage: "arrow.left.arrow.right") {
                    onTogglePosition()
                    onDismiss()
                }
            }
            if let onChangeStyle {
                Button("更换相纸样式", systemImage: "square.on.square") {
                    onChangeStyle()
                    onDismiss()
                }
            }
            if onDelete != nil {
                Button("删除照片", systemImage: "trash", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.35), in: Circle())
        }
        .padding(.top, 16)
        .padding(.trailing, 16)
    }

    /// 双指缩放（0.9x–4x），松手时若小于原始大小则弹回
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(4.0, max(0.9, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.0 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        scale = 1.0
                        lastScale = 1.0
                    }
                }
            }
    }
}
