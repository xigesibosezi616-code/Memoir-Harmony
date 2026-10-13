import SwiftUI
import PhotosUI

/// 往正文里加照片从哪来
enum PhotoInsertSource: Identifiable {
    case camera
    case library
    var id: Self { self }
}

/// 写日记页、编辑页共用的「加一张照片」流程：
/// 尺素相机 / 系统相册 → 选相纸 → 照片（和 Live Photo 的视频）落盘 → 交出一个照片块。
/// 也管「给已经插进去的照片换相纸」。
///
/// 2026-10 图文编辑器之前，这一套只在写日记页里有；编辑页加不了照片，要回详情页长按「在此处插入照片」。
/// 详情页那个入口拿掉之后，两页都要能加，所以抽到这里
struct PhotoInsertFlow: ViewModifier {
    /// 设成 `.camera` / `.library` 就开始；流程结束自动回到 nil
    @Binding var source: PhotoInsertSource?
    /// 设成某张照片就弹相纸选择，换完回到 nil
    @Binding var restyling: ContentBlock?
    let theme: any AppTheme
    /// 新照片落好盘了，插到正文里
    let onInsert: (ContentBlock) -> Void
    /// 换好相纸的照片
    let onRestyle: (ContentBlock) -> Void
    /// 这次落盘的文件名（照片、Live Photo 的视频与原图）。调用方据此在放弃或删掉照片时清理
    let onFilesCreated: ([String]) -> Void

    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var showStylePicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    /// 相册里选中的是 Live Photo 时，它的静态图 + 视频原始字节；普通照片为 nil
    @State private var pendingLiveAssets: LivePhotoAssets?
    @State private var restyleImage: UIImage?

