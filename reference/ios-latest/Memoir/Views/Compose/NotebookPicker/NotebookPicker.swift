import SwiftUI
import SwiftData

/// 转盘上的一本：「全部日记」或某一本日记本
struct PickerBook: Identifiable, Equatable {
    /// 「全部日记」是 `allID`，日记本是 `Tag.id.uuidString`
    let id: String
    /// 封面上的书名：日记本是用户起的名字（不翻译）；「全部日记」是按 App 语言翻好的
    let title: String
    let count: Int
    let color: BookColor
    let photo: CoverPhotoSource?
    let layout: CoverLayout
    /// 写进日记的日记本名；nil = 「全部日记」（不另外收进哪一本）
    let tagName: String?

    static let allID = "all"
    var isAll: Bool { tagName == nil }
}

/// 写日记之前先选写在哪一本里（2026-10-17 产品定）。
///
/// 一打开，正中是一本大大的「全部日记」（= 默认，不另外收进哪一本）。左右滑，像挑唱片那样一本本转过去：
/// 甩一下带着惯性一直转、慢慢停下，每过一本「笃」一声、震一下，转着的时候点一下就停（`NotebookCarousel`）。
/// 往右滑，左边转出来的是最后建的那本 —— 首尾相接，两个方向都能一直转。
/// 最底下「就写在这本里」确认；它上面一行小字「想做一本新的日记？」当场建一本，建好了转到它。
struct NotebookPicker: View {
    /// 选好了：日记本名；nil = 全部日记
    let onChoose: (String?) -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    /// 读一下让语言切换时重算「全部日记」那本的书名（封面上的书名不是 `Text(LocalizedStringKey)`）
    @Environment(\.locale) private var locale
    /// 和书架同一个顺序
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Query private var entries: [JournalEntry]

    @State private var centered = 0
    @State private var focus: String?
    @State private var showCreate = false
    /// 刚建好的那本：等新建页收下去再转过去，不然转的那一下被盖着看不见
    @State private var created: String?
    /// 新手指引 ②③：先给自己做一本（指「想做一本新的日记？」），做好了指「就写在这本里」
    @AppStorage(FirstStep.storageKey) private var firstStepRaw = 0
    @State private var chooseFrame: CGRect = .zero
    @State private var createFrame: CGRect = .zero

    var body: some View {
        let theme = themeManager.current
        let books = makeBooks()
        let book = books[safe: centered] ?? books[0]

        // 关闭和标题放进导航栏：✕ 和首页的 ＋、写日记页的 ‹ 一样大（导航栏给的玻璃圆底）
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 8)

                NotebookCarousel(books: books, centered: $centered, focus: $focus) {
                    onChoose(book.tagName)
                }
                .frame(maxHeight: 360)

                // 正中那本：书名、篇数。转的时候跟着换
                VStack(spacing: 6) {
                    Group {
                        if book.isAll {
                            Text("全部日记")
                        } else {
                            Text(verbatim: book.title)
                        }
                    }
                    .font(.custom("Georgia", size: 24))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    Group {
                        if book.isAll {
                            Text("默认 · \(book.count) 篇")
                        } else {
                            Text("\(book.count) 篇")
                        }
                    }
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                }
                .padding(.horizontal, 32)
                .padding(.top, 14)
                .accessibilityHidden(true)   // 转盘自己会念

                Spacer(minLength: 16)

                Button {
                    showCreate = true
                } label: {
                    Text("想做一本新的日记？")
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { createFrame = $0 }
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    // 新手指引：没做新本子、直接写在这本里也往下走
                    FirstStep.advance(to: .compose, from: [.createNotebook])
                    onChoose(book.tagName)
                } label: {
                    Text("就写在这本里")
                        .font(theme.bodyFont.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(theme.accent))
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { chooseFrame = $0 }
                .padding(.horizontal, 48)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .overlay {
                switch FirstStep(rawValue: firstStepRaw) {
                case .createNotebook where createFrame != .zero && !showCreate:
                    GuideHint(text: "先给自己做一本日记本", target: createFrame, below: false, theme: theme)
                case .compose where chooseFrame != .zero && !showCreate:
                    GuideHint(text: "就写在这一本里，\n点这里开始写", target: chooseFrame, below: false, theme: theme)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CircleIconButton(systemName: "xmark", prominence: .glass, theme: theme, size: 13) {
                        dismiss()
                    }
                    .accessibilityLabel(Text("关闭"))
                }
                ToolbarItem(placement: .principal) {
                    Text("写在哪一本里？")
                        .font(theme.headingFont)
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: {
            if let created {
                focus = created
                self.created = nil
            }
        }) {
            CreateTagSheet(
                existingNames: tags.map(\.name),
                onCreate: { name, edit in
                    let tag = NotebookMaker.create(name: name, edit: edit, after: tags, in: modelContext, errors: env.errors)
                    created = tag.id.uuidString
                    // 新手指引 ②→③：本子做好了，转盘转到它，接着指「就写在这本里」
                    FirstStep.advance(to: .compose, from: [.createNotebook])
                    showCreate = false
                },
                onCancel: { showCreate = false }
            )
            .presentationDetents([.large])
        }
    }

    /// 「全部日记」打头，后面按书架的顺序 —— 首尾相接后，「全部日记」左边就是最后建的那本
    private func makeBooks() -> [PickerBook] {
        _ = locale
        var counts: [String: Int] = [:]
        for entry in entries {
            for name in entry.tags { counts[name, default: 0] += 1 }
        }
        let all = PickerBook(
            id: PickerBook.allID,
            title: NSLocalizedString("全部日记", bundle: .appLanguage, comment: "书架上的第一本：全部日记"),
            count: entries.count,
            color: .ivory,
            photo: nil,
            layout: .fullBleed,
            tagName: nil
        )
        return [all] + tags.map { tag in
            PickerBook(
                id: tag.id.uuidString,
                title: tag.name,
                count: counts[tag.name, default: 0],
                color: tag.bookColor,
                photo: tag.coverPhoto,
                layout: tag.coverLayout,
                tagName: tag.name
            )
        }
    }
}

// MARK: - 写日记的入口

/// 「写下今天的故事」打开的那一页：先选写在哪本里（`NotebookPicker`），选好了就地换成写日记（`ComposeView`）。
///
/// 有草稿就直接接着写，不再问 —— 草稿里记着当时选的那本（`DraftEntry.tags`）。
/// 从某一本日记本里点「写一篇」的不走这里（已经在那本里了，见 `BookDetailView`）
struct ComposeFlow: View {
    @State private var stage: Stage

    private enum Stage: Equatable {
        case picking
        case writing(tags: [String])
    }

    init(hasDraft: Bool) {
        _stage = State(initialValue: hasDraft ? .writing(tags: []) : .picking)
    }

    var body: some View {
        ZStack {
            switch stage {
            case .picking:
                NotebookPicker { tagName in
                    withAnimation(.smooth(duration: 0.5)) {
                        stage = .writing(tags: tagName.map { [$0] } ?? [])
                    }
                }
                // 选好了：这一页轻轻放大着淡出，像凑近翻开那本
                .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 1.06))))
            case .writing(let tags):
                ComposeView(initialTags: tags)
                    .transition(.opacity)
            }
        }
    }
}
