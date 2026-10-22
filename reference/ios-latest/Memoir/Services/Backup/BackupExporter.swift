import Foundation
import SwiftData
import UIKit

/// 把用户的全部日记打成一个可分享的备份包。
///
/// 流程：组装临时目录 → 压成 zip → （可选）整体加密 → 交给分享面板。
///
/// **zip 用系统自带的 `NSFileCoordinator(.forUploading)`**，不引第三方库 ——
/// 它能把一个目录读成标准 zip，是 iOS 上唯一公开的打包途径。
/// （读取方向没有对应 API，所以**导入**才需要 ZIPFoundation。）
@MainActor
enum BackupExporter {

    enum ExportError: LocalizedError {
        case nothingToExport
        case assemblyFailed(String)
        case zipFailed(String)

        var errorDescription: String? {
            switch self {
            // 会显示给用户，`Text(String)` 不查表 —— 必须显式 NSLocalizedString
            case .nothingToExport:
                return NSLocalizedString("还没有可以备份的日记", bundle: .appLanguage, comment: "备份导出错误")
            case .assemblyFailed(let m):
                return String(format: NSLocalizedString("整理数据时出错：%@", bundle: .appLanguage, comment: "备份导出错误，%@ 是底层原因"), m)
            case .zipFailed(let m):
                return String(format: NSLocalizedString("打包时出错：%@", bundle: .appLanguage, comment: "备份导出错误，%@ 是底层原因"), m)
            }
        }
    }

    struct Options {
        /// 关掉则只导出文字，包体通常只有几百 KB —— 微信 100MB 限制下的保命通道
        var includesMedia: Bool = true
        /// nil = 不加密（文件就是纯 zip）
        var password: String?
    }

    struct Result {
        let fileURL: URL
        let byteCount: Int
        let entryCount: Int
        let mediaCount: Int
    }

    // MARK: - 体积预估

    /// 导出前给用户看的体积预估。媒体是大头，文字可忽略不计。
    static func estimateMediaBytes(entries: [JournalEntry], tags: [Tag] = []) -> Int {
        var total = 0
        var counted = Set<String>()
        // 日记本的照片封面也要带走
        for cover in tags.compactMap(\.coverPhotoFilename) where !counted.contains(cover) {
            counted.insert(cover)
            total += fileSize(PhotoPaperIO.photosDirectory.appendingPathComponent(cover))
        }
        for entry in entries {
            for name in entry.photoFilenames where !counted.contains(name) {
                counted.insert(name)
                total += fileSize(PhotoPaperIO.photosDirectory.appendingPathComponent(name))
            }
            for relative in entry.audioURLs where !counted.contains(relative) {
                counted.insert(relative)
                total += fileSize(documentsURL(forRelativePath: relative))
            }
        }
        return total
    }

    // MARK: - 导出

    static func export(
        entries: [JournalEntry],
        letters: [Letter],
        tags: [Tag],
        penPalNotes: [PenPalNote] = [],
        options: Options
    ) throws -> Result {
        guard !entries.isEmpty else { throw ExportError.nothingToExport }

        let fm = FileManager.default
        // 用带 App 名的目录名，因为 NSFileCoordinator 生成的 zip 会以目录名命名
        let stageName = "尺素备份_\(Self.dateStamp())"
        let stage = fm.temporaryDirectory.appendingPathComponent(stageName, isDirectory: true)
        // 上次导出的残留会污染这次的内容
        try? fm.removeItem(at: stage)

        do {
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        } catch {
            throw ExportError.assemblyFailed(error.localizedDescription)
        }
        defer { try? fm.removeItem(at: stage) }

        // 1. 媒体：先拷贝，因为要统计实际字节数写进 manifest
        var mediaBytes = 0
        var mediaCount = 0
        if options.includesMedia {
            let mediaDir = stage.appendingPathComponent(BackupFormat.mediaDirectory, isDirectory: true)
            try? fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)
            (mediaBytes, mediaCount) = copyMedia(entries: entries, tags: tags, into: mediaDir)
        }

