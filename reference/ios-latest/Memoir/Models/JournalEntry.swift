import Foundation
import SwiftData

/// ⚠️ **CloudKit 约束**：本模型参与 iCloud 同步，因此
/// - 每个非可选属性**必须在声明处带默认值**（CloudKit 记录可能缺字段）
/// - 关系必须可选且有反向关系
/// 加新字段时请遵守，否则容器初始化会直接失败。
@Model
class JournalEntry {
    var id: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var date: Date = Date()
    var tags: [String] = []
    var isFavorite: Bool = false
    var wordCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // v1.1 扩展字段
    var audioURLs: [String] = []
    var weatherInfo: String?
    var locationInfo: String?
    var weatherCode: String?

    /// 写完这篇时的心情（2026-10-17，V10 新增，见 `SchemaV10`、`MoodCheckInView`）：
    /// 愉悦度 -1（跌入谷底）… 1（心花怒放），是他在滑杆上选的那个值。nil = 没记（V10 之前的日记都是 nil）
    var moodValence: Double?
    /// 选的情绪词（`MoodLabel` 的 key，如 `drained`），心情页选一个；存成数组是给以后留余地。nil = 没记
    var moodLabels: [String]?

    // v1.2 扩展字段：结构化内容块（JSON 编码）
    // 为保持向后兼容，未设置时从 `content` 字符串降级为单一文本块
    var contentBlocksData: Data?

    /// 由这篇日记引发过的来信（`Letter.relatedEntries` 的反向关系）。
    /// CloudKit 要求关系必须成对，V3 才补上；顺带让「翻一篇日记看它引发过哪些信」成为可能。
    @Relationship(inverse: \Letter.relatedEntries)
    var letters: [Letter]? = []

    init(
        title: String = "",
        content: String = "",
        date: Date = .now,
        tags: [String] = [],
        isFavorite: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.date = date
        self.tags = tags
        self.isFavorite = isFavorite
        self.wordCount = content.count
        self.createdAt = .now
        self.updatedAt = .now
        self.audioURLs = []
        self.weatherInfo = nil
        self.locationInfo = nil
        self.weatherCode = nil
        self.contentBlocksData = nil
    }
}

// MARK: - 内容块访问器

extension JournalEntry {
    /// 结构化内容块（文本 + 照片）。
    /// - 读：若 `contentBlocksData` 为空，则从旧的 `content` 字符串降级为单一文本块。
    /// - 写：同步 JSON 编码到 `contentBlocksData`，并用所有文本块拼接更新 `content`（用于搜索和 fallback）。
    var contentBlocks: [ContentBlock] {
        get {
            if let data = contentBlocksData,
               let decoded = try? JSONDecoder().decode([ContentBlock].self, from: data) {
                return decoded
            }
            // 降级：用 entry.id 作为唯一文本块的稳定 id，
            // 否则每次访问都生成新随机 id，会让"长按插入照片"的锚点失配。
            return content.isEmpty ? [] : [ContentBlock(id: id, text: content)]
        }
        set {
            contentBlocksData = try? JSONEncoder().encode(newValue)
            // 划掉的字不进 content（字数、搜索、寄给笔友的都是它），见 `ContentBlock.visibleText`
            content = newValue
                .compactMap { $0.type == .text ? $0.visibleText : nil }
                .joined(separator: "\n\n")
            wordCount = content.count
            updatedAt = .now
        }
    }

    /// 录音清单里、正文中没有位置的录音（老日记的录音，或别的版本写的）—— 还按原来的样子排在正文后面
    var looseAudioURLs: [String] {
        let placed = Set(contentBlocks.audioPaths)
        return audioURLs.filter { !placed.contains($0) }
    }

