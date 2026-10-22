import Foundation

/// 备份包的数据格式定义。**必须与 `Memoir/Docs/EXPORT_FORMAT.md` 保持一致** ——
/// 那份文档是跨端契约，鸿蒙端按它实现读取。改这里就要同步改那里，并按规则升 `formatVersion`。
/// `nonisolated`：这里全是纯粹的格式定义，导入时要在后台线程上解析（解压 + 解密可能几秒，
/// 不能占着主线程），所以整个类型明确退出工程默认的 MainActor 隔离。
nonisolated enum BackupFormat {
    /// 结构版本。**只有破坏性变更才 +1**（删字段、改语义、改类型）。
    /// 新增可选字段不算破坏性 —— 读取方按「未知字段忽略」处理即可。
    static let currentVersion = 1

    static let manifestFile = "manifest.json"
    static let entriesFile = "entries.json"
    static let lettersFile = "letters.json"
    static let taxonomyFile = "taxonomy.json"
    static let mediaDirectory = "media"

    /// 未加密时文件本身就是标准 zip，用户改名 `.zip` 即可打开检视 ——
    /// 对一款主打私密的产品，数据能被用户自己看懂本身就是承诺的一部分。
    static let fileExtension = "memoir"

    /// 每次给一个新实例，不共享 —— JSONEncoder/Decoder 不是 Sendable，
    /// 而导入是在后台线程上跑的，共享一个实例就等于把非线程安全的对象跨线程递。
    /// 构造成本相比解析本身可以忽略。
    static var jsonEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static var jsonDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

// MARK: - manifest.json

nonisolated struct BackupManifest: Codable {
    var formatVersion: Int = BackupFormat.currentVersion
    var app: String = "memoir"
    var appVersion: String
    var platform: String = "ios"
    var exportedAt: Date
    var counts: Counts
    /// 「仅文字」导出时为 false，media/ 目录不存在
    var includesMedia: Bool
    var mediaTotalBytes: Int
    /// 明文标记，让导入端在解密前就知道要不要问密码
    var encrypted: Bool

    struct Counts: Codable {
        var entries: Int = 0
        var letters: Int = 0
        var media: Int = 0

        init(entries: Int, letters: Int, media: Int) {
            self.entries = entries
            self.letters = letters
            self.media = media
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            entries = try c.decodeIfPresent(Int.self, forKey: .entries) ?? 0
            letters = try c.decodeIfPresent(Int.self, forKey: .letters) ?? 0
            media   = try c.decodeIfPresent(Int.self, forKey: .media) ?? 0
        }
    }

    /// 手写解码：**除 `formatVersion` 外全部按缺省值兜底**。
    ///
    /// Swift 合成的 `init(from:)` 对缺失的 key 一律抛 `keyNotFound`，属性上的默认值救不了 ——
    /// 而 manifest 是跨端契约里最先被别人实现的一块（鸿蒙端按 EXPORT_FORMAT.md §2.2 写，
    /// 那份示例里就没有 `encrypted`）。为一个统计字段整包拒收，违背 §2.4「宁可残缺也不要整包失败」。
    /// 真正必须可信的只有 `formatVersion`（决定敢不敢解析），它缺失时按 1 处理。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion   = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        app             = try c.decodeIfPresent(String.self, forKey: .app) ?? "memoir"
        appVersion      = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? "未知"
        platform        = try c.decodeIfPresent(String.self, forKey: .platform) ?? "unknown"
        exportedAt      = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .distantPast
        counts          = try c.decodeIfPresent(Counts.self, forKey: .counts) ?? Counts(entries: 0, letters: 0, media: 0)
        includesMedia   = try c.decodeIfPresent(Bool.self, forKey: .includesMedia) ?? true
        mediaTotalBytes = try c.decodeIfPresent(Int.self, forKey: .mediaTotalBytes) ?? 0
        encrypted       = try c.decodeIfPresent(Bool.self, forKey: .encrypted) ?? false
    }

    init(
        appVersion: String,
        exportedAt: Date,
        counts: Counts,
        includesMedia: Bool,
        mediaTotalBytes: Int,
        encrypted: Bool
    ) {
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.counts = counts
        self.includesMedia = includesMedia
        self.mediaTotalBytes = mediaTotalBytes
        self.encrypted = encrypted
    }
}

// MARK: - entries.json

nonisolated struct BackupEntriesFile: Codable {
    var entries: [BackupEntry]
}

nonisolated struct BackupEntry: Codable {
    /// 合并去重的依据 —— 导入时同 id 视为同一篇，跳过不覆盖
    var id: UUID
    var title: String
    var date: Date
    var createdAt: Date
    var updatedAt: Date
    /// ⚠️ **作废**（2026-10-17 删了旧心情标签）：写 `""` 和 nil、读时忽略。
    /// 字段留着是为了老版本（含鸿蒙 v1）还能导入新包 —— 它们把 `mood` 当必填读，删了就整包读不进去
    var mood: String
    var moodColorHex: String?
    var tags: [String]
    var isFavorite: Bool
    var weatherCode: String?
    var weatherInfo: String?
    var locationInfo: String?
    /// 指向 media/ 内的文件名
    var audio: [String]
    var blocks: [BackupBlock]
    /// 写完时的心情（2026-10-17，见 `JournalEntry.moodValence`）：愉悦度 -1…1。
    /// **可选，不升 `formatVersion`** —— 老包、鸿蒙包没有这个字段就是「没记心情」
    var moodValence: Double? = nil
    /// 选的情绪词（`MoodLabel` 的英文 key，目前一篇一个）。可选，同上；不认识的 key 原样保留、显示时跳过
    var moodLabels: [String]? = nil
}

