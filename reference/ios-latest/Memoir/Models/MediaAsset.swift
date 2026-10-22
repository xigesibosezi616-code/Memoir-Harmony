import Foundation
import SwiftData

/// 照片 / 录音 / Live Photo 视频的**云端载体**。
///
/// **为什么要有这个东西**：照片和录音一直是 `Documents/` 下的独立文件，SwiftData 里只存文件名。
/// CloudKit 同步的是 SwiftData —— 于是同步到第二台设备的日记**有字没图**。
///
/// `@Attribute(.externalStorage)` 的 `Data` 会被 SwiftData 存成独立文件，
/// 而 CloudKit 镜像会**自动把它变成 CKAsset** 上传下载。也就是说：
/// 把字节塞进这里，跨设备同步就由 CloudKit 免费带走了，不用自己写上传队列 / 重试 / 冲突那一套。
///
/// **与磁盘文件的关系**：磁盘文件仍是读取时的主路径（`PhotoPaperIO.loadImage` 那条），
/// 这里是它的云端副本。两边靠 `filename` 对应：
/// - `MediaStorage.syncToCloud` —— 磁盘上有、这里没有 → 补一条（新写入的照片、导入进来的照片都靠它）
/// - `MediaStorage.hydrateFromCloud` —— 这里有、磁盘上没有 → 写回磁盘（第二台设备靠它）
///
/// ⚠️ **CloudKit 约束**：非可选属性必须带默认值；**不能用 `@Attribute(.unique)`**
/// （CloudKit 镜像不支持唯一约束），所以去重靠查询，不靠数据库约束。
@Model
final class MediaAsset {
    /// 与磁盘文件名一致（照片是裸名 `photo_xxx.jpg`，录音是 `audio_xxx.m4a`）。
    /// 这是两边对应的唯一依据。
    var filename: String = ""
    /// 文件原始字节。externalStorage → SwiftData 存成独立文件 → CloudKit 转成 CKAsset
    @Attribute(.externalStorage) var data: Data = Data()
    /// 属于哪个目录：照片在 `journal_photos/`，录音在 `audio/`。
    /// 只存这两个值之一，用字符串是为了以后加目录时不动 schema。
    var directory: String = MediaAsset.photosDirectoryKey
    var createdAt: Date = Date()

    static let photosDirectoryKey = "journal_photos"
    static let audioDirectoryKey = "audio"

    init(filename: String, data: Data, directory: String) {
        self.filename = filename
        self.data = data
        self.directory = directory
        self.createdAt = .now
    }
}
