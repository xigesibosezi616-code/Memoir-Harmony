import AVFoundation
import ImageIO
import UIKit

/// 相机会话封装（AVFoundation）。
///
/// **为什么不用 `UIImagePickerController`**：系统相机是全屏接管的，无法在其上叠加
/// 自定义取景框，做不了「灵动岛相机」的视觉。这里自建会话，但成像走系统默认管线
/// —— 不加滤镜、不做后期，等同原相机直出。
///
/// 整个类 `nonisolated`：配置 / 启停 / 拍照都在自己的串行队列执行，不占主线程；
/// 结果通过回调抛回主线程交给 View。
/// 一次拍照的产物。
///
/// ⚠️ `stillData` 是**未裁剪、元数据完整**的原始字节，别拿裁过的 UIImage 顶替它：
/// Live Photo 靠静态图 Apple maker note 里的 content identifier 与 .mov 配对，
/// 走一遍 `UIImage` 就会把那段元数据丢掉，配对永远失败（详见 `LivePhotoAssets` 注释）。
/// 方形裁切只用于**显示**，配对和存进相册都用这份原始字节。
struct CameraShot: Sendable {
    let stillData: Data
    /// 成对视频的临时文件 URL；不是 Live Photo（或采集失败）时为 nil
    let movieURL: URL?

    var isLivePhoto: Bool { movieURL != nil }
}

/// 照片本身先好了（Live Photo 的那段视频还在写）：原始字节 + 一张显示用的小方图
struct CapturedPhoto: Sendable {
    let stillData: Data
    /// 已转正、居中裁方、缩到长边 `ShotImage.previewSide`，取景框里立刻显示用
    let preview: UIImage
}