    func body(content: Content) -> some View {
        content
            .onChange(of: source) { _, newValue in
                switch newValue {
                case .library:
                    showLibrary = true
                case .camera:
                    // 禁掉系统 fullScreenCover 的上滑转场：相机自己有「从灵动岛长出来」的开场动画，
                    // 两段动画叠加会互相打架
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { showCamera = true }
                case nil:
                    break
                }
            }
            .onChange(of: restyling?.id) { _, id in
                guard id != nil, let photo = restyling else { return }
                restyleImage = PhotoPaperIO.loadImage(photo.photoFilename)
                if restyleImage == nil {
                    restyling = nil
                } else {
                    showStylePicker = true
                }
            }
            // 系统相册（含 Live Photo → 显示 LIVE 角标且可取视频部分）
            .photosPicker(isPresented: $showLibrary, selection: $pickerItem,
                          matching: .any(of: [.images, .livePhotos]), photoLibrary: .shared())
            .onChange(of: showLibrary) { _, showing in
                // 没选就关了相册
                if !showing, pickerItem == nil, pendingImage == nil { source = nil }
            }
            .onChange(of: pickerItem) { _, item in handlePicked(item) }
            // 尺素相机：相纸在相机里就选好了，拍完直接插
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if pendingImage == nil { source = nil }
            }) {
                PaperCameraView { shot, cropped, style in
                    showCamera = false
                    insert(image: cropped, style: style, cameraShot: shot)
                }
            }
            // 相纸样式：新照片选相纸，或给已有照片换相纸
            .sheet(isPresented: $showStylePicker, onDismiss: finish) {
                if let image = pendingImage ?? restyleImage {
                    PaperStylePickerView(
                        image: image,
                        theme: theme,
                        onSelect: { style in
                            if let photo = restyling {
                                var updated = photo
                                updated.paperStyle = style
                                onRestyle(updated)
                            } else {
                                insert(image: image, style: style, cameraShot: nil)
                            }
                            showStylePicker = false
                        },
                        onCancel: { showStylePicker = false }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
    }

    private func handlePicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    pickerItem = nil
                    finish()
                }
                return
            }
            // 尝试拿 Live Photo 素材（走 PHAsset + PHAssetResourceManager；普通照片返回 nil）
            let live = await LivePhotoExtractor.extractLivePhoto(from: item)
            await MainActor.run {
                pendingImage = image
                pendingLiveAssets = live
                pickerItem = nil
                showLibrary = false
            }
            // 先关相册，等 dismiss 动画跑完再开相纸 sheet（两个 presentation 同屏会冲突）
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run { showStylePicker = true }
        }
    }

    /// 落盘并交出照片块。`cameraShot` 非 nil 表示来自尺素相机（`image` 是裁过的方图）。
    ///
    /// Live Photo 的静态图必须**原样落盘**：走 UIImage 重编码会丢掉 Apple maker note 里的
    /// content identifier，PHLivePhoto 就再也配不上这一对（详见 `LivePhotoAssets` 注释）。
    /// 普通照片才走 JPEG 重编码（省空间，且没有要保的元数据）
    private func insert(image: UIImage, style: PaperStyle, cameraShot: CameraShot?) {
        let base = "photo_\(UUID().uuidString.prefix(8))"
        let filename: String
        var videoName: String?
        var stillName: String?

        if let shot = cameraShot {
            // 尺素相机：显示用裁过的方图，配对用未裁的原图 —— 两份都要留
            filename = "\(base).jpg"
            guard PhotoPaperIO.saveImage(image, filename: filename) else { return failed() }
            if let movieURL = shot.movieURL, let movie = try? Data(contentsOf: movieURL) {
                let still = "\(base)_full.jpg"
                let video = "\(base).mov"
                if PhotoPaperIO.saveData(shot.stillData, filename: still),
                   PhotoPaperIO.saveData(movie, filename: video) {
                    stillName = still
                    videoName = video
                } else {
                    NSLog("🔴 [LivePhoto] 相机 Live Photo 落盘失败，按普通照片处理")
                }
            }
            // 拍下就存：相机拍的一律往相册留一份完整的，失败不影响日记
            Task.detached(priority: .utility) { [stillData = shot.stillData, movieURL = shot.movieURL] in
                await PhotoLibrarySaver.saveCameraShot(stillData: stillData, movieURL: movieURL)
                if let movieURL { try? FileManager.default.removeItem(at: movieURL) }
            }
        } else if let live = pendingLiveAssets {
            filename = "\(base).\(live.stillExtension)"
            guard PhotoPaperIO.saveData(live.stillData, filename: filename) else { return failed() }
            let video = "\(base).mov"
            if PhotoPaperIO.saveData(live.videoData, filename: video) {
                videoName = video
            } else {
                // 视频没存下就退化成普通照片 —— 总比留一个点了不播的假 Live Photo 好
                NSLog("🔴 [LivePhoto] 视频保存失败，按普通照片处理")
            }
        } else {
            filename = "\(base).jpg"
            guard PhotoPaperIO.saveImage(image, filename: filename) else { return failed() }
        }

        var photo = ContentBlock(photoFilename: filename, livePhotoVideoFilename: videoName,
                                 position: .right, paperStyle: style)
        photo.livePhotoStillFilename = stillName
        onFilesCreated([filename, videoName, stillName].compactMap { $0 })
        onInsert(photo)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        finish()
    }

    private func failed() {
        NSLog("🔴 [PhotoInsert] 照片落盘失败")
        finish()
    }

    private func finish() {
        pendingImage = nil
        pendingLiveAssets = nil
        restyleImage = nil
        restyling = nil
        source = nil
    }
}

extension View {
    func photoInsertFlow(
        source: Binding<PhotoInsertSource?>,
        restyling: Binding<ContentBlock?>,
        theme: any AppTheme,
        onInsert: @escaping (ContentBlock) -> Void,
        onRestyle: @escaping (ContentBlock) -> Void,
        onFilesCreated: @escaping ([String]) -> Void
    ) -> some View {
        modifier(PhotoInsertFlow(source: source, restyling: restyling, theme: theme,
                                 onInsert: onInsert, onRestyle: onRestyle, onFilesCreated: onFilesCreated))
    }
}
