import Foundation
import SwiftData

/// 没写完的那一篇。
///
/// **为什么单独立一个 model，而不是给 `JournalEntry` 加个 `isDraft`**：
/// 加标志位的话，首页、日记本、搜索、大屏展示、备份包导出、字数统计……
/// 每一处 `@Query<JournalEntry>` 都得记得加过滤条件，**漏一处草稿就混进正式日记里**。
/// 独立 entity 从类型上就杜绝了这件事 —— 现有查询一行都不用改。
///
/// **产品语义**：写日记页按返回时选「保存」存到这里；**只有点右上角对勾才算「完成了一篇书写」**，
/// 那一刻草稿转成 `JournalEntry` 并把自己删掉。草稿全局**只留一份**（`DraftEntry.current`），
/// 下次进写日记页自动接着写。
///
/// ⚠️ **CloudKit 约束**：本模型参与 iCloud 同步，因此
/// - 每个非可选属性**必须在声明处带默认值**
/// - **不能用 `@Attribute(.unique)`**（CloudKit 镜像不支持唯一约束）——
///   所以"只留一份"是靠 `save` 时先清空旧的来保证的，不是靠数据库约束
@Model
final class DraftEntry {
    var id: UUID = UUID()
    var title: String = ""
    /// 结构化正文（与 `JournalEntry.contentBlocksData` 同一套 JSON 编码，转正时可直接搬）
    var contentBlocksData: Data?
    var tags: [String] = []
    var audioURLs: [String] = []

    /// 存草稿那一刻的「此时此地」。
    ///
    /// **恢复时原样还原，不重新取** —— 草稿可能是昨天在广州写的，今天在西安打开，
    /// 重新定位会把地点改成西安，可这篇日记记的是昨天那件事。
    /// 用户上次已经做过决定（包括他手动挑的地点），不该被覆盖。
    var weatherCode: String?
    var weatherInfo: String?
    var locationInfo: String?
    /// 地点选择模式：`auto` / `none` / `manual`，配合 `manualPlaceName` 还原 `PlaceChoice`
    var placeMode: String = PlaceMode.auto.rawValue
    var manualPlaceName: String?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// `PlaceChoice` 的可持久化形态（enum 带 associated value，存不进 SwiftData）
    enum PlaceMode: String {
        case auto, none, manual
    }

    init(
        title: String = "",
        tags: [String] = [],
        audioURLs: [String] = []
    ) {
        self.id = UUID()
        self.title = title
        self.tags = tags
        self.audioURLs = audioURLs
        self.createdAt = .now
        self.updatedAt = .now
    }
}

// MARK: - 内容块访问器

extension DraftEntry {
    /// 与 `JournalEntry.contentBlocks` 同构。草稿没有"从 content 字符串降级"那条旧路径，
    /// 因为它是全新的 model，不存在历史数据。
    var contentBlocks: [ContentBlock] {
        get {
            guard let data = contentBlocksData,
                  let decoded = try? JSONDecoder().decode([ContentBlock].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            contentBlocksData = try? JSONEncoder().encode(newValue)
            updatedAt = .now
        }
    }

    /// 这份草稿引用到的全部媒体文件名（照片裸名 + 录音 "audio/xxx" 相对路径）。
    ///
    /// ⚠️ `MediaStorage` 靠它把草稿里的照片算进"被引用"—— 否则用户存了草稿、
    /// 再去设置里点一次「清理残留文件」，草稿里的图就被当孤儿删了。
    var referencedMediaNames: [String] {
        var names: [String] = []
        for block in contentBlocks where block.type == .photo {
            names.append(contentsOf: [
                block.photoFilename, block.livePhotoVideoFilename, block.livePhotoStillFilename
            ].compactMap { $0 })
        }
        for relative in audioURLs {
            names.append(relative)
            names.append((relative as NSString).lastPathComponent)
        }
        return names
    }

    /// 删掉这份草稿引用的媒体文件。
    ///
    /// **只在「不保存」地丢弃草稿时调**。转成正式日记时**绝对不能调** ——
    /// 那些文件正要被 `JournalEntry` 接着用。
    func deleteAssociatedMedia() {
        for block in contentBlocks where block.type == .photo {
            PhotoPaperIO.deleteImage(block.photoFilename)
            PhotoPaperIO.deleteImage(block.livePhotoVideoFilename)
            PhotoPaperIO.deleteImage(block.livePhotoStillFilename)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for relative in audioURLs {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(relative))
        }
    }
}

// MARK: - 单份草稿的存取

extension DraftEntry {
    /// 取当前草稿（约定只有一份；真出现多条就用最近改过的那条，其余顺手清掉）。
    ///
    /// 为什么会"真出现多条"：CloudKit 不支持唯一约束，两台设备同时存草稿就会各同步一条过来。
    /// 这里以 `updatedAt` 最新的为准 —— 与其弹个框让用户选，不如安静地取最新那份。
    static func current(in context: ModelContext) -> DraftEntry? {
        var descriptor = FetchDescriptor<DraftEntry>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        guard let drafts = try? context.fetch(descriptor), let newest = drafts.first else { return nil }
        // 多余的旧草稿直接删（连同它们的媒体文件），避免越攒越多
        for stale in drafts.dropFirst() {
            stale.deleteAssociatedMedia()
            context.delete(stale)
        }
        return newest
    }

    /// 丢弃当前草稿（连同它引用的媒体文件）。
    static func discardCurrent(in context: ModelContext) {
        guard let draft = current(in: context) else { return }
        draft.deleteAssociatedMedia()
        context.delete(draft)
        try? context.save()
    }
}
