import ImageIO
import SwiftUI
import UIKit

/// 把一本日记本做成精装 PDF：备料（字体、照片尺寸）→ 排版（`BookPaginator`）→ 一页页画进 PDF（`BookPageView`）。
///
/// - **排版不解图**：照片多大读文件头就知道（ImageIO 的属性，毫秒级），相纸多大拿同比例的小灰块量。
///   几百张照片的日记本，预览也是一打开就有
/// - **画到哪页才解哪页的图**：按印刷尺寸在后台解（最长边 1600px，A5 上约 300 dpi），**重新压成 JPEG**，
///   画进 PDF 时直接嵌 JPEG（几百张照片的书也就几十 MB；位图直接画进去会被无损压缩，动辄几百 MB），画完就扔，内存不攒
/// - 每画一页让一下主线程（进度条照常走、能取消）。PDF 边画边写盘
@MainActor
enum BookExporter {
    /// 这本书的信息：封面、扉页、版权页用
    static func info(tag: Tag, entries: [JournalEntry], author: String?) async -> BookInfo {
        var cover: UIImage?
        var tint: Color?
        if let name = tag.coverPhotoFilename, !name.isEmpty {
            cover = await coverPhoto(name)
            tint = await NotebookCoverStore.thumbnail(name)?.averageColor
        }
        let photoCount = entries.reduce(0) { $0 + $1.contentBlocks.filter { $0.type == .photo }.count }
        let subtitle = tag.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BookInfo(
            title: tag.name,
            subtitle: (subtitle?.isEmpty ?? true) ? nil : subtitle,
            dateRange: dateRange(entries),
            author: author.flatMap { $0.isEmpty ? nil : $0 },
            color: tag.bookColor,
            coverPhoto: cover,
            coverLayout: tag.coverLayout,
            photoTint: cover == nil ? nil : tint,
            entryCount: entries.count,
            photoCount: photoCount,
            exportedAt: .now
        )
    }

    /// 封面照片：存盘时就是 1200px 宽的 JPEG（`NotebookCoverStore.save`），原样读进来不解码 ——
    /// 画进 PDF 时直接嵌这份 JPEG。解成位图再画会被无损压缩，一张封面就好几 MB
    private static func coverPhoto(_ filename: String) async -> UIImage? {
        let url = PhotoPaperIO.photosDirectory.appendingPathComponent(filename)
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            do {
                let data = try Data(contentsOf: url)
                if let image = UIImage(data: data) { return image }
                NSLog("⚠️ [BookExporter] 封面照片解不出来，封面用布面：%@", filename)
            } catch {
                let ns = error as NSError
                NSLog("❌ [BookExporter] 读不了封面照片，封面用布面 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            }
            return nil
        }.value
    }

    /// 「2026年3月 — 2026年10月」（同一个月就只写一个）
    static func dateRange(_ entries: [JournalEntry]) -> String {
        guard let first = entries.first?.date, let last = entries.last?.date else { return "" }
        let start = BookContents.monthTitle(first)
        let end = BookContents.monthTitle(last)
        return start == end ? start : "\(start) — \(end)"
    }

    // MARK: - 照片

    /// 正文里所有照片的版式：读文件头得到比例，量好单独一张、和挨着的那张并排时各占多大。不解图
    static func figures(for entries: [JournalEntry]) async -> BookFigureCatalog {
        var catalog = BookFigureCatalog()
        catalog.singles = await singleFigures(for: entries)
        for entry in entries {
            for (first, second) in BookPaginator.adjacentPhotoPairs(in: entry.contentBlocks) {
                // 键和排版时查表用的一样：两个照片块的 id
                guard let a = catalog.singles[first.id], let b = catalog.singles[second.id] else { continue }
                let key = BookFigureCatalog.Pair(first: first.id, second: second.id)
                if catalog.pairs[key] == nil, let row = pairRow(a, b) { catalog.pairs[key] = row }
            }
        }
        return catalog
    }

    /// 按照片块（不按文件名）：同一个文件在两处用了不同的相纸，各量各的
    private static func singleFigures(for entries: [JournalEntry]) async -> [UUID: BookFigure] {
        let blocks = entries.flatMap { $0.contentBlocks }.filter { $0.type == .photo && $0.photoFilename != nil }
        let directory = PhotoPaperIO.photosDirectory
        // 比例在后台读（几百个文件头）
        let sources = blocks.map { ($0.photoFilename!, $0.pairingStillFilename ?? $0.photoFilename!) }
        let aspects = await Task.detached(priority: .userInitiated) { () -> [String: CGFloat] in
            var result: [String: CGFloat] = [:]
            for (_, source) in sources where result[source] == nil {
                if let aspect = pixelAspect(directory.appendingPathComponent(source)) { result[source] = aspect }
            }
            return result
        }.value

        var result: [UUID: BookFigure] = [:]
        for block in blocks where result[block.id] == nil {
            guard let name = block.photoFilename else { continue }
            let source = block.pairingStillFilename ?? name
            guard let aspect = aspects[source] else {
                NSLog("⚠️ [BookExporter] 照片读不出尺寸，书里跳过：%@", source)
                continue
            }
            result[block.id] = BookFigure(block: block, source: source, aspect: aspect,
                                          size: figureSize(block: block, aspect: aspect))
        }
        return result
    }

    /// 照片的宽高比（读文件头，按拍摄方向转正）
    nonisolated private static func pixelAspect(_ url: URL) -> CGFloat? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        // 5–8 是转了 90° 的方向：宽高对调
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? height / width : width / height
    }