nonisolated final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.sinaratech.memoir.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back

    /// 闪光灯模式。**存在这里而不是每次拍照现读 UI**，因为 `capture` 跑在 `queue` 上，
    /// 不该去碰主线程的状态。UI 改动通过 `setFlash` 推进来。
    ///
    /// ⚠️ 只是「意向」——实际能不能闪由设备决定（前摄多数没有闪光灯，
    /// 系统会自动退化成屏幕补光或直接忽略）。所以 UI 侧要用 `isFlashAvailable` 决定显不显示这个按钮。
    private var flashMode: AVCaptureDevice.FlashMode = .auto
    /// 拍照 delegate：`AVCapturePhotoOutput` 只弱引用它，得自己攥着直到这一张的回调全部结束。
    /// 按 `uniqueID` 存：拍完马上点「重拍」，上一张的 Live Photo 视频可能还在写，两张会同时在路上
    private var processors: [Int64: PhotoCaptureProcessor] = [:]

    // MARK: - 权限

    /// 请求相机权限，回调在主线程。
    func requestAccess(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hopToMain(completion, true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [self] granted in
                hopToMain(completion, granted)
            }
        default:
            hopToMain(completion, false)
        }
    }

    /// 回主线程执行回调。已经 `DispatchQueue.main` 上了，`assumeIsolated` 免去多余的 Task 调度。
    private func hopToMain<T>(_ completion: @escaping @MainActor @Sendable (T) -> Void, _ value: T) where T: Sendable {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { completion(value) }
        }
    }

    // MARK: - 生命周期

    /// 首次调用会配置输入输出；已配置则仅恢复运行。回调在主线程。
    func start(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        queue.async { [self] in
            if session.inputs.isEmpty, !configureOnQueue() {
                hopToMain(completion, false)
                return
            }
            if !session.isRunning { session.startRunning() }
            hopToMain(completion, true)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// 变焦上限：超过 5× 数码放大画质劣化明显，不给用户踩坑的机会
    static let maxZoom: CGFloat = 5

    /// 设置变焦倍率（内部按设备能力和上限夹取）。拖动时用：直接跟手
    func setZoom(_ factor: CGFloat) {
        queue.async { [self] in
            guard let device = videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
            } catch {
                let ns = error as NSError
                NSLog("⚠️ [Camera] 变焦锁设备失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
                return
            }
            device.videoZoomFactor = clampedZoom(factor, for: device)
            device.unlockForConfiguration()
        }
    }

    /// 平滑地推到某个倍率（点预设倍数时用）。速率 8 = 每秒放大 2⁸ 倍的对数速度，1× 到 5× 约 0.3 秒，和界面上的滑块一起到
    func rampZoom(to factor: CGFloat) {
        queue.async { [self] in
            guard let device = videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
            } catch {
                let ns = error as NSError
                NSLog("⚠️ [Camera] 变焦锁设备失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
                return
            }
            device.ramp(toVideoZoomFactor: clampedZoom(factor, for: device), withRate: 8)
            device.unlockForConfiguration()
        }
    }

    private func clampedZoom(_ factor: CGFloat, for device: AVCaptureDevice) -> CGFloat {
        let ceiling = min(device.maxAvailableVideoZoomFactor, Self.maxZoom)
        return max(device.minAvailableVideoZoomFactor, min(factor, ceiling))
    }

    /// 前后摄切换
    /// 设置闪光灯模式。只改意向，下次拍照生效。
    func setFlash(_ mode: AVCaptureDevice.FlashMode) {
        queue.async { [self] in flashMode = mode }
    }

    /// 当前镜头有没有闪光灯（前摄通常没有）。主线程可直接读，用于决定按钮显不显示。
    var isFlashAvailable: Bool {
        camera(at: position)?.hasFlash ?? false
    }

    func flip() {
        queue.async { [self] in
            let next: AVCaptureDevice.Position = (position == .back) ? .front : .back
            guard let device = camera(at: next),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }

            session.beginConfiguration()
            if let old = videoInput { session.removeInput(old) }
            if session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
                position = next
            } else if let old = videoInput {
                session.addInput(old)   // 回滚
            }
            enableLivePhotoIfSupported()   // 前后摄的 Live Photo 能力可能不同
            session.commitConfiguration()
        }
    }

    // MARK: - 拍照

    /// 拍一张，原图直出（设备支持时连 Live Photo 一起拍）。两段回调，都在主线程，失败给 nil：
    /// - `onPhoto`：照片本身处理完就来（按下后约 0.3～0.5 秒），带一张显示用的小方图 —— 取景框马上换成相纸
    /// - `onFinished`：Live Photo 那段视频也写完了才来（要录到按下之后 1.5 秒左右）
    ///
    /// 2026-10-17 之前只有一段回调、等到视频写完才出图，拍完要干等一两秒（产品真机反馈）
    func capture(
        onPhoto: @escaping @MainActor @Sendable (CapturedPhoto?) -> Void,
        onFinished: @escaping @MainActor @Sendable (CameraShot?) -> Void
    ) {
        queue.async { [self] in
            // 前摄按预览镜像出图，避免「拍出来和看到的左右相反」
            let mirrored = (position == .front)
            if let conn = photoOutput.connection(with: .video), conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = mirrored
            }

            // 显式要 JPEG：默认格式随机型/系统设置可能是 HEIC，落盘时就没法确定扩展名，
            // 而扩展名对不上会干扰 `PHLivePhoto.request` 判断资源类型。
            let settings = photoOutput.availablePhotoCodecTypes.contains(.jpeg)
                ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                : AVCapturePhotoSettings()
            // 闪光灯：`supportedFlashModes` 是**按当前镜头**给的，直接塞不支持的值会崩
            if photoOutput.supportedFlashModes.contains(flashMode) {
                settings.flashMode = flashMode
            }

            if photoOutput.isLivePhotoCaptureEnabled {
                // 每次拍照都要一个全新的、尚不存在的路径，复用会直接失败
                settings.livePhotoMovieFileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("shot_\(UUID().uuidString).mov")
            }

            let id = settings.uniqueID
            let p = PhotoCaptureProcessor(
                onPhoto: { [weak self] data in
                    // AVFoundation 的回调线程上：解码、转正、裁方都在这里做完，不占主线程
                    let ready = data.flatMap { data in
                        ShotImage.squarePreview(from: data).map { CapturedPhoto(stillData: data, preview: $0) }
                    }
                    self?.hopToMain(onPhoto, ready)
                },
                onFinished: { [weak self] shot in
                    self?.hopToMain(onFinished, shot)
                    self?.queue.async { self?.processors[id] = nil }
                }
            )
            processors[id] = p
            photoOutput.capturePhoto(with: settings, delegate: p)
        }
    }

    // MARK: - 内部

    /// 必须在 `queue` 上调用
    private func configureOnQueue() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo
        guard let device = camera(at: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput) else {
            return false
        }
        session.addInput(input)
        videoInput = input
        session.addOutput(photoOutput)
        enableLivePhotoIfSupported()
        return true
    }

    /// 打开 Live Photo 采集。**必须在 output 加进 session 之后**，且只有 supported 时才能置 true
    /// （不支持时赋值会直接抛异常）。前后摄能力可能不同，切换摄像头后要重新判一次。
    private func enableLivePhotoIfSupported() {
        photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
    }

    private func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }
}

