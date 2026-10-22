import UIKit

/// 日记照片按要显示的大小解出来的图，连同它的底色（照片底部的主色，大卡片 / 总览格子的文字区用它染色）。
///
/// 用在一屏放好几篇的地方：大屏的大卡片（1400px）、总览的格子（600 / 300 / 160px）、日记本主页的目录宫格（300px）。
///
/// 🔴 **为什么要有它**（2026-10-21 真机上「非常卡」）：原来大卡片在 body 里**同步**读原图、缩小、取色，
/// 用户的照片是 1200 万～4800 万像素的原图，翻一页主线程就被占住好几秒；缓存又只放得下七八张 1400px 的图，
/// 来回翻一直在重读。现在：
///
/// - **全在后台解**，主线程只拿结果。ImageIO 按目标尺寸直接解，不先把整张原图解进内存
/// - **同时最多解 3 张**，后来的先解（`DecodeGate`，先进后出），低优先级：快速滚过去的格子不会把 CPU 占满、不抢主线程，眼前这几格先出来
/// - 格子已经滚走（任务被取消）就不解了
/// - **解过的小图存一份在 Caches**（`Library/Caches/EntryPhotos/<尺寸>/`），下次直接读几十 KB 的小图，不再碰原图。
///   照片文件名带 UUID、存下就不改，所以不用管失效；删了照片留下的小图系统空间紧时会自己清
/// - 底色按文件名记一份，各种尺寸共用（换级时颜色不跳）
@MainActor
enum EntryPhotoStore {
    struct Photo {
        let image: UIImage
        let tint: UIColor
    }

    private final class Box {
        let photo: Photo
        init(_ photo: Photo) { self.photo = photo }
    }

    private static let memory: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 400
        c.totalCostLimit = 90 * 1024 * 1024
        return c
    }()
    /// 底色：按文件名，各尺寸共用
    private static var tints: [String: UIColor] = [:]
    private static let gate = DecodeGate(limit: 3)
    /// 每种尺寸解过的有哪些（`anyCached` 先大后小找）
    private static let sizes: [CGFloat] = [1400, 600, 300, 160]

    // MARK: - 取

    /// 这个尺寸已经解好的
    static func cached(_ filename: String, pixels: CGFloat) -> Photo? {
        memory.object(forKey: key(filename, pixels))?.photo
    }

    /// 任何尺寸解好过的（先大后小）：换格子大小、翻到下一页时先拿它顶着，正好的那张解好了再换，不闪底色
    static func anyCached(_ filename: String) -> Photo? {
        for pixels in sizes {
            if let hit = memory.object(forKey: key(filename, pixels)) { return hit.photo }
        }
        return nil
    }

    /// 底色已经算过的（还没解过这张照片就是 nil）
    static func knownTint(_ filename: String) -> UIColor? {
        tints[filename]
    }

    /// 解到最长边 `pixels` 像素。调用的任务被取消（格子滚走了）就不解，返回 nil
    static func load(_ filename: String, pixels: CGFloat) async -> Photo? {
        let key = key(filename, pixels)
        if let hit = memory.object(forKey: key) { return hit.photo }

        await gate.acquire()
        defer { gate.release() }
        if Task.isCancelled { return nil }
        // 排队的时候别人可能已经解好了
        if let hit = memory.object(forKey: key) { return hit.photo }

        let original = PhotoPaperIO.photosDirectory.appendingPathComponent(filename)
        let small = smallURL(filename, pixels)
        let knownTint = tints[filename]
        // 低优先级：手机上让给主线程用大核，解图走小核，翻页滚动时不抢（2026-10-21 真机测帧）
        let result = await Task.detached(priority: .utility) { () -> (UIImage, UIColor)? in
            // 先找存过的小图；没有再从原图解，解完存一份
            var image = small.flatMap { NotebookCoverStore.downsample($0, maxPixels: pixels) }
            if image == nil {
                image = NotebookCoverStore.downsample(original, maxPixels: pixels)
                if let image, let small, let data = image.jpegData(compressionQuality: 0.82) {
                    do {
                        try FileManager.default.createDirectory(at: small.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: small, options: .atomic)
                    } catch {
                        let ns = error as NSError
                        NSLog("⚠️ [EntryPhotoStore] 小图存不下 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
                    }
                }
            }
            guard let image else { return nil }
            // 转成屏幕直接能用的格式再交出去：否则第一次显示时还要在主线程上转一遍，翻页那一下会掉帧
            let ready = image.preparingForDisplay() ?? image
            return (ready, knownTint ?? DominantColor.tint(of: ready))
        }.value

        guard let (image, tint) = result else {
            NSLog("⚠️ [EntryPhotoStore] 照片解不出来：%@", filename)
            return nil
        }
        if tints[filename] == nil { tints[filename] = tint }
        let photo = Photo(image: image, tint: tints[filename] ?? tint)
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(Box(photo), forKey: key, cost: cost)
        return photo
    }

    /// 提前解好（翻页时把左右两页的照片先解出来，翻过去就有）
    static func prefetch(_ filenames: [String], pixels: CGFloat) {
        for name in filenames where memory.object(forKey: key(name, pixels)) == nil {
            Task { _ = await load(name, pixels: pixels) }
        }
    }

    // MARK: - 内部

    private static func key(_ filename: String, _ pixels: CGFloat) -> NSString {
        "\(Int(pixels)):\(filename)" as NSString
    }

    private static let smallRoot: URL? = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("EntryPhotos", isDirectory: true)
    }()

    /// 存小图的地方：`Caches/EntryPhotos/<尺寸>/<原文件名>.jpg`
    private static func smallURL(_ filename: String, _ pixels: CGFloat) -> URL? {
        smallRoot?
            .appendingPathComponent("\(Int(pixels))", isDirectory: true)
            .appendingPathComponent(filename + ".jpg")
    }
}

/// 同时最多放 `limit` 个进去，多的排队；**后来的先进**（快速滚动时，眼前刚出现的格子比早就滚走的要紧）
@MainActor
final class DecodeGate {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// 名额直接交给排在最后的那个（`running` 不变）
    func release() {
        if let next = waiting.popLast() {
            next.resume()
        } else {
            running -= 1
        }
    }
}
