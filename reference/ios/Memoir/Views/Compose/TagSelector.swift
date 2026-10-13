import SwiftUI
import SwiftData

/// 写日记 / 编辑日记页的「收进日记本」。
///
/// 数据上日记本就是 `JournalEntry.tags` 里的名字，这里是它的选择器：
/// - 按书架顺序列出全部日记本，**单选**：一篇日记最多属于一本（2026-10 规则，见 `JournalEntry.singleNotebook`）。
///   点另一本 = 换过去；再点一下已选的 = 取消
/// - 当场新建日记本，建完自动选中
/// - **一本都不选 = 只在「全部日记」里**。「全部日记」不是 `Tag`，所有日记天然都在里面，
///   所以不选不需要写任何东西，下面那行提示只是把这件事告诉用户
struct TagSelector: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var env
    /// 与书架同一个顺序（见 `BookshelfView`）
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var allTags: [Tag]
    /// 最多一个元素。保留数组是为了和 `JournalEntry.tags` / `DraftEntry.tags` 对得上
    @Binding var selectedTags: [String]
    @State private var showAddTag = false
    @State private var newTagName = ""

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allTags) { tag in
                            chip(for: tag, theme: theme)
                                .id(tag.name)
                        }

                        Button {
                            showAddTag = true
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10))
                                Text("新建")
                                    .font(theme.captionFont)
                            }
                            .foregroundStyle(theme.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(
                                Capsule()
                                    .stroke(theme.border, style: StrokeStyle(lineWidth: 0.5, dash: [3]))
                            )
                        }
                        .buttonStyle(.plain)
                        .id(Self.newButtonID)
                    }
                    .padding(.vertical, 2)   // 选中时 1.05 倍放大，留点余地不被裁
                }
                // 新建的那本排在最后，可能在屏幕外 —— 滚过去让用户看到它已经被选上了
                .onChange(of: allTags.count) { old, new in
                    guard new > old else { return }
                    withAnimation { proxy.scrollTo(Self.newButtonID, anchor: .trailing) }
                }
            }

            // 一本都不选时说清楚去向，否则用户会担心这篇日记「没地方放」
            if selectedTags.isEmpty {
                Text("不选的话，只收在「全部日记」里")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: selectedTags.isEmpty)
        .alert("新建日记本", isPresented: $showAddTag) {
            TextField("日记本名称", text: $newTagName)
            Button("取消", role: .cancel) { newTagName = "" }
            Button("创建") { createAndSelect() }
        }
    }

    private static let newButtonID = "__new_notebook__"

    private func chip(for tag: Tag, theme: any AppTheme) -> some View {
        let isSelected = selectedTags.contains(tag.name)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                toggleTag(tag.name)
            }
        } label: {
            HStack(spacing: 5) {
                // 封面色小书脊：让用户一眼对上书架上的那本
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(hex: tag.bookColor.hex))
                    .frame(width: 7, height: 11)
                    .overlay(
                        RoundedRectangle(cornerRadius: 1.5)
                            .stroke(Color.black.opacity(tag.bookColor.isLight ? 0.15 : 0), lineWidth: 0.5)
                    )
                // 名字是用户数据，不查翻译表
                Text(verbatim: tag.name)
                    .font(theme.captionFont)
                    .foregroundStyle(isSelected ? theme.cardBackground : theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? theme.accent : Color.clear)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? theme.accent : theme.border, lineWidth: 0.5)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func createAndSelect() {
        defer { newTagName = "" }
        let typed = Tag.cleanedName(newTagName)
        guard !typed.isEmpty else { return }

        // 已有同名（含大小写 / 全半角不同）的日记本 → 直接选中那本，不另建。
        // 用库里那本的原名，否则「travel」会挂不上「Travel」那本
        let key = Tag.nameKey(typed)
        let name: String
        if let existing = allTags.first(where: { Tag.nameKey($0.name) == key }) {
            name = existing.name
        } else {
            name = typed
            let tag = Tag(name: name, colorID: Self.quietestColor(among: allTags).rawValue)
            tag.sortOrder = Tag.nextSortOrder(after: allTags)
            modelContext.insert(tag)
            do {
                try modelContext.save()
            } catch {
                let ns = error as NSError
                NSLog("❌ [TagSelector] 新建日记本保存失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
                env.errors.present(error, fallback: NSLocalizedString("保存失败", bundle: .appLanguage, comment: "通用保存失败"))
                return
            }
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedTags = [name]
        }
    }

    /// 写日记时顺手建的本子没机会挑颜色，给它一个书架上用得最少的颜色，
    /// 免得连建几本全是同一个颜色、摆在架子上分不清。
    /// 象牙白不参与：那是「全部日记」的门面色。并列时按 `BookColor` 的声明顺序取，结果是确定的。
    private static func quietestColor(among tags: [Tag]) -> BookColor {
        var usage: [BookColor: Int] = [:]
        for tag in tags { usage[tag.bookColor, default: 0] += 1 }
        let candidates = BookColor.allCases.filter { $0 != .ivory }
        return candidates.min { usage[$0, default: 0] < usage[$1, default: 0] } ?? .pineGreen
    }

    private func toggleTag(_ name: String) {
        selectedTags = selectedTags.contains(name) ? [] : [name]
    }
}
