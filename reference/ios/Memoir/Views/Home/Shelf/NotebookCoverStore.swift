import SwiftUI
import SwiftData
import UIKit
import ImageIO

/// 日记本的照片封面：存、取、删。
///
/// ## 存法
/// 选来的照片**当场裁成封面比例**（`aspect` = 0.73，和亚麻封面同比例）、缩到 1200px 宽，存成 JPEG，
/// 放在 `journal_photos/` 里，文件名 `cover_<UUID>.jpg`，写进 `Tag.coverPhotoFilename`。
/// 1200px ≈ 全屏宽 × 3 倍屏：P3 的日记本主页要拿它做满屏大图，书架上只用缩小版（见 `thumbnail`）。
///
/// 裁切直接"烤"进文件、不另存裁切参数：V7 schema 没有放裁切参数的字段，再加就要升一次 schema。
/// 以后封面编辑器（P3）让用户调构图，也是重新生成一张替换掉。
///
/// ## 同步与回收
/// 封面文件和日记里的照片走同一套：`MediaStorage` 把它算进「被引用」的文件 →
/// 登记成 `MediaAsset` 随 CloudKit 同步到别的设备；「清理残留文件」也不会把它当孤儿删掉。
/// 换掉 / 移除 / 删日记本时，旧文件和它的云端副本要一起删（`remove`）。
@MainActor
enum NotebookCoverStore {
    /// 封面宽高比（宽 / 高），与 `BookCoverView` 一致
    nonisolated static let aspect: CGFloat = 0.73
    /// 存盘宽度（px）
    nonisolated static let pixelWidth: CGFloat = 1200
    /// 书架 / 预览用的缩略图长边（px）。书架上一本约 110pt 宽、3 倍屏，480 绰绰有余
    static let thumbnailPixels: CGFloat = 480

    /// 不带 `errorDescription`：给用户看的统一是调用方传的「保存失败」兜底文案
    /// （`LocalizedError` 的描述在非主线程上取，读不了 App 选的语言）
    enum CoverError: Error {
        case encodeFailed
        case writeFailed(Error)
    }

    // MARK: - 存

    /// 裁成封面比例、缩到存盘尺寸、写盘，返回文件名。
    static func save(_ image: UIImage) throws -> String {
        let cropped = cropToCover(image)
        guard let data = cropped.jpegData(compressionQuality: 0.85) else { throw CoverError.encodeFailed }
        let filename = "cover_\(UUID().uuidString).jpg"
        let url = PhotoPaperIO.photosDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            let ns = error as NSError
            NSLog("❌ [Cover] 封面写盘失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            throw CoverError.writeFailed(error)
        }
        return filename
    }

    /// 居中裁成 `aspect`，再缩到最宽 `pixelWidth`（原图更小就不放大）。
    /// 不绑主线程：从相册读进来的原图可能有几千万像素，选图时放后台做（见 `BookCustomizerView.load`）
    nonisolated static func cropToCover(_ image: UIImage) -> UIImage {
        render(image, crop: centeredCrop(for: image.size))
    }