nonisolated struct BackupBlock: Codable {
    /// "text" | "photo" | "audio" | "trace"（"audio" 2026-10-10 加：录音在正文里的位置；
    /// "trace" 2026-10-11 加：墨迹干了以后取下的照片 / 删去的录音留下的痕迹）。
    /// 读不懂的类型跳过这一块，不阻断导入
    var type: String
    var text: String?
    /// 文本块的格式（加粗、斜体、小标题、荧光笔），偏移按 UTF-16，见 `TextStyleRun`。
    /// **可选，不升 `formatVersion`** —— 老包没有这个字段就是没有格式
    var styles: [TextStyleRun]?
    /// media/ 内的文件名。照片块是照片；录音块是录音（和 `BackupEntry.audio` 里同一个文件）
    var file: String?
    /// Live Photo 的视频部分，media/ 内的文件名
    var liveVideo: String?
    /// **未裁剪**的静态图，media/ 内的文件名。只有相机拍的 Live Photo 有 ——
    /// `file` 是裁过的方图（显示用），配对必须用这一份。缺失时读取方退回用 `file` 配对。
    var liveStill: String?
    var paperStyle: String?
    var position: String?
    var rotationAngle: Double?
    var isCover: Bool?
    /// 照片 / 录音是什么时候放进来的（Unix 秒，见 `Ink`）。nil = 日记写下时就有。可选，不升 `formatVersion`
    var addedAt: Double?
    /// 痕迹块（`type: "trace"`）：取下的是什么（"photo" / "audio"）、什么时候取下的（Unix 秒）
    var traceOf: String?
    var removedAt: Double?
}

// MARK: - letters.json

nonisolated struct BackupLettersFile: Codable {
    var letters: [BackupLetter]
    /// 「他记得的关于你的事」（世界笔友，2026-10-16）。
    /// **可选，不升 `formatVersion`** —— 老包、鸿蒙包没有这个字段就是没有
    var penPalNotes: [BackupPenPalNote]? = nil
}

/// 「他记得的关于你的事」里的一条（`PenPalNote`）。按 `id` 去重合并
nonisolated struct BackupPenPalNote: Codable {
    var id: UUID
    /// 世界笔友的 id（`penpals.json`）
    var penPalID: String
    var text: String
    /// 记下它的那封回信的写信时刻
    var notedAt: Date
    var createdAt: Date
}

nonisolated struct BackupLetter: Codable {
    var id: UUID
    var body: String
    var fromCharacter: String
    /// 写信当时的收信人昵称快照（信件抬头「致 XXX」）。
    /// **可选，不升 `formatVersion`** —— 老包没有这个字段也要能正常导入（解成 nil，
    /// 抬头退回只写「致」），鸿蒙端导出的包同理。
    var toName: String?
    /// 这封信用的什么信纸：nil = 普通信纸，`"sealed"` = 火漆信（尺素会员，2026-10）。
    /// **可选，不升 `formatVersion`** —— 老包、鸿蒙包没有这个字段时解成 nil（普通信纸）；
    /// 不认识的取值原样保留，不在导入时抹掉
    var stationery: String?
    var status: String
    var triggerKind: String
    /// **寄出时刻**（= 回信写好的时刻）
    var generatedAt: Date
    /// **到达时刻**。2026-09-14 起回信寄出后 6 小时 ~ 3 天才到（见 `LetterDelivery`），
    /// 所以**在路上的信这里是个未来时间**，导入后到点才会出现在信箱里 —— 这是对的，不要修正它。
    /// 更早的包里这个值约等于写好的时刻或为 nil，都按「早已到达」处理
    var deliveredAt: Date?
    var readAt: Date?
    /// 关联日记的 id。导入时按 id 重连；找不到的忽略（不阻断导入）
    var relatedEntryIDs: [UUID]
    // 世界笔友（2026-10-16）。**都可选，不升 `formatVersion`** —— 老包、鸿蒙包没有就是「自己起名的那位的信」
    /// 世界笔友的 id；nil = 自己起名的那位
    var penPalID: String? = nil
    /// 译文（读信人的语言）；`body` 是笔友母语写的原文
    var translatedBody: String? = nil
    /// 危险的那封：正面放译文
    var danger: Bool? = nil
    /// 贴了几张邮票
    var postage: Int? = nil
}

// MARK: - taxonomy.json

nonisolated struct BackupTaxonomyFile: Codable {
    var tags: [BackupTag]
    /// ⚠️ **作废**（2026-10-17 删了旧心情标签）：写 `[]`、读时忽略；留着的原因同 `BackupEntry.mood`
    var moods: [BackupMood]
}

nonisolated struct BackupTag: Codable {
    var id: UUID
    var name: String
    var colorID: String
    var textureID: String
    var createdAt: Date
    /// 照片封面，media/ 内的文件名（2026-10 P2）。
    /// **可选，不升 `formatVersion`** —— 老包、鸿蒙包没有这个字段照常导入（就是纯色封面）。
    /// 「仅文字」导出时不写；文件在包里找不到时导入端当作没有封面，不阻断。
    var coverFile: String?
    /// 照片封面的版式：`"FullBleed"` / `"Framed"` / `"TipIn"`（2026-10 P3b，见 `CoverLayout`）。
    /// 可选；缺失或不认识按满版。没有照片封面时没有意义
    var coverLayout: String?
    /// 副标题（日记本主页书名下那行小字，2026-10 P3b）。可选，缺失 = 没有
    var subtitle: String?
}

/// 旧心情标签（作废，只为读写 `moods` 字段留着类型）
nonisolated struct BackupMood: Codable {
    var id: UUID
    var name: String
    var colorHex: String
    var isDefault: Bool
    var sortOrder: Int
    var iconName: String?
    var createdAt: Date
}
