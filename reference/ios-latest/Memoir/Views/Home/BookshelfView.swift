import SwiftUI
import SwiftData

struct BookshelfView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    /// 书架顺序：`sortOrder` 小的在前；迁移上来的老数据全是 0，按创建时间排（= 原来的顺序）
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Query private var entries: [JournalEntry]

    @State private var showCreateSheet = false
    @State private var editingTag: Tag?            // 完整编辑（改名+换封面）—— 当前未走，留着备用
    /// 导航路由：`"all"` = 全部日记，其余是日记本的 `id.uuidString`。
    /// 按 id 不按名字 —— 名字会被改，打开着的页面不该因为改名就找不到自己那本
    @State private var path: [String] = []

    // 📌 2026-10 取消了「8 本自建 + 1 本全部日记 = 铺满 3×3」的上限，日记本数量不再封顶。
    // 📌 2026-10 长按菜单（换封面 / 重命名 / 删除）挪进日记本页右上角的「…」（见 `BookDetailView`）：
    //    长按现在用来拿起书换位置，两者只能留一个。

    private static let allEntriesRoute = "all"

    var body: some View {
        let theme = themeManager.current
        NavigationStack(path: $path) {
            ShelfGridView(
                tags: tags,
                // 每本的篇数一次算完。不封顶以后书可能很多，
                // 原来每画一本书都把全部日记过滤一遍，是「本数 × 篇数」的开销
                counts: entryCountsByTag,
                allEntriesCount: entries.count,
                onOpenAll: { path.append(Self.allEntriesRoute) },
                onOpen: { path.append($0.id.uuidString) },
                onCreate: { showCreateSheet = true },
                onReorder: saveOrder
            )
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("日记本")
                        .font(theme.labelFont)
                        .tracking(theme.letterSpacingWide)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .navigationDestination(for: String.self) { route in
                if route == Self.allEntriesRoute {
                    BookDetailView(tag: nil)
                } else {
                    BookDetailView(tag: tags.first { $0.id.uuidString == route })
                }
            }
            // 新建
            .sheet(isPresented: $showCreateSheet) {
                CreateTagSheet(
                    existingNames: tags.map { $0.name },
                    onCreate: { name, edit in
                        NotebookMaker.create(name: name, edit: edit, after: tags, in: modelContext, errors: env.errors)
                        showCreateSheet = false
                    },
                    onCancel: { showCreateSheet = false }
                )
                .presentationDetents([.large])
            }
            // 完整编辑（名字 + 封面）—— 当前未走，但留着备用
            .sheet(item: $editingTag) { tag in
                EditTagSheet(
                    tag: tag,
                    existingNames: tags.filter { $0.id != tag.id }.map { $0.name },
                    onSave: { newName, edit in
                        let oldName = tag.name
                        tag.name = newName
                        applyCoverEdit(edit, to: tag)
                        for entry in entries where entry.tags.contains(oldName) {
                            if let idx = entry.tags.firstIndex(of: oldName) {
                                entry.tags[idx] = newName
                            }
                        }
                        save()
                        syncCoverIfNeeded(edit)
                        editingTag = nil
                    },
                    onCancel: { editingTag = nil }
                )
                .presentationDetents([.large])
            }
        }
    }

    /// 松手后把新顺序写进 `sortOrder`（0, 1, 2…）。只写真变了的，少触发几次 CloudKit 同步
    private func saveOrder(_ ids: [UUID]) {
        let byID = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for (index, id) in ids.enumerated() {
            guard let tag = byID[id], tag.sortOrder != index else { continue }
            tag.sortOrder = index
            changed = true
        }
        if changed { save() }
    }

    /// 篇数按日记本名字汇总（2026-10 起一篇日记最多在一本里）
    private var entryCountsByTag: [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for name in entry.tags { counts[name, default: 0] += 1 }
        }
        return counts
    }

    /// 新选的封面照片当场登记上云（存库之后调）—— 平时是 App 启动时才对账一次，
    /// 不顺手登记的话，要等下次打开 App 别的设备才看得到这张封面
    private func syncCoverIfNeeded(_ edit: CoverEdit) {
        if case .replaced = edit.photo { MediaStorage.syncToCloud(in: modelContext) }
    }

    /// 封面的改动落盘（不保存 context）
    private func applyCoverEdit(_ edit: CoverEdit, to tag: Tag) {
        do {
            try edit.apply(to: tag, in: modelContext)
        } catch {
            let ns = error as NSError
            NSLog("❌ [Bookshelf] 封面照片保存失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            env.errors.present(error, fallback: NSLocalizedString("保存失败", bundle: .appLanguage, comment: "通用保存失败"))
        }
    }

    /// 写库失败要让用户知道（`AppEnvironment.errors`），不能 `try?` 吞掉
    private func save() {
        do {
            try modelContext.save()
        } catch {
            let ns = error as NSError
            NSLog("❌ [Bookshelf] 保存日记本失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            env.errors.present(error, fallback: NSLocalizedString("保存失败", bundle: .appLanguage, comment: "通用保存失败"))
        }
    }
}

// MARK: - 新建日记本

/// 新建一本日记本：书架上的「新建」和写日记前选本子时的「想做一本新的日记？」共用
enum NotebookMaker {
    @discardableResult
    static func create(name: String, edit: CoverEdit, after tags: [Tag], in context: ModelContext, errors: ErrorPresenter) -> Tag {
        let tag = Tag(name: name, colorID: edit.color.rawValue)
        // 排到书架最后（`Tag.nextSortOrder` 的注释：每个新建入口都要用它）
        tag.sortOrder = Tag.nextSortOrder(after: tags)
        context.insert(tag)
        // 封面照片存失败不拦着建本子：本子照建（纯色封面），失败说出来
        do {
            try edit.apply(to: tag, in: context)
        } catch {
            let ns = error as NSError
            NSLog("❌ [Notebook] 封面照片保存失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            errors.present(error, fallback: NSLocalizedString("保存失败", bundle: .appLanguage, comment: "通用保存失败"))
        }
        do {
            try context.save()
        } catch {
            let ns = error as NSError
            NSLog("❌ [Notebook] 新建日记本保存失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            errors.present(error, fallback: NSLocalizedString("保存失败", bundle: .appLanguage, comment: "通用保存失败"))
        }
        // 新选的封面照片当场登记上云，不然要等下次打开 App 别的设备才看得到
        if case .replaced = edit.photo { MediaStorage.syncToCloud(in: context) }
        return tag
    }
}

struct CreateTagSheet: View {
    let existingNames: [String]
    let onCreate: (String, CoverEdit) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var edit = CoverEdit(color: .pineGreen)   // 默认墨绿
    @Environment(StoreKitManager.self) private var store
    @State private var showPaywall = false

    private var isNameTaken: Bool {
        Tag.isNameTaken(name, in: existingNames)
    }

    private var canCreate: Bool {
        !Tag.cleanedName(name).isEmpty && !isNameTaken
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 名称
                    VStack(alignment: .leading, spacing: 8) {
                        Text("名称")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        TextField("日记本名称", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        // 当场说明为什么「创建」是灰的
                        if isNameTaken {
                            Text("已有同名的日记本")
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }

                    BookCustomizerView(
                        previewName: Tag.cleanedName(name),
                        edit: $edit
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("新建日记本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        // 新选了会员版式 → 先问要不要开通（尺素会员）
                        if edit.needsMembership(originalLayout: nil, hasExistingPhoto: false) && !store.isMember {
                            showPaywall = true
                        } else {
                            onCreate(Tag.cleanedName(name), edit)
                        }
                    }
                    .disabled(!canCreate)
                }
            }
        }
        .paywallCover(isPresented: $showPaywall)
    }
}

// MARK: - 完整编辑日记本 sheet（备用，目前未走，已拆成 重命名 + 编辑封面）

private struct EditTagSheet: View {
    let tag: Tag
    /// 已排除自己
    let existingNames: [String]
    let onSave: (String, CoverEdit) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var edit: CoverEdit
    @Environment(StoreKitManager.self) private var store
    @State private var showPaywall = false

    init(tag: Tag,
         existingNames: [String],
         onSave: @escaping (String, CoverEdit) -> Void,
         onCancel: @escaping () -> Void) {
        self.tag = tag
        self.existingNames = existingNames
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: tag.name)
        _edit = State(initialValue: CoverEdit(tag: tag))
    }

    private var canSave: Bool {
        !Tag.cleanedName(name).isEmpty && !Tag.isNameTaken(name, in: existingNames)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("名称")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        TextField("日记本名称", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }

                    BookCustomizerView(
                        previewName: Tag.cleanedName(name),
                        edit: $edit,
                        existingPhoto: tag.coverPhotoFilename
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("编辑日记本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if edit.needsMembership(originalLayout: tag.coverPhotoFilename == nil ? nil : tag.coverLayout,
                                                hasExistingPhoto: tag.coverPhotoFilename != nil) && !store.isMember {
                            showPaywall = true
                        } else {
                            onSave(Tag.cleanedName(name), edit)
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .paywallCover(isPresented: $showPaywall)
    }
}

// MARK: - 编辑封面 sheet（日记本页「…」入口，见 `BookDetailView`）

struct CoverChangeSheet: View {
    let tag: Tag
    let onSave: (CoverEdit) -> Void
    let onCancel: () -> Void

    @State private var edit: CoverEdit
    @Environment(StoreKitManager.self) private var store
    @State private var showPaywall = false

    init(tag: Tag,
         onSave: @escaping (CoverEdit) -> Void,
         onCancel: @escaping () -> Void) {
        self.tag = tag
        self.onSave = onSave
        self.onCancel = onCancel
        _edit = State(initialValue: CoverEdit(tag: tag))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                BookCustomizerView(
                    previewName: tag.name,
                    edit: $edit,
                    existingPhoto: tag.coverPhotoFilename
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("编辑封面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        // 新选了会员版式 → 先问要不要开通；原来就用着的会员版式不拦（到期也不收回）
                        if edit.needsMembership(originalLayout: tag.coverPhotoFilename == nil ? nil : tag.coverLayout,
                                                hasExistingPhoto: tag.coverPhotoFilename != nil) && !store.isMember {
                            showPaywall = true
                        } else {
                            onSave(edit)
                        }
                    }
                }
            }
        }
        .paywallCover(isPresented: $showPaywall)
    }
}

// MARK: - 新建按钮

struct NewBookButton: View {
    let theme: any AppTheme

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 20))
                .foregroundStyle(theme.textTertiary)
            Text("新建")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.73, contentMode: .fit)    // 与 BookCoverView 同比例
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(theme.border)
        )
    }
}