    /// 相纸连照片在版心里多大：宽占版心 62%，太高（竖幅）就整体缩小，最高占版心高的 58%
    private static func figureSize(block: ContentBlock, aspect: CGFloat) -> CGSize {
        let maxHeight = BookLayout.textHeight * BookLayout.figureMaxHeightRatio
        let width = BookLayout.textWidth * BookLayout.figureWidthRatio
        var height = paperHeight(block: block, aspect: aspect, width: width)
        if height > maxHeight {
            let narrower = floor(width * maxHeight / height)
            height = paperHeight(block: block, aspect: aspect, width: narrower)
            return CGSize(width: narrower, height: height)
        }
        return CGSize(width: width, height: height)
    }

    /// 这张照片连相纸排成 `width` 宽时多高（拿同比例的灰块量，不用解原图）
    private static func paperHeight(block: ContentBlock, aspect: CGFloat, width: CGFloat) -> CGFloat {
        let probe = BookPhotoPaper.placeholder(aspect: aspect)
        let host = UIHostingController(rootView: BookPhotoPaper(block: block, image: probe).frame(width: width))
        let fitted = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        return ceil(fitted.height)
    }

    /// 挨着的两张并排：两张相纸一样高、加起来占满版心宽（中间空 `pairGap`）。
    ///
    /// 一样高靠**等比**缩放 —— 长的那张（手机截图）变窄，照片从不拉伸、不硬塞（2026-10-22 用户强调）。
    /// 相纸的高随宽线性变（边框是定的、照片按比例）：每张量两个宽度拟合 `高 = k·宽 + c`，解出一样高时各多宽。
    /// 太高就一起缩小；有一张会窄到不足版心宽的三成（全景配竖幅）就不并排，返回 nil
    private static func pairRow(_ a: BookFigure, _ b: BookFigure) -> BookFigureRow? {
        let total = BookLayout.textWidth - BookLayout.pairGap
        func line(_ figure: BookFigure) -> (k: CGFloat, c: CGFloat) {
            let w1 = total * 0.3, w2 = total * 0.7
            let h1 = paperHeight(block: figure.block, aspect: figure.aspect, width: w1)
            let h2 = paperHeight(block: figure.block, aspect: figure.aspect, width: w2)
            let k = (h2 - h1) / (w2 - w1)
            return (k, h1 - k * w1)
        }
        let la = line(a), lb = line(b)
        guard la.k + lb.k > 0 else { return nil }
        var widthA = floor((lb.k * total + lb.c - la.c) / (la.k + lb.k))
        var widthB = floor(total - widthA)
        let minimum = BookLayout.textWidth * BookLayout.pairMinWidthRatio
        guard widthA >= minimum, widthB >= minimum else { return nil }

        let maxHeight = BookLayout.textHeight * BookLayout.figureMaxHeightRatio
        var height = max(paperHeight(block: a.block, aspect: a.aspect, width: widthA),
                         paperHeight(block: b.block, aspect: b.aspect, width: widthB))
        if height > maxHeight {
            let shrink = maxHeight / height
            widthA = floor(widthA * shrink)
            widthB = floor(widthB * shrink)
            height = max(paperHeight(block: a.block, aspect: a.aspect, width: widthA),
                         paperHeight(block: b.block, aspect: b.aspect, width: widthB))
        }
        return BookFigureRow(pair: a, b, widths: [widthA, widthB], height: height)
    }

