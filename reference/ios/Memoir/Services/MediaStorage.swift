import Foundation
import SwiftData

/// 沙盒里媒体文件的统计与回收。
///
/// **为什么需要它**：照片、Live Photo 的原图与视频、录音都是**磁盘上的独立文件**，
/// 不在 SwiftData 里 —— SwiftData 只存文件名。这意味着：
///
/// - 删日记时若忘了删文件，文件就永远留着（用户看不见，也没有任何入口能删）
/// - 写盘成功但插入日记失败（中途取消、App 被杀）的产物同样是孤儿
/// - 一张相机拍的 Live Photo 要占三份（方图 + 未裁原图 + .mov），攒起来很可观
///
/// 所以要有一条「以库为准，扫盘对账」的回收路径。
@MainActor
enum MediaStorage {

    /// 媒体占用概况
    struct Usage {
        /// 被日记引用的文件数与字节数
        var referencedCount = 0
        var referencedBytes = 0
        /// 没有任何日记引用的文件数与字节数（可安全清理）
        var orphanCount = 0
        var orphanBytes = 0

        var totalBytes: Int { referencedBytes + orphanBytes }
    }

    // MARK: - 目录

    static var photosDirectory: URL { PhotoPaperIO.photosDirectory }

    static var audioDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - 统计

    /// 扫一遍磁盘并与库里的引用对账。
    ///
    /// ⚠️ 只统计不删除。删除请显式调 `reclaimOrphans`，别让扫描顺手改东西。
    static func usage(in context: ModelContext) -> Usage {
        let referenced = referencedFilenames(in: context)
        var usage = Usage()

        for (dir, prefix) in [(photosDirectory, ""), (audioDirectory, "audio/")] {
            for url in files(in: dir) {
                let name = url.lastPathComponent
                // 录音在库里存的是 "audio/xxx.m4a" 这样的相对路径，照片存的是裸文件名
                let key = prefix + name
                let size = fileSize(url)
                if referenced.contains(key) || referenced.contains(name) {
                    usage.referencedCount += 1
                    usage.referencedBytes += size
                } else {
                    usage.orphanCount += 1
                    usage.orphanBytes += size
                }
            }
        }
        return usage
    }

    // MARK: - 回收

    /// 删掉所有没被任何日记引用的媒体文件，返回释放的字节数。
    ///
    /// **以库为准**：每次都重新读一遍全部日记的引用，不依赖任何缓存或标记 ——
    /// 这是在删用户的文件，宁可多扫一遍库，也不能因为一份过期的清单误删还在用的照片。
    @discardableResult
    static func reclaimOrphans(in context: ModelContext) -> Int {
        let referenced = referencedFilenames(in: context)
        // 一篇日记、一份草稿都没有时才允许"无引用即清空"：没有引用**且库里确实是空的**，
        // 才说明这些文件真是孤儿。否则多半是库还没加载好（迁移中 / CloudKit 首次同步未完成），
        // 这时候「没有引用」是假象，照删就会把用户的照片全清光。
        // fetchCount 失败时给 -1，让它落进"不清理"这一侧 —— 读不到库就更不该动文件。
        let entryCount = (try? context.fetchCount(FetchDescriptor<JournalEntry>())) ?? -1
        let draftCount = (try? context.fetchCount(FetchDescriptor<DraftEntry>())) ?? -1
        // 日记本的照片封面同理（2026-10 P2）：只有封面、还没写日记的新设备，也不能被当成空库
        let coverCount = (try? context.fetchCount(FetchDescriptor<Tag>(
            predicate: #Predicate { $0.coverPhotoFilename != nil }
        ))) ?? -1
        guard !referenced.isEmpty || (entryCount == 0 && draftCount == 0 && coverCount == 0) else {
            return 0
        }

        var freed = 0
        for (dir, prefix) in [(photosDirectory, ""), (audioDirectory, "audio/")] {
            for url in files(in: dir) {
                let name = url.lastPathComponent
                guard !referenced.contains(prefix + name), !referenced.contains(name) else { continue }
                let size = fileSize(url)
                if (try? FileManager.default.removeItem(at: url)) != nil {
                    freed += size
                }
            }
        }

        // 云端记录一并清掉，否则本地删了、iCloud 里还占着空间，
        // 而且下次 hydrateFromCloud 会把它们又写回磁盘 —— 清理就白做了
        var removedAssets = 0
        for asset in assets(in: context) {
            let isReferenced = referenced.contains(asset.filename)
                || referenced.contains("\(MediaAsset.audioDirectoryKey)/\(asset.filename)")
            guard !isReferenced else { continue }
            context.delete(asset)
            removedAssets += 1
        }
        if removedAssets > 0 {
            try? context.save()
        }
        return freed
    }

    // MARK: - 跨设备同步（借 CloudKit 的力）

