import Foundation
import SwiftData
import ZIPFoundation

/// 把 `.memoir` 备份包读回本机。
///
/// 流程：读文件 →（加密则解密）→ 解压到临时目录 → 校验 manifest → 按 id 合并进库 → 清理临时目录。
///
/// **合并策略只有一种：跳过已存在的，绝不覆盖**（EXPORT_FORMAT.md §5 决策 3）。
/// 唯一要用户选的是同名日记本合并还是分开（`TagConflictPolicy`），两种都只增不减。
/// 不提供「替换全部」—— 那个功能一次误操作就能清空用户所有日记，
/// 收益远小于风险。导入在任何情况下都只会让库里的东西变多，不会变少。
///
/// **解压用 ZIPFoundation** —— iOS 没有公开的解压 API。这是项目里唯一的第三方依赖，
/// 引它的理由见 EXPORT_FORMAT.md §5.3 决策 1：备份恢复是「只能成功不能失败」的路径。
/// `nonisolated`：解密 + 解压是重活（加密的大包能跑好几秒），必须能在后台线程上跑，
/// 否则导入面板一弹出来主线程就卡死，连转菊花都不会动。
/// 只有真正碰 SwiftData 的 `merge` 单独标 `@MainActor`。
nonisolated enum BackupImporter {

    // MARK: - 错误

    enum ImportError: LocalizedError {
        case unreadableFile
        /// 包是加密的，但还没拿到密码 —— 不是失败，是要 UI 去问用户
        case needsPassword
        case wrongPassword
        case notABackup
        case unsupportedVersion(Int)
        case stagingFailed(String)
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            // 会显示给用户，`Text(String)` 不查表 —— 必须显式 NSLocalizedString
            case .unreadableFile:
                return NSLocalizedString("读不到这个文件，可能已被移动或删除", bundle: .appLanguage, comment: "备份导入错误")
            case .needsPassword:
                return NSLocalizedString("这个备份包需要密码", bundle: .appLanguage, comment: "备份导入错误")
            case .wrongPassword:
                return NSLocalizedString("密码不对，请重新输入", bundle: .appLanguage, comment: "备份导入错误")
            case .notABackup:
                return NSLocalizedString("这不是尺素的备份包，或者文件已损坏", bundle: .appLanguage, comment: "备份导入错误")
            case .unsupportedVersion(let v):
                return String(format: NSLocalizedString("这个备份包来自更新版本的尺素（格式 v%lld），请先把 App 更新到最新版再导入", bundle: .appLanguage, comment: "备份导入错误，%lld 是格式版本号"), v)
            case .stagingFailed(let m):
                return String(format: NSLocalizedString("解压时出错：%@", bundle: .appLanguage, comment: "备份导入错误，%@ 是底层原因"), m)
            case .saveFailed(let m):
                return String(format: NSLocalizedString("写入数据时出错：%@", bundle: .appLanguage, comment: "备份导入错误，%@ 是底层原因"), m)
            }
        }
    }

    // MARK: - 打开后的包

    /// 已解压待导入的包。**持有临时目录，用完必须调 `discard` **。
    struct Package: Identifiable {
        let id = UUID()
        let manifest: BackupManifest
        /// `manifest.json` 所在目录
        let root: URL
        /// 本次解压的临时根目录（`root` 在它里面），清理时删这个
        let staging: URL

        var mediaDirectory: URL {
            root.appendingPathComponent(BackupFormat.mediaDirectory, isDirectory: true)
        }
    }

    /// 导入结果。给用户看的那句话就是从这里拼的。
    struct Summary {
        var entriesImported = 0
        var entriesSkipped = 0
        var lettersImported = 0
        var lettersSkipped = 0
        var tagsImported = 0
        /// 包里引用了、但 media/ 下找不到的照片 / 录音数
        var missingMedia = 0
    }

    // MARK: - 第一步：这个包加密了吗

    /// 只读文件头判断，不整个读进内存 —— 备份包可能有上百 MB。
    static func isEncrypted(fileURL: URL) throws -> Bool {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw ImportError.unreadableFile
        }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: BackupCrypto.magic.count)) ?? Data()
        return head == BackupCrypto.magic
    }

    // MARK: - 第二步：解密 + 解压 + 校验（还不落库）

    /// 打开备份包但**先不写库** —— 让用户看清「这里面是什么、什么时候导出的」再决定导不导。
    /// 成功后调用方有责任在用完时调 `discard(_:)`。
    static func open(fileURL: URL, password: String?) throws -> Package {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }

        guard let raw = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            throw ImportError.unreadableFile
        }

        // 1. 解密（不加密的包就是纯 zip，直接用）
        let zipData: Data
        if BackupCrypto.isEncrypted(raw) {
            guard let password, !password.isEmpty else { throw ImportError.needsPassword }
            do {
                zipData = try BackupCrypto.decrypt(raw, password: password)
            } catch BackupCrypto.CryptoError.wrongPassword {
                throw ImportError.wrongPassword
            } catch {
                throw ImportError.notABackup
            }
        } else {
            zipData = raw
        }

        // 2. 解压到独立的临时目录（用 UUID 命名，避免两次导入互相踩）
        let fm = FileManager.default
        // 开工前先扫一遍上次没扫干净的：用户在导入面板开着时把 App 划掉，
        // `onDisappear` 就不会走，那份解压出来的东西（可能上百 MB）会一直留在 tmp/ 里。
        sweepStaleStaging()
        let staging = fm.temporaryDirectory
            .appendingPathComponent("\(stagingPrefix)\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            throw ImportError.stagingFailed(error.localizedDescription)
        }

        let zipURL = staging.appendingPathComponent("payload.zip")
        let extracted = staging.appendingPathComponent("package", isDirectory: true)
        do {
            try zipData.write(to: zipURL, options: .atomic)
        } catch {
            try? fm.removeItem(at: staging)
            throw ImportError.stagingFailed(error.localizedDescription)
        }
        do {
            // 默认 allowUncontainedSymlinks = false，且库内部会校验条目路径没跑出 destination，
            // 恶意包没法借解压往沙箱别处写文件。
            try fm.unzipItem(at: zipURL, to: extracted)
        } catch {
            try? fm.removeItem(at: staging)
            throw ImportError.notABackup
        }
        // 解压完 zip 本体就没用了，早点删省一份体积（大包时这一份可能就是上百 MB）
        try? fm.removeItem(at: zipURL)

        // 3. 找到 manifest.json 所在目录
        guard let root = findPackageRoot(in: extracted) else {
            try? fm.removeItem(at: staging)
            throw ImportError.notABackup
        }

        // 4. 读 manifest 并判版本
        guard
            let data = try? Data(contentsOf: root.appendingPathComponent(BackupFormat.manifestFile)),
            let manifest = try? BackupFormat.jsonDecoder.decode(BackupManifest.self, from: data)
        else {
            try? fm.removeItem(at: staging)
            throw ImportError.notABackup
        }
        // §2.4 规则 1：版本比自己认识的新就直接拒绝，不做半吊子解析
        guard manifest.formatVersion <= BackupFormat.currentVersion else {
            try? fm.removeItem(at: staging)
            throw ImportError.unsupportedVersion(manifest.formatVersion)
        }

        return Package(manifest: manifest, root: root, staging: staging)
    }

    /// 删掉解压出来的临时文件。导入完成、取消、出错都要调。
    static func discard(_ package: Package) {
        try? FileManager.default.removeItem(at: package.staging)
    }

    private static let stagingPrefix = "memoir-import-"

    /// 清掉历次没来得及删的解压目录。
    private static func sweepStaleStaging() {
        let fm = FileManager.default
        let leftovers = (try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in leftovers where url.lastPathComponent.hasPrefix(stagingPrefix) {
            try? fm.removeItem(at: url)
        }
    }

    /// 系统把外部文件拷进 `Documents/Inbox/` 再交给我们（见 Info.plist 里
    /// `LSSupportsOpeningDocumentsInPlace = false` 的说明）。读完得自己扫地，
    /// 否则用户每导入一次就在沙箱里留一份几十 MB 的死文件。
    static func cleanUpInboxCopy(of fileURL: URL) {
        let inbox = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
        guard fileURL.standardizedFileURL.path.hasPrefix(inbox.standardizedFileURL.path) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - 同名日记本

    /// 包里的日记本和本机的同名时怎么办。
    /// 只有「两边都挂着日记」的同名本子才会走到这个选择，其余一律合并（见 `tagConflicts`）。
    enum TagConflictPolicy {
        /// 导入的日记放进本机已有的同名日记本（也是一直以来的默认行为）
        case merge
        /// 作为新日记本导入，名字后面加序号：「旅行」→「旅行 2」
        case keepSeparate
    }

    /// 需要问用户的同名日记本（返回包里的写法）。空数组 = 不用问，直接 `merge`。
    ///
    /// 「同名」按 `Tag.nameKey` 比（忽略大小写 / 全半角 / 首尾空白），而且要**两边都挂着日记**：
    /// - 有一边是空本子时，合并不会把任何东西混在一起，不必打扰用户 ——
    ///   两台设备各有一套默认的「生活 / 旅行…」，不这么筛的话几乎每次导入都会弹窗
    /// - 包里那边只算**这次真会新增的**日记：重导同一个包时它们全会跳过，也不该问
    @MainActor
    static func tagConflicts(in package: Package, context: ModelContext) -> [String] {
        planTagNames(entries: decodeEntries(in: package), package: package, context: context, policy: .merge)
            .conflicts
    }

    /// 包里每个日记本名字导入后叫什么。
    private struct TagNamePlan {
        /// 包里的写法 → 导入后用的名字。不在表里的原样用
        var rename: [String: String] = [:]
        var conflicts: [String] = []
    }

    /// 日记靠名字挂在日记本上（`JournalEntry.tags`），所以「合并」和「分开」的区别全在名字：
    /// - 合并：包里的「travel」改写成本机的「Travel」，导入的日记自然落进那本
    /// - 分开：改写成一个没人用过的「travel 2」，连同它名下导入的日记一起改
    ///
    /// 本机没有的名字也要进表：包里自己可能就有「Travel」和「travel」两种写法
    /// （新规则之前建的），导入后要并成一个，否则会在本机造出两本同名的。
    @MainActor
    private static func planTagNames(
        entries: [BackupEntry],
        package: Package,
        context: ModelContext,
        policy: TagConflictPolicy
    ) -> TagNamePlan {
        let localTags = ((try? context.fetch(FetchDescriptor<Tag>())) ?? [])
            .sorted { $0.createdAt < $1.createdAt }
        var localNameByKey: [String: String] = [:]
        for tag in localTags where localNameByKey[Tag.nameKey(tag.name)] == nil {
            localNameByKey[Tag.nameKey(tag.name)] = tag.name
        }

        let localEntries = (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []
        let localIDs = Set(localEntries.map(\.id))
        let localKeysWithEntries = Set(localEntries.flatMap(\.tags).map(Tag.nameKey))
        // 只算导入后真会落进某一本的：同时挂着几本的日记按单本规则会退回「全部日记」，
        // 它不会进任何一本，也就谈不上和本机那本「混在一起」
        let incomingKeysWithEntries = Set(
            entries
                .filter { !localIDs.contains($0.id) }
                .map { Set($0.tags.map(Tag.nameKey)) }
                .filter { $0.count == 1 }
                .flatMap { $0 }
        )

        // 包里出现过的全部名字：日记本定义 + 日记上挂的，按出现顺序去重
        let taxonomyNames = decodeFile(BackupTaxonomyFile.self, named: BackupFormat.taxonomyFile, in: package)?
            .tags.map(\.name) ?? []
        var seen = Set<String>()
        let incomingNames = (taxonomyNames + entries.flatMap(\.tags)).filter { seen.insert($0).inserted }

        // 起新名字时要避开的：本机的日记本、本机日记上挂着的名字（含已删日记本留下的）、包里的全部名字
        var taken = localTags.map(\.name) + localEntries.flatMap(\.tags) + incomingNames

        var plan = TagNamePlan()
        var finalNameByKey: [String: String] = [:]
        for name in incomingNames {
            let key = Tag.nameKey(name)
            if let decided = finalNameByKey[key] {
                plan.rename[name] = decided
                continue
            }
            let final: String
            if let local = localNameByKey[key] {
                let conflicts = localKeysWithEntries.contains(key) && incomingKeysWithEntries.contains(key)
                if conflicts { plan.conflicts.append(name) }
                if conflicts && policy == .keepSeparate {
                    final = Tag.uniqueName(basedOn: name, avoiding: taken)
                    taken.append(final)
                } else {
                    final = local
                }
            } else {
                final = name
            }
            finalNameByKey[key] = final
            plan.rename[name] = final
        }
        return plan
    }

    // MARK: - 第三步：合并进库

    /// 按 id 合并。**已存在的一律跳过，不覆盖**。
    /// `tagPolicy` 只影响 `tagConflicts` 报出来的那几本，其余同名日记本一律合并。
    @MainActor
    static func merge(
        _ package: Package,
        into context: ModelContext,
        tagPolicy: TagConflictPolicy = .merge
    ) throws -> Summary {
        var summary = Summary()
        let incomingEntries = decodeEntries(in: package)
        let tagNames = planTagNames(entries: incomingEntries, package: package, context: context, policy: tagPolicy)

        // 媒体文件在包内是扁平文件名，导入时可能因重名改名 —— 这两张表记住改成了什么，
        // 同一个源文件被多篇日记引用时也只拷一次。
        var photoNames: [String: String] = [:]
        var audioNames: [String: String] = [:]

        // 1. 日记本（包里的旧心情标签 `moods` 2026-10-17 起作废，直接跳过）
        //
        // **按名字去重，不按 id**：`JournalEntry.tags` 存的是名字字符串，名字才是日记本的真实身份。
        // 而每台设备首启会各自生成一套默认日记本（id 各不相同），
        // 按 id 去重的话导入一次就多出一整套同名的「生活」「旅行」，用户侧看着就是重复。
        // 日记本的名字先过一遍 `tagNames`（同名合并 / 分开导入的改名都在那里决定）。
        if let taxonomy = decodeFile(BackupTaxonomyFile.self, named: BackupFormat.taxonomyFile, in: package) {
            let existingTags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
            // 判重键 → 包里同名的要并进的那本。同一个键本机有多本（新规则之前建的大小写不同的）时取最早建的，
            // 和 `planTagNames` 改写名字时挑的是同一本
            var tagsByKey: [String: Tag] = [:]
            for tag in existingTags.sorted(by: { $0.createdAt < $1.createdAt }) where tagsByKey[Tag.nameKey(tag.name)] == nil {
                tagsByKey[Tag.nameKey(tag.name)] = tag
            }
            var takenTagIDs = Set(existingTags.map(\.id))
            // 导入的日记本按包里的顺序接在书架末尾
            var nextTagOrder = Tag.nextSortOrder(after: existingTags)
            for t in taxonomy.tags {
                let name = tagNames.rename[t.name] ?? t.name
                if let target = tagsByKey[Tag.nameKey(name)] {
                    fillMissingCover(of: target, from: t, package: package, photoNames: &photoNames)
                    continue
                }
                // 下架的颜色就近换成保留色；完全不认识的（更新版本 / 鸿蒙端新加的）原样留着，
                // 渲染时 `Tag.bookColor` 会兜底，等这台设备升级后自然认得。
                // 纹理不读包里的：2026-10 起只有亚麻（见 `BookTexture`）
                let colorID = BookColor.retiredColorReplacement[t.colorID]?.rawValue ?? t.colorID
                let tag = Tag(name: name, colorID: colorID)
                tag.sortOrder = nextTagOrder
                nextTagOrder += 1
                // 照片封面：包里找不到文件就当没有封面（纯色），不算错、不阻断
                tag.coverPhotoFilename = t.coverFile.flatMap {
                    adoptMedia(named: $0, from: package.mediaDirectory, into: PhotoPaperIO.photosDirectory, cache: &photoNames)
                }
                // 版式只跟着照片走；不认识的值（更新版本加的）原样留着，显示时按满版
                tag.coverLayoutID = tag.coverPhotoFilename == nil ? nil : t.coverLayout
                tag.subtitle = t.subtitle.flatMap { $0.isEmpty ? nil : String($0.prefix(CoverEdit.subtitleMaxLength)) }
                if !takenTagIDs.contains(t.id) { tag.id = t.id }
                tag.createdAt = t.createdAt
                context.insert(tag)
                tagsByKey[Tag.nameKey(name)] = tag
                takenTagIDs.insert(tag.id)
                summary.tagsImported += 1
            }

        }

        // 2. 日记
        let existingEntries = (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []
        var entriesByID = Dictionary(existingEntries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for be in incomingEntries {
            guard entriesByID[be.id] == nil else {
                summary.entriesSkipped += 1
                continue
            }

            let entry = JournalEntry(
                title: be.title,
                content: "",
                date: be.date,
                tags: renamedTags(be.tags, with: tagNames),
                isFavorite: be.isFavorite
            )
            entry.id = be.id
            // 写完时的心情：愉悦度夹在 -1…1；情绪词原样收（不认识的 key 留着，显示时跳过）
            entry.moodValence = be.moodValence.map { min(max($0, -1), 1) }
            entry.moodLabels = be.moodLabels
            entry.weatherCode = be.weatherCode
            entry.weatherInfo = be.weatherInfo
            entry.locationInfo = be.locationInfo

            // 内容块。照片文件缺失时**只丢这一块**，日记其余部分照常导入（§2.4 规则 3）。
            var blocks: [ContentBlock] = []
            for bb in be.blocks {
                switch bb.type {
                case ContentBlockType.text.rawValue:
                    var block = ContentBlock(text: bb.text ?? "")
                    block.styles = bb.styles
                    blocks.append(block)

                case ContentBlockType.audio.rawValue:
                    // 录音文件和下面 `be.audio` 清单是同一个，共用缓存，改了名两边一致。
                    // 文件缺了只丢这个位置，不计缺失（清单那边会计一次）
                    guard let file = bb.file,
                          let local = adoptMedia(named: file, from: package.mediaDirectory,
                                                 into: audioDirectory, cache: &audioNames)
                    else { continue }
                    var audio = ContentBlock(audioFilename: "audio/\(local)")
                    audio.addedAt = bb.addedAt
                    blocks.append(audio)

                case ContentBlockType.trace.rawValue:
                    // 痕迹不带文件，原样还原
                    var trace = ContentBlock(traceOf: ContentBlockType(rawValue: bb.traceOf ?? "") ?? .photo,
                                             removedAt: bb.removedAt.map(Date.init(timeIntervalSince1970:)) ?? .now)
                    trace.removedAt = bb.removedAt ?? trace.removedAt
                    blocks.append(trace)

                case ContentBlockType.photo.rawValue:
                    guard
                        let file = bb.file,
                        let localName = adoptMedia(
                            named: file,
                            from: package.mediaDirectory,
                            into: PhotoPaperIO.photosDirectory,
                            cache: &photoNames
                        )
                    else {
                        summary.missingMedia += 1
                        continue
                    }
                    // Live Photo 的视频部分丢了不算错 —— 降级成一张静态图即可，不计入缺失
                    let live = bb.liveVideo.flatMap {
                        adoptMedia(
                            named: $0,
                            from: package.mediaDirectory,
                            into: PhotoPaperIO.photosDirectory,
                            cache: &photoNames
                        )
                    }
                    var block = ContentBlock(
                        photoFilename: localName,
                        livePhotoVideoFilename: live,
                        position: bb.position.flatMap(PhotoPosition.init(rawValue:)) ?? .right,
                        paperStyle: bb.paperStyle.flatMap(PaperStyle.init(rawValue:)) ?? .original
                    )
                    // 相机拍的 Live Photo 带的未裁原图；缺了就退回用 file 配对（多半配不上，
                    // 但 LivePhotoView 会兜底显示静态图，不会空白）
                    block.livePhotoStillFilename = bb.liveStill.flatMap {
                        adoptMedia(
                            named: $0,
                            from: package.mediaDirectory,
                            into: PhotoPaperIO.photosDirectory,
                            cache: &photoNames
                        )
                    }
                    if let angle = bb.rotationAngle { block.rotationAngle = angle }
                    block.isCover = bb.isCover
                    block.addedAt = bb.addedAt
                    blocks.append(block)

                default:
                    // 未来版本新增的块类型 —— 忽略，不阻断（§2.4 规则 2）
                    continue
                }
            }
            // ⚠️ 这个 setter 会重算 content / wordCount，并把 updatedAt 抹成 now，
            // 所以时间戳必须放在它之后恢复。
            entry.contentBlocks = blocks

            var audio: [String] = []
            for name in be.audio {
                guard let local = adoptMedia(
                    named: name,
                    from: package.mediaDirectory,
                    into: audioDirectory,
                    cache: &audioNames
                ) else {
                    summary.missingMedia += 1
                    continue
                }
                audio.append("audio/\(local)")
            }
            entry.audioURLs = audio

            entry.createdAt = be.createdAt
            entry.updatedAt = be.updatedAt

            context.insert(entry)
            entriesByID[be.id] = entry
            summary.entriesImported += 1
        }

        // 3. 来信
        let existingLetters = (try? context.fetch(FetchDescriptor<Letter>())) ?? []
        var letterIDs = Set(existingLetters.map(\.id))

        for bl in decodeLetters(in: package) {
            guard !letterIDs.contains(bl.id) else {
                summary.lettersSkipped += 1
                continue
            }
            let letter = Letter()
            letter.id = bl.id
            letter.body = bl.body
            letter.fromCharacter = bl.fromCharacter
            // 老包 / 鸿蒙包可能没有这个字段，解成 nil 即可（抬头退回只写「致」）
            letter.toName = bl.toName
            // 信纸同理：老包没有 → nil（普通信纸）。火漆信导回来还是火漆信，不看现在是不是会员
            letter.stationery = bl.stationery
            // status / triggerKind 存原始字符串而不过一遍枚举：后端会新增取值
            // （比如 trigger_kind = "welcome"），这一端还不认识的值也不该在导入时被抹掉。
            letter.status = bl.status
            letter.triggerKind = bl.triggerKind
            letter.generatedAt = bl.generatedAt
            letter.deliveredAt = bl.deliveredAt
            letter.readAt = bl.readAt
            letter.updatedAt = bl.generatedAt
            // 世界笔友：老包、鸿蒙包没有这几个字段 → nil，就是「自己起名的那位的信」
            letter.penPalID = bl.penPalID
            letter.translatedBody = bl.translatedBody
            letter.danger = bl.danger
            letter.postage = bl.postage
            context.insert(letter)
            // 关系要在 insert 之后连，两边都得先在同一个 context 里
            letter.relatedEntries = bl.relatedEntryIDs.compactMap { entriesByID[$0] }
            letterIDs.insert(bl.id)
            summary.lettersImported += 1
        }

        // 4. 笔友手记：按 id 去重，本机已有的不动（同一位的画像导进来有两份也不要紧：寄信只带新的那份，下次重写时并掉）
        let existingNotes = (try? context.fetch(FetchDescriptor<PenPalNote>())) ?? []
        var noteIDs = Set(existingNotes.map(\.id))
        for bn in decodePenPalNotes(in: package) where !noteIDs.contains(bn.id) && !bn.penPalID.isEmpty {
            let note = PenPalNote(penPalID: bn.penPalID, text: bn.text, notedAt: bn.notedAt)
            note.id = bn.id
            note.createdAt = bn.createdAt
            note.kind = bn.kind ?? PenPalNote.Kind.recent.rawValue
            note.updatedAt = bn.updatedAt
            context.insert(note)
            noteIDs.insert(bn.id)
        }

        // 5. 情绪小结：按 id 去重；本机已经有同一期的也不导（各自写过一份，留本机的）
        let existingSummaries = (try? context.fetch(FetchDescriptor<MoodSummary>())) ?? []
        var summaryIDs = Set(existingSummaries.map(\.id))
        var summaryPeriods = existingSummaries
        for bs in decodeMoodSummaries(in: package) where !summaryIDs.contains(bs.id) {
            guard let period = MoodSummary.Period(rawValue: bs.period),
                  !summaryPeriods.contains(where: { $0.periodKind == period && abs($0.periodStart.timeIntervalSince(bs.periodStart)) < 12 * 3600 })
            else { continue }
            let item = MoodSummary(period: period, periodStart: bs.periodStart, periodEnd: bs.periodEnd, text: bs.text,
                                   suggestions: bs.suggestions, language: bs.language, entryCount: bs.entryCount, heavy: bs.heavy)
            item.id = bs.id
            item.createdAt = bs.createdAt
            context.insert(item)
            summaryIDs.insert(bs.id)
            summaryPeriods.append(item)
        }

        do {
            try context.save()
        } catch {
            throw ImportError.saveFailed(error.localizedDescription)
        }
        return summary
    }

    /// 日记上挂的日记本名字按 `plan` 改写，再按单本规则整理：
    /// 改写后重复的（「Travel」「travel」并成一个）算一本；仍多于一本的退回「全部日记」
    @MainActor
    private static func renamedTags(_ tags: [String], with plan: TagNamePlan) -> [String] {
        JournalEntry.singleNotebook(tags.map { plan.rename[$0] ?? $0 })
    }

    // MARK: - 包内定位

    /// 找到 `manifest.json` 所在的目录。
    ///
    /// 导出端用 `NSFileCoordinator(.forUploading)` 打包，产物**多套一层同名目录**
    /// （`尺素备份_20260805/manifest.json`）；鸿蒙端或手工打的包则可能是平的。
    /// 两种都得认，所以先看根目录，再看下一层。
    private static func findPackageRoot(in directory: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.appendingPathComponent(BackupFormat.manifestFile).path) {
            return directory
        }
        let children = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for child in children {
            // macOS 打的 zip 会塞一个 __MACOSX 元数据目录进来
            guard child.lastPathComponent != "__MACOSX",
                  (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            if fm.fileExists(atPath: child.appendingPathComponent(BackupFormat.manifestFile).path) {
                return child
            }
        }
        return nil
    }

    /// 读包里的某个 json。文件不存在或整体解析失败都返回 nil ——
    /// 调用方把它当「这部分没有」处理，不让一个坏文件毁掉整次导入。
    private static func decodeFile<T: Decodable>(_ type: T.Type, named name: String, in package: Package) -> T? {
        guard let data = try? Data(contentsOf: package.root.appendingPathComponent(name)) else { return nil }
        return try? BackupFormat.jsonDecoder.decode(type, from: data)
    }

    /// 单条容错的解码壳：解不动就是 nil，不往上抛。
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    private struct LenientEntriesFile: Decodable { var entries: [Lenient<BackupEntry>] }
    private struct LenientLettersFile: Decodable { var letters: [Lenient<BackupLetter>] }

    /// 日记和来信是用户真正的东西，读法比 taxonomy 宽一档：
    /// 整体解不动时**退回逐条解**，能救几篇救几篇。
    /// 一篇日记的日期字段坏了就让另外 499 篇也回不来，那是最不该发生的事。
    private static func decodeEntries(in package: Package) -> [BackupEntry] {
        guard let data = try? Data(contentsOf: package.root.appendingPathComponent(BackupFormat.entriesFile))
        else { return [] }
        if let file = try? BackupFormat.jsonDecoder.decode(BackupEntriesFile.self, from: data) {
            return file.entries
        }
        let salvaged = try? BackupFormat.jsonDecoder.decode(LenientEntriesFile.self, from: data)
        return salvaged?.entries.compactMap(\.value) ?? []
    }

    /// 「他记得的事」：这一项坏了不影响信和日记（单独解，解不动就当没有）
    /// 情绪小结坏了不影响日记的导入：单独解析，解不动就当没有
    private static func decodeMoodSummaries(in package: Package) -> [BackupMoodSummary] {
        struct SummariesOnly: Decodable { var moodSummaries: [Lenient<BackupMoodSummary>]? }
        guard let data = try? Data(contentsOf: package.root.appendingPathComponent(BackupFormat.entriesFile)),
              let file = try? BackupFormat.jsonDecoder.decode(SummariesOnly.self, from: data)
        else { return [] }
        return (file.moodSummaries ?? []).compactMap(\.value)
    }

    private static func decodePenPalNotes(in package: Package) -> [BackupPenPalNote] {
        struct NotesOnly: Decodable { var penPalNotes: [Lenient<BackupPenPalNote>]? }
        guard let data = try? Data(contentsOf: package.root.appendingPathComponent(BackupFormat.lettersFile)),
              let file = try? BackupFormat.jsonDecoder.decode(NotesOnly.self, from: data)
        else { return [] }
        return (file.penPalNotes ?? []).compactMap(\.value)
    }

    private static func decodeLetters(in package: Package) -> [BackupLetter] {
        guard let data = try? Data(contentsOf: package.root.appendingPathComponent(BackupFormat.lettersFile))
        else { return [] }
        if let file = try? BackupFormat.jsonDecoder.decode(BackupLettersFile.self, from: data) {
            return file.letters
        }
        let salvaged = try? BackupFormat.jsonDecoder.decode(LenientLettersFile.self, from: data)
        return salvaged?.letters.compactMap(\.value) ?? []
    }

    // MARK: - 媒体落盘

    private static var audioDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 把包内 `media/<name>` 拷进沙箱，返回它在沙箱里的最终文件名（可能和包里不同）。
    /// 源文件不存在返回 nil。
    /// 包里的日记本并进本机已有的同名那本时：**本机缺什么补什么，已有的一律不动**
    /// （日记本重铸 P5，2026-10-08 产品定）。
    ///
    /// - 封面照片和版式是一套：本机那本**没有照片封面**才把包里的整套带过来
    /// - 副标题单独看：本机没写才用包里的
    /// - 颜色、书架位置、名字的写法都按本机的
    ///
    /// 包里自己有两种写法（「Travel」「travel」）时，后一本并进前一本，也走这里
    private static func fillMissingCover(
        of target: Tag,
        from incoming: BackupTag,
        package: Package,
        photoNames: inout [String: String]
    ) {
        if (target.coverPhotoFilename ?? "").isEmpty,
           let file = incoming.coverFile,
           // 包里找不到文件就当没有封面，不算错
           let adopted = adoptMedia(named: file, from: package.mediaDirectory,
                                    into: PhotoPaperIO.photosDirectory, cache: &photoNames) {
            target.coverPhotoFilename = adopted
            target.coverLayoutID = incoming.coverLayout
        }
        if (target.subtitle ?? "").isEmpty, let subtitle = incoming.subtitle, !subtitle.isEmpty {
            target.subtitle = String(subtitle.prefix(CoverEdit.subtitleMaxLength))
        }
    }

    private static func adoptMedia(
        named name: String,
        from mediaDir: URL,
        into destDir: URL,
        cache: inout [String: String]
    ) -> String? {
        // 只取最后一段：json 里的文件名是外部输入，不能让 "../../x" 决定往哪写
        let safe = (name as NSString).lastPathComponent
        guard !safe.isEmpty, safe != ".", safe != ".." else { return nil }
        if let already = cache[safe] { return already }

        let fm = FileManager.default
        let source = mediaDir.appendingPathComponent(safe)
        guard fm.fileExists(atPath: source.path) else { return nil }

        var finalName = safe
        var dest = destDir.appendingPathComponent(finalName)

        if fm.fileExists(atPath: dest.path) {
            let sourceSize = fileSize(source)
            if sourceSize >= 0, sourceSize == fileSize(dest) {
                // 同名同大小 —— 就是同一张照片（多半是把自己的备份又导了一遍），复用，不重复占空间
                cache[safe] = finalName
                return finalName
            }
            // 同名不同内容。照片名只取了 UUID 前 8 位（见 ComposeView.insertPaperPhoto），
            // 跨库导入撞名并非不可能 —— 这时**必须另起名字**，
            // 否则这篇日记会指到别人的照片上，比丢图还糟。
            let base = (safe as NSString).deletingPathExtension
            let ext = (safe as NSString).pathExtension
            var n = 1
            repeat {
                finalName = ext.isEmpty ? "\(base)_\(n)" : "\(base)_\(n).\(ext)"
                dest = destDir.appendingPathComponent(finalName)
                n += 1
            } while fm.fileExists(atPath: dest.path) && n < 100
        }

        do {
            try fm.copyItem(at: source, to: dest)
        } catch {
            return nil
        }
        cache[safe] = finalName
        return finalName
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
    }
}
