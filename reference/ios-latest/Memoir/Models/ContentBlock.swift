import SwiftUI

/// 内容块类型：文本 / 照片 / 录音
enum ContentBlockType: String, Codable {
    case text
    case photo
    /// 录音在正文里的位置（2026-10-10 加）。录音文件本身仍记在 `JournalEntry.audioURLs`，
    /// 同步、备份、删日记时清文件都只认那份清单 —— 这里只管「放在哪一行」。
    ///
    /// ⚠️ 不认识这个值的老版本整组解码会失败，退回只显示纯文字（`contentBlocks` 的降级），不会崩
    case audio
    /// 墨迹干了之后取下的照片 / 删去的录音留下的痕迹（2026-10-11 加，「墨迹会干」规则）。
    /// 只记取下的是什么（`traceOf`）、什么时候（`removedAt`），文件已经删了
    case trace
}

// MARK: - 墨迹会干（2026-10-11 产品定）

/// 日记写下 24 小时之后，墨迹就干了：
/// - 干了的字不能悄悄改掉、删掉 —— 删就是**划掉**（字还在，变淡，带上划掉的日子）
/// - 之后再写的字是**补记**：换一种墨色，整段补的上面标「补记 · 某月某日」
/// - 干了的照片、录音可以取下，但原处留一行痕迹
/// - 整篇日记随时可以删（数据是用户自己的）
///
/// 时间一律存 **Unix 秒**（`Double`），和鸿蒙、备份包对得上
enum Ink {
    /// 墨迹多久变干
    static let dryingInterval: TimeInterval = 24 * 60 * 60

    /// `writtenAt`（没有就是日记写下的时刻 `base`）过了 24 小时就是干的。`base` 为 nil（还在写的新日记）一律不干
    static func isDry(writtenAt: TimeInterval?, base: Date?, now: Date = .now) -> Bool {
        guard let written = writtenAt.map(Date.init(timeIntervalSince1970:)) ?? base else { return false }
        return now.timeIntervalSince(written) >= dryingInterval
    }

    /// 是不是「补记」：写的那天和日记写下的那天不是同一天
    static func isAddendum(writtenAt: TimeInterval?, base: Date?) -> Bool {
        guard let writtenAt, let base else { return false }
        return !Calendar.current.isDate(Date(timeIntervalSince1970: writtenAt), inSameDayAs: base)
    }
}

/// 照片在正文中的位置（左 / 右，不支持居中）
enum PhotoPosition: String, Codable {
    case left
    case right
}

/// 六种相纸样式（`.original` 为无相框的纯原图，其余五种为各式相纸装饰）
enum PaperStyle: String, Codable, CaseIterable {
    case original       // 原图：无相框、无装饰，仅圆角微裁
    case polaroid       // 宝丽来：白色厚边框，底部留白
    case washiSticker   // 和风贴纸：米白底棕边四角装饰
    case minimalCard    // 极简卡片：淡色细边 0.5px
    case filmFrame      // 胶片帧：两侧胶卷齿孔
    case letterAttached // 信纸附照：模拟贴在信纸上，有阴影

    /// 见 `HomeDisplayMode.displayName`：常驻界面的文案用 `LocalizedStringKey`
    var displayName: LocalizedStringKey {
        switch self {
        case .original:       return "原图"
        case .polaroid:       return "宝丽来"
        case .washiSticker:   return "和风贴纸"
        case .minimalCard:    return "极简卡片"
        case .filmFrame:      return "胶片帧"
        case .letterAttached: return "信纸附照"
        }
    }
}

/// 一段文字的格式。偏移和长度都按 **UTF-16** 计（和 NSString、鸿蒙 ArkTS 的字符串下标一致），
/// 相对于所在文本块的 `text`。
///
/// 小标题是整段的格式，也用同样的区间表示（覆盖那一整段）。
struct TextStyleRun: Codable, Equatable {
    var location: Int
    var length: Int
    var bold: Bool?
    var italic: Bool?
    /// 小标题
    var heading: Bool?
    /// 荧光笔（2026-10-10 加）
    var highlight: Bool?
    /// 这段字是什么时候写的（Unix 秒）。nil = 日记写下时就有的字（见 `Ink`）
    var writtenAt: Double?
    /// 这段字什么时候被划掉的（Unix 秒）。nil = 没划掉
    var struckAt: Double?
}

/// 日记正文的内容块。可以是纯文本，也可以是一张照片。
/// 存到 SwiftData 时以 JSON 编码后写入 `JournalEntry.contentBlocksData`。
struct ContentBlock: Codable, Identifiable, Equatable {
    let id: UUID
    let type: ContentBlockType

    // 文本块字段
    var text: String?