    /// **磁盘 → 云**：把被日记引用、但还没有 `MediaAsset` 记录的文件补进库，
    /// 交给 CloudKit 同步走。返回新登记的文件数。
    ///
    /// **刻意做成"事后对账"而不是"写入时双写"**：照片的写入点散在写日记页、详情页插图、
    /// 备份包导入等好几处，逐个改一遍既啰嗦又迟早漏一个。
    /// 以「库里引用了什么」为唯一依据来补，天然覆盖所有写入路径，包括以后新加的。
    @discardableResult
    static func syncToCloud(in context: ModelContext, limit: Int = 40) -> Int {
        let referenced = referencedFilenames(in: context)
        guard !referenced.isEmpty else { return 0 }
        let existing = Set(assets(in: context).map(\.filename))

        var added = 0
        for (dir, key) in [(photosDirectory, MediaAsset.photosDirectoryKey),
                           (audioDirectory, MediaAsset.audioDirectoryKey)] {
            for url in files(in: dir) {
                guard added < limit else { break }
                let name = url.lastPathComponent
                // 只登记「日记真的在用」的文件，孤儿不上传 —— 别拿用户的 iCloud 空间存垃圾
                let isReferenced = referenced.contains(name)
                    || referenced.contains("\(MediaAsset.audioDirectoryKey)/\(name)")
                guard isReferenced, !existing.contains(name) else { continue }
                guard let data = try? Data(contentsOf: url) else { continue }
                context.insert(MediaAsset(filename: name, data: data, directory: key))
                added += 1
            }
        }
        if added > 0 {
            try? context.save()
            print("☁️ [MediaAsset] 登记 \(added) 个文件待同步")
        }
        return added
    }

    /// **云 → 磁盘**：把已同步下来、但本机磁盘上没有的文件写回去。返回恢复的文件数。
    ///
    /// 这是第二台设备"日记有字没图"的解药 —— CloudKit 把 `MediaAsset` 同步过来之后，
    /// 由它落成磁盘文件，读取路径（`PhotoPaperIO.loadImage`）就照常工作，不用改。
    @discardableResult
    static func hydrateFromCloud(in context: ModelContext) -> Int {
        let fm = FileManager.default
        var restored = 0
        for asset in assets(in: context) {
            let dir = asset.directory == MediaAsset.audioDirectoryKey ? audioDirectory : photosDirectory
            let url = dir.appendingPathComponent(asset.filename)
            guard !fm.fileExists(atPath: url.path), !asset.data.isEmpty else { continue }
            if (try? asset.data.write(to: url, options: .atomic)) != nil {
                restored += 1
            }
        }
        if restored > 0 {
            print("☁️ [MediaAsset] 从 iCloud 恢复 \(restored) 个文件")
        }
        return restored
    }

    /// 两个方向跑一遍。App 启动和回到前台时调用。
    static func reconcileWithCloud(in context: ModelContext) {
        hydrateFromCloud(in: context)
        syncToCloud(in: context)
    }

    // MARK: - 内部

    private static func assets(in context: ModelContext) -> [MediaAsset] {
        (try? context.fetch(FetchDescriptor<MediaAsset>())) ?? []
    }

    /// 库里所有**日记、草稿、日记本封面**引用到的文件名集合（照片是裸名，录音是 "audio/xxx" 相对路径）
    ///
    /// ⚠️ **草稿必须算在内**。草稿里的照片在插入那一刻就落盘了，却还没有任何 `JournalEntry`
    /// 引用它 —— 漏算的话，用户存了草稿再去设置里点一次「清理残留文件」，草稿里的图就被当孤儿删了。
    ///
    /// ⚠️ **日记本的照片封面也必须算在内**（2026-10 P2）。漏算的后果更重：
    /// 「清理残留文件」会把所有封面连同 iCloud 里的副本一起删掉；而且 `syncToCloud` 只登记被引用的文件，
    /// 封面就永远上不了云，换台设备就没了。
    private static func referencedFilenames(in context: ModelContext) -> Set<String> {
        var names = Set<String>()
        for entry in (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? [] {
            for block in entry.contentBlocks where block.type == .photo {
                if let f = block.photoFilename { names.insert(f) }
                if let f = block.livePhotoVideoFilename { names.insert(f) }
                if let f = block.livePhotoStillFilename { names.insert(f) }
            }
            for relative in entry.audioURLs {
                names.insert(relative)
                names.insert((relative as NSString).lastPathComponent)
            }
        }
        for draft in (try? context.fetch(FetchDescriptor<DraftEntry>())) ?? [] {
            names.formUnion(draft.referencedMediaNames)
        }
        for tag in (try? context.fetch(FetchDescriptor<Tag>())) ?? [] {
            if let cover = tag.coverPhotoFilename, !cover.isEmpty { names.insert(cover) }
        }
        return names
    }

    private static func files(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
