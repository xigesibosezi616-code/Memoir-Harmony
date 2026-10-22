import SwiftUI
import UIKit

// MARK: - 进程级图片缓存

/// 全进程共享的 UIImage 内存缓存。
/// - 命中：跳过磁盘 IO + JPEG 解码（PhotoPaperView body 频繁重算时关键优化点）
/// - miss：读磁盘 + `preparingThumbnail` 解码并缩放到 600×600，降低内存峰值
/// - 系统内存紧张时 NSCache 会自动驱逐条目，无需手动管理
final class ImageCache {
    static let shared = NSCache<NSString, UIImage>()
    static func setup() {
        shared.countLimit = 100                    // 最多 100 张
        shared.totalCostLimit = 50 * 1024 * 1024   // 50 MB 上限
    }
}

// MARK: - 照片文件加载

enum PhotoPaperIO {
    /// 照片存放目录：Documents/journal_photos/
    static var photosDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("journal_photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
        }
        return dir
    }

    /// 从 Documents/journal_photos/<filename> 加载 UIImage，**带进程级内存缓存**。
    /// 策略：内存命中 → 直接返回；否则读磁盘 + `preparingThumbnail(of:)` 缩放到 600×600 + 入缓存。
    static func loadImage(_ filename: String?) -> UIImage? {
        guard let filename, !filename.isEmpty else { return nil }

        // 1. 内存缓存命中
        let key = filename as NSString
        if let cached = ImageCache.shared.object(forKey: key) {
            return cached
        }

        // 2. 读磁盘
        let url = photosDirectory.appendingPathComponent(filename)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }

        // 3. 缩到 600×600 缩略图（同步解码 + 缩放，比 SwiftUI Image.resizable 内存占用低得多）
        let targetSize = CGSize(width: 600, height: 600)
        let thumbnail = image.preparingThumbnail(of: targetSize) ?? image

        // 4. 入缓存（cost = 像素数 × 4 字节 RGBA，逼近真实内存占用）
        let cost = Int(thumbnail.size.width * thumbnail.size.height * thumbnail.scale * thumbnail.scale * 4)
        ImageCache.shared.setObject(thumbnail, forKey: key, cost: cost)

        return thumbnail
    }

    /// 大屏展示封面用的加载：目标 1400×1400。
    ///
    /// 与 `loadImage` 的 600×600 分开缓存（键加 `cover:` 前缀）—— 同一文件名在两处按不同尺寸取用，
    /// 共用一个键会互相覆盖，导致正文里的小图被换成大图（白占内存）或封面被换成糊图。
    static func loadCoverImage(_ filename: String?) -> UIImage? {
        guard let filename, !filename.isEmpty else { return nil }

        let key = "cover:\(filename)" as NSString
        if let cached = ImageCache.shared.object(forKey: key) {
            return cached
        }

        let url = photosDirectory.appendingPathComponent(filename)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }

        let targetSize = CGSize(width: 1400, height: 1400)
        // 原图本来就比目标小就别放大，放大只会更糊还更占内存
        let needsDownscale = image.size.width > targetSize.width || image.size.height > targetSize.height
        let result = needsDownscale ? (image.preparingThumbnail(of: targetSize) ?? image) : image

        let cost = Int(result.size.width * result.size.height * result.scale * result.scale * 4)
        ImageCache.shared.setObject(result, forKey: key, cost: cost)
        return result
    }

    /// 保存 UIImage 到 Documents/journal_photos/<filename>，以 JPEG 压缩
    @discardableResult
    static func saveImage(_ image: UIImage, filename: String, quality: CGFloat = 0.85) -> Bool {
        guard let data = image.jpegData(compressionQuality: quality) else { return false }
        let url = photosDirectory.appendingPathComponent(filename)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// 保存任意 Data 到 Documents/journal_photos/<filename>（用于 Live Photo 视频）
    @discardableResult
    static func saveData(_ data: Data, filename: String) -> Bool {
        let url = photosDirectory.appendingPathComponent(filename)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// 删除指定文件名的照片文件
    static func deleteImage(_ filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        let url = photosDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - 通用占位符（照片未能加载时）

struct PhotoPaperPlaceholder: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(hex: "#E8DDC9").opacity(0.5))
            Image(systemName: "photo")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color(hex: "#8A7E6C").opacity(0.7))
        }
        .aspectRatio(1.0, contentMode: .fit)
    }
}

// MARK: - 三角形（相角装饰）

struct CornerTriangle: Shape {
    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    let corner: Corner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch corner {
        case .topLeft:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .topRight:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomLeft:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        case .bottomRight:
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}


// MARK: - 相纸里的「照片那一格」

/// 相纸里放照片的那一格。**尺寸只由外面给的宽度 × `aspect` 决定，里面放什么都撑不大它。**
///
/// ## 为什么不能写成 `Group { 照片 }.aspectRatio(比例, .fit).clipped()`
/// 六种相纸原来都是这么写的，看着像是「按比例定尺寸、多出来的裁掉」，其实不是：
/// `.aspectRatio` **只是给子视图一个建议尺寸**，子视图报回来多大，它就是多大；
/// `.clipped()` 也只按这个已经变大的尺寸去裁。所以只要里面的东西不守规矩，整格就跟着变大。
///
/// 不守规矩的正是 Live Photo 的播放器：`PHLivePhotoView` 装上照片后，固有尺寸就是照片的像素尺寸
/// （几千 pt），UIKit 视图默认的抗压缩优先级又高，SwiftUI 会尊重它 —— 详情页里的照片就被撑满屏幕、
/// 还溢出到屏幕外（2026-10-09 真机：从大屏卡片点进详情页偶发）。之所以「偶发」，
/// 是播放器异步加载完照片后，要等下一次重新布局（切大屏 / 转场）才会被问到尺寸。
///
/// 现在照片放在 `Color.clear` 的 **overlay** 里：overlay 的内容影响不了底下那层的尺寸，
/// 格子永远是「宽 × 比例」，内容多出来的部分由 `.clipped()` 裁掉。
struct PhotoPaperImageArea: View {
    let uiImage: UIImage?
    var livePhotoContent: AnyView? = nil
    /// 宽 / 高
    let aspect: CGFloat

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                if let livePhotoContent {
                    livePhotoContent
                } else if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    PhotoPaperPlaceholder()
                }
            }
            .clipped()
    }
}