// MARK: - 单次拍照 delegate

/// 一次拍照可能触发多个回调（静态图一个、Live Photo 视频一个），
/// 全部结束后系统才调 `didFinishCaptureFor` —— 完整的产物在那里收口；
/// 静态图一好就先交一次（`onPhoto`），界面不用等视频。
private nonisolated final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let onPhoto: (Data?) -> Void
    private let onFinished: (CameraShot?) -> Void
    private var stillData: Data?
    private var movieURL: URL?
    /// `onPhoto` 只交一次（照片回调没来就收口了，也要在收口时补一次 nil，界面才不会一直等）
    private var photoDelivered = false

    init(onPhoto: @escaping (Data?) -> Void, onFinished: @escaping (CameraShot?) -> Void) {
        self.onPhoto = onPhoto
        self.onFinished = onFinished
    }

    private func deliverPhoto(_ data: Data?) {
        guard !photoDelivered else { return }
        photoDelivered = true
        onPhoto(data)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        if let error {
            let ns = error as NSError
            NSLog("🔴 [Camera] 照片处理失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            deliverPhoto(nil)
            return
        }
        // 原始字节，元数据完整 —— 千万别在这里转 UIImage 再转回来
        stillData = photo.fileDataRepresentation()
        deliverPhoto(stillData)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
        duration: CMTime,
        photoDisplayTime: CMTime,
        resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: (any Error)?
    ) {
        if let error {
            let ns = error as NSError
            NSLog("🔴 [LivePhoto] 相机成对视频写入失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            return
        }
        movieURL = outputFileURL
    }

    /// 该次拍照的最后一个回调 —— 静态图和 Live 视频都已就位
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: (any Error)?
    ) {
        deliverPhoto(stillData)
        guard let stillData else {
            onFinished(nil)
            return
        }
        onFinished(CameraShot(stillData: stillData, movieURL: movieURL))
    }
}

// MARK: - 裁切

/// 拍到的照片居中裁成正方形，把 EXIF 方向烘焙进像素。
///
/// 取景框是方的，所见即所得；方形也正是相纸（宝丽来）的原生比例。
/// 用 ImageIO 解码：显示用的那张解码时就按缩小的尺寸解（快十几倍），存进日记的那张才按原尺寸解。
/// 裁方用 `CGImage.cropping`，不重画一遍像素。都不碰主线程。
nonisolated enum ShotImage {
    /// 取景框里显示用的方图的边长（像素）。取景框约 330pt × 3 倍屏，1200 足够清楚
    static let previewSide: CGFloat = 1200

    /// 显示用：缩小解码 + 转正 + 裁方
    static func squarePreview(from data: Data) -> UIImage? {
        // 长边按方边的 4/3 解（照片是 4:3），裁出来的方边正好约等于 `previewSide`
        square(decode(data, maxPixel: previewSide * 4 / 3))
    }

    /// 存进日记用：原尺寸解码 + 转正 + 裁方（和原来 `UIGraphicsImageRenderer` 重画的结果一样，只是快）
    static func squareFull(from data: Data) -> UIImage? {
        square(decode(data, maxPixel: nil))
    }

    private static func decode(_ data: Data, maxPixel: CGFloat?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // 按 EXIF 方向转正
            kCGImageSourceShouldCacheImmediately: true,          // 在这条后台线程上就解完，别等到画的时候
        ]
        if let maxPixel {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel
        } else if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
                  let height = properties[kCGImagePropertyPixelHeight] as? CGFloat {
            options[kCGImageSourceThumbnailMaxPixelSize] = max(width, height)
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func square(_ image: CGImage?) -> UIImage? {
        guard let image else { return nil }
        let side = min(image.width, image.height)
        let rect = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
        return image.cropping(to: rect).map { UIImage(cgImage: $0) }
    }
}