        // 2. JSON
        do {
            let entriesFile = BackupEntriesFile(
                entries: entries.map { makeBackupEntry($0, includesMedia: options.includesMedia) }
            )
            try BackupFormat.jsonEncoder.encode(entriesFile)
                .write(to: stage.appendingPathComponent(BackupFormat.entriesFile))

            let lettersFile = BackupLettersFile(
                letters: letters.map(makeBackupLetter),
                // 没有就不写这个字段（而不是写一个空数组），老格式的包长得和以前一样
                penPalNotes: penPalNotes.isEmpty ? nil : penPalNotes.map {
                    BackupPenPalNote(id: $0.id, penPalID: $0.penPalID, text: $0.text, notedAt: $0.notedAt, createdAt: $0.createdAt)
                }
            )
            try BackupFormat.jsonEncoder.encode(lettersFile)
                .write(to: stage.appendingPathComponent(BackupFormat.lettersFile))

            // 日记本按书架顺序写出 —— 导入端按数组顺序接在书架末尾（见 `BackupImporter.merge`），
            // 书架顺序就这样带过去了，备份格式不用为 `sortOrder` 加字段
            let taxonomy = BackupTaxonomyFile(
                tags: tags
                    .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
                    .map { makeBackupTag($0, includesMedia: options.includesMedia) },
                moods: []
            )
            try BackupFormat.jsonEncoder.encode(taxonomy)
                .write(to: stage.appendingPathComponent(BackupFormat.taxonomyFile))

            let manifest = BackupManifest(
                appVersion: appVersion,
                exportedAt: .now,
                counts: .init(entries: entries.count, letters: letters.count, media: mediaCount),
                includesMedia: options.includesMedia,
                mediaTotalBytes: mediaBytes,
                encrypted: options.password != nil
            )
            try BackupFormat.jsonEncoder.encode(manifest)
                .write(to: stage.appendingPathComponent(BackupFormat.manifestFile))
        } catch {
            throw ExportError.assemblyFailed(error.localizedDescription)
        }

        // 3. 打包
        let zipData = try zipDirectory(stage)

        // 4. 加密（可选）
        let payload: Data
        if let password = options.password, !password.isEmpty {
            do {
                payload = try BackupCrypto.encrypt(zipData, password: password)
            } catch {
                throw ExportError.zipFailed(error.localizedDescription)
            }
        } else {
            payload = zipData
        }

        // 5. 落到临时目录交给分享面板
        let outURL = fm.temporaryDirectory
            .appendingPathComponent("\(stageName).\(BackupFormat.fileExtension)")
        try? fm.removeItem(at: outURL)
        do {
            try payload.write(to: outURL, options: .atomic)
        } catch {
            throw ExportError.zipFailed(error.localizedDescription)
        }