    /// 一页上的照片：按印刷尺寸在后台解好，压成 JPEG（画进 PDF 时直接嵌 JPEG）
    static func images(on page: BookPage) async -> [String: UIImage] {
        guard case .body(let body) = page else { return [:] }
        let sources = body.items.flatMap { item -> [String] in
            if case .figures(let row) = item { return row.figures.map(\.source) }
            return []
        }
        guard !sources.isEmpty else { return [:] }
        let directory = PhotoPaperIO.photosDirectory
        return await Task.detached(priority: .userInitiated) { () -> [String: UIImage] in
            var result: [String: UIImage] = [:]
            for source in sources where result[source] == nil {
                guard let decoded = NotebookCoverStore.downsample(directory.appendingPathComponent(source),
                                                                  maxPixels: BookLayout.figurePixels),
                      let jpeg = decoded.jpegData(compressionQuality: 0.85),
                      let image = UIImage(data: jpeg) else {
                    NSLog("⚠️ [BookExporter] 照片解不出来，用灰块占位：%@", source)
                    continue
                }
                result[source] = image
            }
            return result
        }.value
    }

    // MARK: - 画

    /// 一页页画进 PDF，写到 `url`。`progress` 0…1；任务取消就停下（写了一半的文件由调用方删）
    static func renderPDF(pages: [BookPage], info: BookInfo, to url: URL, progress: (Double) -> Void = { _ in }) async throws {
        var box = CGRect(origin: .zero, size: BookLayout.pageSize)
        var auxiliary: [CFString: Any] = [kCGPDFContextTitle: info.title, kCGPDFContextCreator: "Memoir 尺素"]
        if let author = info.author { auxiliary[kCGPDFContextAuthor] = author }
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, auxiliary as CFDictionary) else {
            NSLog("❌ [BookExporter] 建不了 PDF：%@", url.path)
            throw CocoaError(.fileWriteUnknown)
        }
        defer { pdf.closePDF() }
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            if case .cover = page, let cover = await coverRaster(info: info) {
                pdf.beginPDFPage(nil)
                pdf.draw(cover, in: CGRect(origin: .zero, size: BookLayout.pageSize))
                pdf.endPDFPage()
            } else {
                let images = await images(on: page)
                let renderer = ImageRenderer(content: BookPageView(page: page, index: index, info: info, images: images))
                renderer.proposedSize = ProposedViewSize(BookLayout.pageSize)
                renderer.render { _, draw in
                    pdf.beginPDFPage(nil)
                    draw(pdf)
                    pdf.endPDFPage()
                }
            }
            progress(Double(index + 1) / Double(pages.count))
            await Task.yield()
        }
    }

    /// 封面先画成一张图（约 290 dpi 的 JPEG）再放进 PDF。
    ///
    /// 🔴 SwiftUI 画进 PDF 时，**带透明度的渐变会变成实心的**（2026-10-22 真机：满版封面上下压暗的那层把照片整个盖成黑的，
    /// 杂志封面左边的书脊阴影成了一道黑边；预览走位图，看不出来）。封面画成位图就和预览一模一样；
    /// 其余各页照旧是矢量，字是清楚的
    private static func coverRaster(info: BookInfo) async -> CGImage? {
        guard let bitmap = await image(of: .cover, index: 0, info: info, scale: coverRasterScale),
              let jpeg = bitmap.jpegData(compressionQuality: 0.9),
              let provider = CGDataProvider(data: jpeg as CFData),
              // 用 JPEG 数据建图：PDF 里直接嵌这份 JPEG，不再解压重压
              let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            NSLog("⚠️ [BookExporter] 封面没能画成图，改按矢量画")
            return nil
        }
        return image
    }

    /// A5 宽 419.53 点 × 4 ≈ 1680 像素，约 290 dpi
    private static let coverRasterScale: CGFloat = 4

    /// 一页的图（预览用）
    static func image(of page: BookPage, index: Int, info: BookInfo, scale: CGFloat) async -> UIImage? {
        let images = await images(on: page)
        let renderer = ImageRenderer(content: BookPageView(page: page, index: index, info: info, images: images))
        renderer.proposedSize = ProposedViewSize(BookLayout.pageSize)
        renderer.scale = scale
        return renderer.uiImage
    }

    /// 估计 PDF 多大：每张照片约 0.55 MB，再加文字和封面
    static func estimatedBytes(figureCount: Int, pageCount: Int) -> Int {
        // 最后一项：布面 / 纸纹贴图约 1.5 MB + 画成图的封面约 1 MB
        figureCount * 560_000 + pageCount * 12_000 + 2_500_000
    }
}