    /// 原图里居中、比例为 `aspect` 的最大一块（点坐标）
    nonisolated static func centeredCrop(for size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: size) }
        let crop: CGSize = size.width / size.height > aspect
            ? CGSize(width: size.height * aspect, height: size.height)   // 太宽：裁左右
            : CGSize(width: size.width, height: size.width / aspect)     // 太高：裁上下
        return CGRect(
            x: (size.width - crop.width) / 2, y: (size.height - crop.height) / 2,
            width: crop.width, height: crop.height
        )
    }

    /// 把原图里 `rect`（点坐标、比例应为 `aspect`）这一块画成封面：最宽 `pixelWidth`，原图更小就不放大。
    /// 拖动调构图（`CoverCropView`）之后也走这里。
    /// `UIImage.draw` 会按 `imageOrientation` 摆正，竖拍的照片不会横过来。
    nonisolated static func render(_ image: UIImage, crop rect: CGRect) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else { return image }
        let outWidth = min(pixelWidth, rect.width * image.scale)
        let outSize = CGSize(width: outWidth.rounded(), height: (outWidth / aspect).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outSize, format: format).image { _ in
            let scale = outSize.width / rect.width
            let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
            let origin = CGPoint(x: -rect.minX * scale, y: -rect.minY * scale)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    /// 从相册拿到的原始数据按长边 `maxPixels` 解码。
    /// 4800 万像素的原图整张解进内存要近 200MB；调构图用 2400px 已经绰绰有余
    nonisolated static func downsample(data: Data, maxPixels: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - 删

    /// 删掉封面文件和它的云端副本（`MediaAsset`）。只删磁盘的话，别的设备同步下来还会把它写回来
    static func remove(_ filename: String?, in context: ModelContext) {
        guard let filename, !filename.isEmpty else { return }
        PhotoPaperIO.deleteImage(filename)
        cache.removeObject(forKey: filename as NSString)
        do {
            let assets = try context.fetch(FetchDescriptor<MediaAsset>(predicate: #Predicate { $0.filename == filename }))
            for asset in assets { context.delete(asset) }
        } catch {
            let ns = error as NSError
            NSLog("❌ [Cover] 查找封面云端副本失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        }
    }

    // MARK: - 取（缩略图 + 主色）

    /// 缩略图和照片主色（书脊用）
    final class Thumbnail {
        let image: UIImage
        let averageColor: Color
        init(image: UIImage, averageColor: Color) {
            self.image = image
            self.averageColor = averageColor
        }
    }

    private static let cache: NSCache<NSString, Thumbnail> = {
        let c = NSCache<NSString, Thumbnail>()
        c.countLimit = 120
        return c
    }()

    /// 已经在缓存里的就直接给（拿起书的那一下要同步拿到，不然会闪一下底色）
    static func cachedThumbnail(_ filename: String) -> Thumbnail? {
        cache.object(forKey: filename as NSString)
    }

    /// 读盘 + 缩小 + 算主色，放后台线程做，完了进缓存
    static func thumbnail(_ filename: String) async -> Thumbnail? {
        if let hit = cachedThumbnail(filename) { return hit }
        let url = PhotoPaperIO.photosDirectory.appendingPathComponent(filename)
        let maxPixels = thumbnailPixels
        let result = await Task.detached(priority: .userInitiated) { () -> (UIImage, UIColor)? in
            guard let image = downsample(url, maxPixels: maxPixels) else { return nil }
            return (image, averageColor(of: image))
        }.value
        guard let (image, color) = result else { return nil }
        let thumb = Thumbnail(image: image, averageColor: Color(uiColor: color))
        cache.setObject(thumb, forKey: filename as NSString)
        return thumb
    }

    // MARK: - 取（整张，日记本主页的大图用）

    private static let fullCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 6   // 同一时间最多开着一两本，留几张够来回切
        return c
    }()

    static func cachedFullImage(_ filename: String) -> UIImage? {
        fullCache.object(forKey: filename as NSString)
    }

    /// 整张封面（存盘时就是 1200px 宽，铺满全屏宽 3 倍屏正好）。后台读盘解码，完了进缓存
    static func fullImage(_ filename: String) async -> UIImage? {
        if let hit = cachedFullImage(filename) { return hit }
        let url = PhotoPaperIO.photosDirectory.appendingPathComponent(filename)
        let image = await Task.detached(priority: .userInitiated) {
            downsample(url, maxPixels: max(pixelWidth / aspect, pixelWidth))
        }.value
        if let image { fullCache.setObject(image, forKey: filename as NSString) }
        return image
    }

    /// ImageIO 直接按目标尺寸解码，不先把整张大图解进内存。
    /// 不绑主线程，日记本主页的目录宫格也用它读日记照片的小图
    nonisolated static func downsample(_ url: URL, maxPixels: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 缩到 1×1 像素取颜色，再压暗一点 —— 书脊在封面侧面、背光，原色直接用会显得发亮
    nonisolated static func averageColor(of image: UIImage) -> UIColor {
        guard let cg = image.cgImage else { return .darkGray }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drew = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drew else { return .darkGray }
        let shade: CGFloat = 0.82
        return UIColor(
            red: CGFloat(pixel[0]) / 255 * shade,
            green: CGFloat(pixel[1]) / 255 * shade,
            blue: CGFloat(pixel[2]) / 255 * shade,
            alpha: 1
        )
    }
}

// MARK: - 封面照片的来源

/// 封面上显示的照片从哪来：已经存好的文件，或者刚从相册选来、还没存的图（编辑封面时的实时预览）
enum CoverPhotoSource: Equatable {
    case file(String)
    case image(UIImage)
}

/// 编辑封面时，照片这一项的改动（点「应用 / 创建」时才落盘）
enum CoverPhotoDraft: Equatable {
    /// 沿用原来的（原来可能就没有）
    case unchanged
    /// 新选了一张，还没存
    case replaced(UIImage)
    /// 去掉照片，改用纯色亚麻封面
    case removed

    /// 把改动落到这本日记本上：写新文件、删旧文件和云端副本。**不保存 context**，由调用方保存。
    @MainActor
    func apply(to tag: Tag, in context: ModelContext) throws {
        switch self {
        case .unchanged:
            return
        case .replaced(let image):
            let old = tag.coverPhotoFilename
            tag.coverPhotoFilename = try NotebookCoverStore.save(image)
            NotebookCoverStore.remove(old, in: context)
        case .removed:
            NotebookCoverStore.remove(tag.coverPhotoFilename, in: context)
            tag.coverPhotoFilename = nil
        }
    }

    /// 编辑过程中预览该显示哪张
    func previewSource(existing filename: String?) -> CoverPhotoSource? {
        switch self {
        case .unchanged: return filename.map(CoverPhotoSource.file)
        case .replaced(let image): return .image(image)
        case .removed: return nil
        }
    }
}

// MARK: - 一次封面编辑的全部改动

/// 新建 / 编辑封面时攒下的改动：颜色、照片、版式、副标题。点「创建 / 应用」时一次性落到日记本上。
struct CoverEdit: Equatable {
    var color: BookColor
    var photo: CoverPhotoDraft = .unchanged
    var layout: CoverLayout = .fullBleed
    /// 用户输入的原样；落盘时去首尾空白，空的就是没有副标题
    var subtitle: String = ""

    /// 从一本已有的日记本起步
    init(tag: Tag) {
        color = tag.bookColor
        layout = tag.coverLayout
        subtitle = tag.subtitle ?? ""
    }

    /// 新建日记本的默认值
    init(color: BookColor) {
        self.color = color
    }

    /// 落到日记本上。**不保存 context**，由调用方保存。
    /// 照片写盘失败会抛出，但颜色 / 版式 / 副标题照样已经改好 —— 照片的失败不连累其他改动
    @MainActor
    func apply(to tag: Tag, in context: ModelContext) throws {
        tag.colorID = color.rawValue
        let cleaned = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        tag.subtitle = cleaned.isEmpty ? nil : String(cleaned.prefix(CoverEdit.subtitleMaxLength))
        try photo.apply(to: tag, in: context)
        // 版式只对照片封面有意义；没有照片就清掉，免得留一个看不见的值
        tag.coverLayoutID = tag.coverPhotoFilename == nil ? nil : layout.rawValue
    }

    /// 副标题上限：主页大图上一行放得下
    static let subtitleMaxLength = 24
}

// MARK: - 照片视图

/// 铺满容器的封面照片。文件版先显示底色、读好了淡入；缓存里有的直接显示，不闪
struct CoverPhotoView: View {
    let source: CoverPhotoSource
    /// 照片还没读出来时垫的颜色
    let fallback: Color
    /// true = 读整张（日记本主页的大图）；false = 读缩略图（书架、预览）
    var fullResolution = false

    @State private var loaded: UIImage?

    var body: some View {
        Group {
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                fallback
            }
        }
        .task(id: source) {
            guard case .file(let name) = source, cached(name) == nil else { return }
            let image = fullResolution
                ? await NotebookCoverStore.fullImage(name)
                : await NotebookCoverStore.thumbnail(name)?.image
            withAnimation(.easeOut(duration: 0.25)) { loaded = image }
        }
    }

    private func cached(_ name: String) -> UIImage? {
        fullResolution
            ? NotebookCoverStore.cachedFullImage(name)
            : NotebookCoverStore.cachedThumbnail(name)?.image
    }

    private var displayImage: UIImage? {
        switch source {
        case .image(let image):
            return image
        case .file(let name):
            // 大图还没读好时先垫缩略图（书架上一般已经读过），比先闪一下底色好
            return cached(name) ?? loaded ?? NotebookCoverStore.cachedThumbnail(name)?.image
        }
    }
}
