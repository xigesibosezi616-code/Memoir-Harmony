import Foundation

/// 大屏展示模式用到的派生数据。
///
/// 全部是计算属性 —— 不新增存储属性，**不影响 SwiftData schema**。
extension JournalEntry {
    /// 正文里的全部照片文件名，按出现顺序。多张时大屏封面会轮播。
    var photoFilenames: [String] {
        contentBlocks.compactMap { $0.type == .photo ? $0.photoFilename : nil }
    }

    /// 封面照片：用户长按指定的优先；没指定就用第一张；没照片则 nil。
    var coverPhotoFilename: String? {
        let photos = contentBlocks.filter { $0.type == .photo }
        return photos.first(where: { $0.isCover == true })?.photoFilename
            ?? photos.first?.photoFilename
    }

    /// 轮播顺序：指定的封面排第一，其余按原顺序跟在后面。
    /// 用户指定了封面就该先看到它，而不是等轮播转过来。
    var showcasePhotoFilenames: [String] {
        guard let cover = coverPhotoFilename else { return [] }
        return [cover] + photoFilenames.filter { $0 != cover }
    }

    /// 是否有录音 —— 决定大屏卡片上要不要出播放键
    var hasAudio: Bool { !audioURLs.isEmpty }

    /// 正文纯文字预览（跳过照片块）
    var textPreview: String {
        contentBlocks
            .compactMap { $0.type == .text ? $0.visibleText : nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