    // 照片块字段
    var photoFilename: String?             // Documents/journal_photos/ 下的相对文件名
    var livePhotoVideoFilename: String?    // Live Photo 视频部分（.mov），仅 Live Photo 有
    /// **未裁剪**的静态图文件名，专供 Live Photo 配对用。
    ///
    /// 只有**尺素相机拍的** Live Photo 才有值：相机会把画面居中裁成方形（相纸是方的），
    /// 而裁过的图和没裁的 .mov **配不成对**（走一遍重绘就丢了 Apple maker note 里的
    /// content identifier）。所以显示用 `photoFilename` 的方图，配对用这一份原图。
    ///
    /// 从相册选的 Live Photo 本来就没裁，`photoFilename` 存的就是原始字节，这里为 nil。
    /// 读取方一律按「nil 就退回 `photoFilename`」处理。
    var livePhotoStillFilename: String?
    var position: PhotoPosition?
    var paperStyle: PaperStyle?
    var rotationAngle: Double?    // ±3° 固定倾斜角，绑定到 id 避免滚动时抖动
    /// 用户在写日记页长按指定的「大屏展示封面」。一篇最多一张为 true。
    ///
    /// 可选类型是刻意的：`ContentBlock` 序列化进 `JournalEntry.contentBlocksData`（Data 里的 JSON），
    /// 不是 SwiftData 属性 —— 新增可选字段时旧数据缺这个 key 会解成 nil，**无需 schema 迁移**。
    var isCover: Bool?

    /// 文字格式（2026-10 图文编辑器）：这一段里哪些字加粗、斜体，哪几段是小标题。只有文本块有，没格式时为 nil。
    ///
    /// `text` 仍然是**纯文字** —— 笔友回信、字数、搜索、大屏卡片摘要只读它，不受格式影响；
    /// 不认识这个字段的老版本 / 鸿蒙端照样能显示正文，只是没有格式。
    /// 同 `isCover`：JSON 里的可选字段，老数据缺这个 key 解成 nil，**无需 schema 迁移**。
    var styles: [TextStyleRun]?

    // 录音块字段
    /// 录音的相对路径，和 `JournalEntry.audioURLs` 里的写法一样（"audio/xxx.m4a"）
    var audioFilename: String?

    // 墨迹（见 `Ink`）
    /// 照片 / 录音是什么时候放进来的（Unix 秒）。nil = 日记写下时就有
    var addedAt: Double?
    /// 痕迹块：取下的是什么（"photo" / "audio"）
    var traceOf: String?
    /// 痕迹块：什么时候取下的（Unix 秒）
    var removedAt: Double?

    /// 是否为 Live Photo
    var isLivePhoto: Bool { livePhotoVideoFilename != nil }

    /// 与 `.mov` 配对用的静态图文件名 —— 相机拍的用未裁原图，相册选的就是 `photoFilename`
    var pairingStillFilename: String? { livePhotoStillFilename ?? photoFilename }

    /// 文本块构造器
    init(text: String) {
        self.id = UUID()
        self.type = .text
        self.text = text
    }

    /// 文本块构造器（指定 id）—— 用于 `content` 字符串降级时保持 id 稳定，
    /// 避免每次访问 `contentBlocks` getter 都生成新随机 id 导致锚点失配。
    init(id: UUID, text: String) {
        self.id = id
        self.type = .text
        self.text = text
    }

    /// 痕迹块：干了的照片 / 录音被取下后留在原处
    init(traceOf kind: ContentBlockType, removedAt: Date) {
        self.id = UUID()
        self.type = .trace
        self.traceOf = kind.rawValue
        self.removedAt = removedAt.timeIntervalSince1970
    }

    /// 录音块构造器
    init(audioFilename: String) {
        self.id = UUID()
        self.type = .audio
        self.audioFilename = audioFilename
    }

    /// 照片块构造器：角度由 id 推导，保证同一张照片每次渲染角度一致
    init(photoFilename: String, livePhotoVideoFilename: String? = nil, position: PhotoPosition, paperStyle: PaperStyle) {
        let uuid = UUID()
        self.id = uuid
        self.type = .photo
        self.photoFilename = photoFilename
        self.livePhotoVideoFilename = livePhotoVideoFilename
        self.position = position
        self.paperStyle = paperStyle
        // 由 id 的 hash 推导 -3.0 ~ +3.0 的固定角度
        let hash = abs(uuid.uuidString.hashValue)
        self.rotationAngle = Double(hash % 60 - 30) / 10.0
    }
}

// MARK: - 划掉的字不算

extension ContentBlock {
    /// 去掉划掉的字之后的正文（见 `Ink`）。字数、搜索、寄给笔友的内容都用它 —— 划掉就是收回了，
    /// 只是在纸上还留着痕迹
    var visibleText: String {
        guard let text, let styles, styles.contains(where: { $0.struckAt != nil }) else { return text ?? "" }
        let ns = NSMutableString(string: text)
        for run in styles.filter({ $0.struckAt != nil }).sorted(by: { $0.location > $1.location }) {
            let range = NSRange(location: run.location, length: run.length)
            guard range.location >= 0, NSMaxRange(range) <= ns.length else { continue }
            ns.deleteCharacters(in: range)
        }
        return ns as String
    }
}

// MARK: - 录音在正文里

extension Array where Element == ContentBlock {
    /// 正文里放了的录音（按出现顺序）
    var audioPaths: [String] {
        compactMap { $0.type == .audio ? $0.audioFilename : nil }
    }

    /// 把「在录音清单里、但正文里还没有位置」的录音补到正文末尾。
    /// 2026-10-10 之前的日记录音都在正文外面（列在最后），打开编辑时就地转成正文里的录音块
    func withLooseAudio(_ audioURLs: [String]) -> [ContentBlock] {
        let placed = Set(audioPaths)
        let loose = audioURLs.filter { !placed.contains($0) }
        guard !loose.isEmpty else { return self }
        return self + loose.map { ContentBlock(audioFilename: $0) }
    }
}
