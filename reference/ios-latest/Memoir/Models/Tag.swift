import Foundation
import SwiftData

/// ⚠️ **CloudKit 约束**：非可选属性必须带默认值。见 `JournalEntry` 顶部说明。
@Model
class Tag {
    var id: UUID = UUID()
    var name: String = ""
    /// 旧字段：早期版本存的是 hex 字符串（"#592A2C"）。
    /// 新代码请勿读写，仅一次性迁移函数 `migrateTagsToBookCoverSystem` 读取。
    var color: String?
    /// 封面颜色标识：`BookColor.rawValue`（"WineRed" / "PineGreen" 等）。默认酒红。
    var colorID: String = "WineRed"
    /// 封面纹理标识。**2026-10 起只剩亚麻**（皮革下架，见 `BookTexture`），新建的一律写 "Linen"。
    ///
    /// 字段本身留着：它在 schema 和备份格式里都有，删掉要升 schema、改跨端契约，不值得。
    /// 声明处的默认值 `"Leather"` 也**不要改** —— 改默认值同样算动 schema。
    /// 渲染不读这个字段，存量的 "Leather" 由 `migrateTagsToBookCoverSystem` 改写成 "Linen"。
    var textureID: String = "Leather"
    /// 最后打开时间（保留备用；20-图方案下不再渲染封条）
    var lastOpenedAt: Date = Date()
    var createdAt: Date = Date()

    // MARK: V7（2026-10 日记本重铸）新增 —— 见 `SchemaV7`

    /// 书架上的位置，小的在前。迁移上来的老数据全是 0，此时按 `createdAt` 排（= 原来的顺序）。
    var sortOrder: Int = 0
    /// 照片封面的文件名（`journal_photos/` 下）。nil = 用纯色亚麻封面。
    /// ⚠️ 接上功能时必须把它算进 `MediaStorage` 的引用表，否则「清理残留文件」会把封面当孤儿删掉
    var coverPhotoFilename: String?
    /// 封面版式模板 ID。nil = 经典布面
    var coverLayoutID: String?
    /// 书名下的小字（如「2025 · 京都」）。nil = 不显示
    var subtitle: String?

    init(name: String, colorID: String = "WineRed", textureID: String = BookTexture.linen.rawValue) {
        self.id = UUID()
        self.name = name
        self.color = nil
        self.colorID = colorID
        self.textureID = textureID
        self.lastOpenedAt = .now
        self.createdAt = .now
    }

    // MARK: - 桥接到枚举（给 BookCoverView / BookCustomizerView 用）

    /// 已下架的颜色先就近映射，再不认识才回落酒红 ——
    /// 别的设备（旧版本）同步来的、或从旧备份包导入的记录，可能还带着下架的 colorID，
    /// 迁移函数只在启动时跑一次，接不住之后才到的数据。
    var bookColor: BookColor {
        BookColor(rawValue: colorID)
            ?? BookColor.retiredColorReplacement[colorID]
            ?? .wineRed
    }

    /// 照片封面（给 `BookCoverView` 用）；nil = 纯色亚麻
    var coverPhoto: CoverPhotoSource? {
        coverPhotoFilename.flatMap { $0.isEmpty ? nil : .file($0) }
    }

    /// 封面渲染用的标题文案：每行最多 4 字，超出自动插入换行符。
    /// `name` 仍是路由 / 过滤等逻辑用的原值，不变。
    var displayName: String {
        guard name.count > 4 else { return name }
        var result = ""
        for (i, char) in name.enumerated() {
            if i > 0 && i % 4 == 0 { result += "\n" }
            result.append(char)
        }
        return result
    }
}

// MARK: - 名字规则：日记本不许重名

/// **日记本的身份就是名字**：`JournalEntry.tags` 存的是名字字符串，不是关系。
/// 两本同名的日记本在数据上根本分不开 —— 同一篇日记会同时出现在两本里。
///
/// 所有能产生日记本名字的入口（书架新建 / 重命名 / 写日记页的「新建标签」/ 导入）
/// 都必须走这里判重，不要各自拿 `==` 比。
///
/// > CloudKit 镜像不支持 `@Attribute(.unique)`，数据库层拦不住，
/// > 两台设备各自建出来的同名记录由 `dedupeTagsByName` 事后合并。
extension Tag {
    /// 判重用的键：去首尾空白、忽略大小写与全半角。
    /// 「Travel」「travel」「Ｔｒａｖｅｌ」「 旅行 」各算同一个名字。
    ///
    /// **只用于比较，不要存进库** —— 用户输入的大小写和全半角原样保留。
    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    /// 存库前的名字：只去首尾空白
    static func cleanedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `name` 是否和 `names` 里的某一个撞名（按 `nameKey` 比）。
    /// 重命名时调用方要先把自己从 `names` 里排除，否则改个大小写也会被拦。
    static func isNameTaken(_ name: String, in names: some Sequence<String>) -> Bool {
        let key = nameKey(name)
        return names.contains { nameKey($0) == key }
    }