        return Result(
            fileURL: outURL,
            byteCount: payload.count,
            entryCount: entries.count,
            mediaCount: mediaCount
        )
    }

    // MARK: - 打包

    /// 用 `NSFileCoordinator(.forUploading)` 把目录读成标准 zip。
    /// 这是 iOS 上唯一公开的 zip 生成途径，产物是标准格式，鸿蒙端可直接解。
    private static func zipDirectory(_ directory: URL) throws -> Data {
        var coordError: NSError?
        var readError: Error?
        var result: Data?

        NSFileCoordinator().coordinate(
            readingItemAt: directory,
            options: [.forUploading],
            error: &coordError
        ) { zipURL in
            do {
                result = try Data(contentsOf: zipURL, options: .mappedIfSafe)
            } catch {
                readError = error
            }
        }

        if let coordError { throw ExportError.zipFailed(coordError.localizedDescription) }
        if let readError { throw ExportError.zipFailed(readError.localizedDescription) }
        guard let result else { throw ExportError.zipFailed("打包结果为空") }
        return result
    }

    // MARK: - 媒体收集

    /// 返回 (总字节数, 文件数)。同一文件被多篇引用时只拷一次。
    private static func copyMedia(entries: [JournalEntry], tags: [Tag], into mediaDir: URL) -> (Int, Int) {
        let fm = FileManager.default
        var bytes = 0
        var copied = Set<String>()

        func copy(from source: URL, name: String) {
            guard !copied.contains(name), fm.fileExists(atPath: source.path) else { return }
            let dest = mediaDir.appendingPathComponent(name)
            do {
                try fm.copyItem(at: source, to: dest)
                copied.insert(name)
                bytes += fileSize(dest)
            } catch {
                // 单个媒体拷贝失败不该让整个备份失败 —— 导入端对缺失媒体有降级处理
                print("⚠️ [Backup] 媒体拷贝失败: \(name) — \(error.localizedDescription)")
            }
        }

        for entry in entries {
            for block in entry.contentBlocks where block.type == .photo {
                if let file = block.photoFilename {
                    copy(from: PhotoPaperIO.photosDirectory.appendingPathComponent(file), name: file)
                }
                if let live = block.livePhotoVideoFilename {
                    copy(from: PhotoPaperIO.photosDirectory.appendingPathComponent(live), name: live)
                }
                // 相机拍的 Live Photo 还有一份未裁原图 —— 不带走的话导入端就配不成对了
                if let still = block.livePhotoStillFilename {
                    copy(from: PhotoPaperIO.photosDirectory.appendingPathComponent(still), name: still)
                }
            }
            for relative in entry.audioURLs {
                // audioURLs 存的是 "audio/xxx.m4a" 这样的相对路径，包内统一用扁平文件名
                let name = (relative as NSString).lastPathComponent
                copy(from: documentsURL(forRelativePath: relative), name: name)
            }
        }
        // 日记本的照片封面
        for cover in tags.compactMap(\.coverPhotoFilename) where !cover.isEmpty {
            copy(from: PhotoPaperIO.photosDirectory.appendingPathComponent(cover), name: cover)
        }
        return (bytes, copied.count)
    }

    // MARK: - 模型 → DTO

    private static func makeBackupEntry(_ entry: JournalEntry, includesMedia: Bool) -> BackupEntry {
        BackupEntry(
            id: entry.id,
            title: entry.title,
            date: entry.date,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            mood: "",
            moodColorHex: nil,
            tags: entry.tags,
            isFavorite: entry.isFavorite,
            weatherCode: entry.weatherCode,
            weatherInfo: entry.weatherInfo,
            locationInfo: entry.locationInfo,
            audio: includesMedia
                ? entry.audioURLs.map { ($0 as NSString).lastPathComponent }
                : [],
            blocks: entry.contentBlocks.map { block in
                BackupBlock(
                    type: block.type.rawValue,
                    text: block.text,
                    styles: block.styles,
                    // 录音块记的是 "audio/xxx.m4a"，包内统一用扁平文件名（同 `audio` 清单）
                    file: includesMedia
                        ? (block.type == .audio ? block.audioFilename.map { ($0 as NSString).lastPathComponent } : block.photoFilename)
                        : nil,
                    liveVideo: includesMedia ? block.livePhotoVideoFilename : nil,
                    liveStill: includesMedia ? block.livePhotoStillFilename : nil,
                    paperStyle: block.paperStyle?.rawValue,
                    position: block.position?.rawValue,
                    rotationAngle: block.rotationAngle,
                    isCover: block.isCover,
                    addedAt: block.addedAt,
                    traceOf: block.traceOf,
                    removedAt: block.removedAt
                )
            }
        )
    }

    private static func makeBackupLetter(_ letter: Letter) -> BackupLetter {
        BackupLetter(
            id: letter.id,
            body: letter.body,
            fromCharacter: letter.fromCharacter,
            toName: letter.toName,
            stationery: letter.stationery,
            status: letter.status,
            triggerKind: letter.triggerKind,
            generatedAt: letter.generatedAt,
            deliveredAt: letter.deliveredAt,
            readAt: letter.readAt,
            relatedEntryIDs: (letter.relatedEntries ?? []).map(\.id),
            penPalID: letter.penPalID,
            translatedBody: letter.translatedBody,
            danger: letter.danger,
            postage: letter.postage
        )
    }

    private static func makeBackupTag(_ tag: Tag, includesMedia: Bool) -> BackupTag {
        BackupTag(
            id: tag.id,
            name: tag.name,
            colorID: tag.colorID,
            textureID: tag.textureID,
            createdAt: tag.createdAt,
            coverFile: includesMedia ? tag.coverPhotoFilename : nil,
            // 「仅文字」导出不带照片，版式也就没意义了
            coverLayout: includesMedia ? tag.coverLayoutID : nil,
            subtitle: tag.subtitle
        )
    }

    // MARK: - 工具

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: .now)
    }

    private static func documentsURL(forRelativePath path: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(path)
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