    /// 补记过的那几天（不同的日子，按先后）。详情页显示「补记 N 次」用
    var addendumDays: [Date] {
        var days = Set<Date>()
        func add(_ written: Double?) {
            guard let written, Ink.isAddendum(writtenAt: written, base: createdAt) else { return }
            days.insert(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: written)))
        }
        for block in contentBlocks {
            add(block.addedAt)
            for run in block.styles ?? [] where run.struckAt == nil { add(run.writtenAt) }
        }
        return days.sorted()
    }

    /// 当前日记中的照片数量
    var photoCount: Int {
        contentBlocks.filter { $0.type == .photo }.count
    }

    /// 删掉这篇日记引用的全部媒体文件（照片 / Live Photo 的原图与视频 / 录音）。
    ///
    /// ⚠️ **删日记之前必须调一次**。照片和录音是沙盒里的独立文件，不在 SwiftData 里 ——
    /// 只 `modelContext.delete(entry)` 的话，文件会永远留在磁盘上，用户看不见也删不掉。
    /// 一篇带图日记的残留可能有好几 MB，攒起来很可观。
    func deleteAssociatedMedia() {
        var names: [String] = []
        for block in contentBlocks where block.type == .photo {
            names.append(contentsOf: [
                block.photoFilename, block.livePhotoVideoFilename, block.livePhotoStillFilename
            ].compactMap { $0 })
        }
        for name in names {
            PhotoPaperIO.deleteImage(name)
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for relative in audioURLs {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(relative))
            names.append((relative as NSString).lastPathComponent)
        }

        // 云端副本也要删 —— 只删磁盘的话，别的设备同步下来还会把它写回来
        if let context = modelContext, !names.isEmpty {
            let wanted = Set(names)
            let assets = (try? context.fetch(FetchDescriptor<MediaAsset>())) ?? []
            for asset in assets where wanted.contains(asset.filename) {
                context.delete(asset)
            }
        }
    }
}

// MARK: - 标题规则

extension JournalEntry {
    /// 标题字数上限。
    ///
    /// 标题在各处的呈现不一样：**阅读器首页页眉（`DiaryPageHeader`）和详情页不限行数、自动换行**，
    /// 而列表 / 大屏模式 / 阅读器页眉是 `lineLimit(1)` 截断。
    /// 封面那处既不截断又是招牌视觉，标题太长会把排版撑坏 —— 所以上限由它决定：
    /// 40 字约合封面 Georgia 22pt 下的三行。
    ///
    /// **这是 `static let`，不是存储属性，与 SwiftData schema 无关。**
    static let titleMaxLength = 40

    /// 标题输入的净化：去掉手动换行 + 截到上限。
    ///
    /// 换行必须去掉 —— 编辑框是可换行的（`axis: .vertical`），回车会插入真的 `\n`，
    /// 而列表、大屏、阅读器页眉都是单行显示，标题里藏个换行符在那些地方
    /// 会变成一个莫名其妙的空隙。
    static func sanitizedTitle(_ raw: String) -> String {
        let trimmed = raw.replacingOccurrences(of: "\n", with: "")
        return trimmed.count > titleMaxLength ? String(trimmed.prefix(titleMaxLength)) : trimmed
    }
}

// MARK: - 心情

extension JournalEntry {
    /// 这篇的心情在九档里的哪一档；nil = 没记
    var moodLevel: MoodLevel? { moodValence.map(MoodLevel.init(valence:)) }

    /// 选的情绪词（认不出的 key 跳过）
    var moodLabelList: [MoodLabel] { (moodLabels ?? []).compactMap(MoodLabel.init(rawValue:)) }

    /// 发给后端的心情：九档的英文名 + 情绪词，如 `melancholy (drained, anxious)`；没记是 nil
    var moodSummary: String? {
        guard let level = moodLevel else { return nil }
        let labels = moodLabelList.map(\.rawValue)
        return labels.isEmpty ? level.englishName : "\(level.englishName) (\(labels.joined(separator: ", ")))"
    }

    /// 记下心情页的结果
    func record(_ mood: MoodRecord) {
        moodValence = mood.valence
        moodLabels = [mood.label.rawValue]
        updatedAt = .now
    }
}