    /// 新建的日记本排在书架最后：现有最大的 `sortOrder` + 1。
    ///
    /// 迁移上来的老数据全是 0（按 `createdAt` 排），新建的拿 1 起步，自然排在它们后面。
    /// **每个新建日记本的入口都要用它**，否则新书会插进老书中间。
    static func nextSortOrder(after tags: [Tag]) -> Int {
        (tags.map(\.sortOrder).max() ?? -1) + 1
    }

    /// 起一个不撞名的名字：「旅行」→「旅行 2」→「旅行 3」……
    ///
    /// 序号前的空格不进本地化：名字是用户数据，导入后它就是一个普通的日记本名，
    /// 用户换语言时不该跟着变。
    static func uniqueName(basedOn base: String, avoiding names: some Sequence<String>) -> String {
        let keys = Set(names.map(nameKey))
        let cleaned = cleanedName(base)
        guard keys.contains(nameKey(cleaned)) else { return cleaned }
        var n = 2
        while keys.contains(nameKey("\(cleaned) \(n)")) { n += 1 }
        return "\(cleaned) \(n)"
    }
}

// MARK: - 改名

extension Tag {
    enum RenameResult {
        case renamed
        /// 空名字，或和原来一样 —— 什么都没做
        case unchanged
        /// 和别的日记本撞名
        case nameTaken
    }

    /// 改名，并把挂在这本上的日记一起改过去（日记靠名字挂在日记本上，只改 `Tag` 的话日记就"掉"出来了）。
    ///
    /// 只改内存里的对象，**不保存** —— 保存与报错由调用方按自己的方式处理。
    @MainActor
    func rename(to raw: String, in context: ModelContext) throws -> RenameResult {
        let newName = Tag.cleanedName(raw)
        guard !newName.isEmpty, newName != name else { return .unchanged }

        let others = try context.fetch(FetchDescriptor<Tag>()).filter { $0.id != id }
        guard !Tag.isNameTaken(newName, in: others.map(\.name)) else { return .nameTaken }

        let oldName = name
        name = newName
        for entry in try context.fetch(FetchDescriptor<JournalEntry>()) where entry.tags.contains(oldName) {
            entry.tags = entry.tags.map { $0 == oldName ? newName : $0 }
        }
        return .renamed
    }
}

// MARK: - 一篇日记只属于一本日记本

/// 📌 **2026-10 起一篇日记最多属于一本日记本**（产品决策）。一本都不选 = 只在「全部日记」里。
///
/// 数据结构不变：`JournalEntry.tags` 仍是 `[String]`（改类型要动 schema 和备份格式，不值得），
/// 约定**最多一个元素**。守住这条的是所有写入口：写日记 / 编辑页的选择器、草稿恢复、导入，
/// 以及下面这个一次性清理。
extension JournalEntry {
    /// 按单本规则整理一组日记本名字：去重后恰好一本 → 留下；一本没有或多于一本 → 空。
    ///
    /// 多于一本的不去猜「主要是哪本」，一律退回「全部日记」，由用户在编辑页重新选（2026-10-07 用户定）。
    static func singleNotebook(_ names: [String]) -> [String] {
        let unique = names.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return unique.count == 1 ? unique : []
    }
}

/// 把单本规则之前存下的「一篇在几本里」的日记整理掉。幂等，启动时跑一次（见 `TagMigrationRunner`）。
/// 只改 `tags`，不碰 `updatedAt` —— 这不是用户的编辑。
@MainActor
func migrateEntriesToSingleNotebook(context: ModelContext) {
    let entries: [JournalEntry]
    do {
        entries = try context.fetch(FetchDescriptor<JournalEntry>())
    } catch {
        let ns = error as NSError
        NSLog("❌ [Tag] 单本整理读取日记失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        return
    }
    var changed = 0
    for entry in entries {
        let single = JournalEntry.singleNotebook(entry.tags)
        if single != entry.tags {
            entry.tags = single
            changed += 1
        }
    }
    guard changed > 0 else { return }
    do {
        try context.save()
        NSLog("🔧 [Tag] 单本整理：%ld 篇日记的日记本归属已整理", changed)
    } catch {
        let ns = error as NSError
        NSLog("❌ [Tag] 单本整理保存失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
    }
}

// MARK: - 同名记录去重

/// 把**完全同名**的日记本记录合成一本。幂等，每次回到前台跑一次。
///
/// **为什么会有同名记录**：新设备首启时 iCloud 往往还没同步下来，
/// `ensureDefaultTagsExist` 看库是空的就先建一套「生活 / 读书笔记 / 旅行 / 工作」，
/// 之后同步下来的又是一套。CloudKit 不支持唯一约束，只能事后合。
///
/// **为什么合并是安全的**：日记靠名字挂在日记本上，同名的两条记录挂着的是同一批日记，
/// 删掉多余的那条不会让任何日记离开它的日记本。唯一可能丢的是那条记录的封面颜色。
///
/// **留哪一条必须是确定的**：两台设备会各自跑这个函数，再把删除同步给对方。
/// 如果 A 留 X 删 Y、B 留 Y 删 X，同步完两条都没了。
/// 所以按 (`createdAt`, `id`) 取最早的那条 —— 两边看到同一组记录时，选出来的一定是同一条。
///
/// > 只合**完全同名**的。仅大小写 / 全半角不同的（「Travel」与「travel」）
/// > 是新规则出来之前用户自己建的两本，挂着的日记不一样，自动合并就是替用户做决定 —— 不动。
@MainActor
func dedupeTagsByName(context: ModelContext) {
    let all: [Tag]
    do {
        all = try context.fetch(FetchDescriptor<Tag>())
    } catch {
        let ns = error as NSError
        NSLog("❌ [Tag] 去重时读取日记本失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        return
    }

    var removed = 0
    for (name, group) in Dictionary(grouping: all, by: \.name) where group.count > 1 && !name.isEmpty {
        let ordered = group.sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
        // 留下的那条缺什么、要删的有 → 转过来，别让用户刚设好的封面因为去重丢了（P5：本机缺的才补）。
        // 封面照片和版式是一套，一起转（只转照片的话，「白框」会变回默认的「满版」）；副标题单独看。
        // 都按同一个顺序取第一个，两台设备转的是同一份
        if let survivor = ordered.first {
            let rest = ordered.dropFirst()
            if (survivor.coverPhotoFilename ?? "").isEmpty,
               let donor = rest.first(where: { !($0.coverPhotoFilename ?? "").isEmpty }) {
                survivor.coverPhotoFilename = donor.coverPhotoFilename
                survivor.coverLayoutID = donor.coverLayoutID
            }
            if (survivor.subtitle ?? "").isEmpty,
               let subtitle = rest.compactMap(\.subtitle).first(where: { !$0.isEmpty }) {
                survivor.subtitle = subtitle
            }
        }
        for duplicate in ordered.dropFirst() {
            context.delete(duplicate)
            removed += 1
        }
    }
    guard removed > 0 else { return }

    do {
        try context.save()
        NSLog("🔧 [Tag] 合并了 %ld 条同名日记本记录", removed)
    } catch {
        let ns = error as NSError
        NSLog("❌ [Tag] 同名日记本去重保存失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
    }
}

// MARK: - 一次性迁移：旧 hex/textureID → 新 colorID/textureID

/// 将所有 Tag 的封面标识规整到当前的 `BookColor` + 亚麻体系。幂等：可重复调用。
@MainActor
func migrateTagsToBookCoverSystem(context: ModelContext) {
    let descriptor = FetchDescriptor<Tag>()
    guard let allTags = try? context.fetch(descriptor) else { return }
    var didChange = false

    for tag in allTags {
        // 0. 已下架的颜色 → 就近映射到保留色。
        //    必须先于下面几步做：这些 rawValue 现在已经不是合法 BookColor，
        //    不接住的话会一路掉进 `?? .wineRed`，
        //    橄榄褐、古铜、牛皮的日记本会一起变成酒红。
        if let replacement = BookColor.retiredColorReplacement[tag.colorID] {
            tag.colorID = replacement.rawValue
            didChange = true
        }

        // 1. 旧 hex → 新 colorID（仅当 colorID 还是默认 "WineRed" 且 color 字段有合法 hex 时映射）
        if (BookColor(rawValue: tag.colorID) == nil || tag.colorID == "WineRed"),
           let hex = tag.color,
           let mapped = BookColor.allCases.first(where: {
               $0.hex.caseInsensitiveCompare(hex) == .orderedSame
           }) {
            tag.colorID = mapped.rawValue
            didChange = true
        }

        // 2. 纹理一律亚麻（2026-10 皮革下架；更早的 "paper" / "canvas" / "denim" 本来也映射到亚麻）
        if tag.textureID != BookTexture.linen.rawValue {
            tag.textureID = BookTexture.linen.rawValue
            didChange = true
        }
    }

    if didChange {
        do {
            try context.save()
        } catch {
            let ns = error as NSError
            NSLog("❌ [Tag] 封面迁移保存失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        }
    }
}
