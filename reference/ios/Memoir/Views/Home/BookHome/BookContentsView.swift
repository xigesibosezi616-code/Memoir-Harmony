import SwiftUI
import UIKit

/// 日记本的目录（参考图 ④ 列表 / ⑤ 宫格）。
///
/// 日记按**阅读顺序（从早到晚）**排好再传进来，编号就是在这本里的第几篇 ——
/// 和翻页阅读器往后翻的方向一致（见 `PageDataSource.readingOrder`）。
struct BookContentsView: View {
    enum Layout: String {
        case list
        case grid
    }

    /// 已按阅读顺序排好
    let entries: [JournalEntry]
    let layout: Layout
    var onOpen: (JournalEntry) -> Void
    var onCompose: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        switch layout {
        case .list: list(theme: theme)
        case .grid: grid(theme: theme)
        }
    }

    // MARK: - 列表：按月分组，编号 · 标题 · 日期

    private struct MonthGroup: Identifiable {
        let id: String
        let title: String
        var items: [(number: Int, entry: JournalEntry)]
    }

    /// 按月切段，顺序沿用阅读顺序（不重新排）
    private var monthGroups: [MonthGroup] {
        var groups: [MonthGroup] = []
        for (index, entry) in entries.enumerated() {
            let comps = Calendar.current.dateComponents([.year, .month], from: entry.date)
            let id = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if groups.last?.id == id {
                groups[groups.count - 1].items.append((index + 1, entry))
            } else {
                groups.append(MonthGroup(id: id, title: Self.monthTitle(entry.date), items: [(index + 1, entry)]))
            }
        }
        return groups
    }

    private func list(theme: any AppTheme) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(monthGroups) { group in
                Text(verbatim: group.title)
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.top, 22)
                    .padding(.bottom, 4)

                ForEach(group.items, id: \.entry.id) { item in
                    Button { onOpen(item.entry) } label: {
                        row(number: item.number, entry: item.entry, theme: theme)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 22)
    }

    private func row(number: Int, entry: JournalEntry, theme: any AppTheme) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(number)")
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 36, alignment: .leading)
            Self.titleText(for: entry)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(verbatim: Self.dayTitle(entry.date))
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.vertical, 15)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 0.5)
        }
    }

    // MARK: - 宫格：一页页小样

    private func grid(theme: any AppTheme) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 18) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button { onOpen(entry) } label: {
                    VStack(spacing: 6) {
                        EntryPageThumbnail(entry: entry)
                        Text("\(index + 1)")
                            .font(.system(size: 11, design: .serif))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            // 最后一格：写一篇（参考图 ⑤ 的 Add）
            Button(action: onCompose) {
                VStack(spacing: 6) {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .light))
                        Text("写一篇")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.73, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(style: StrokeStyle(lineWidth: 0.8, dash: [4]))
                            .foregroundStyle(theme.border)
                    )
                    Text(verbatim: " ").font(.system(size: 11))   // 与上面各格的编号行对齐
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    // MARK: - 文案

    /// 标题；没写标题的用正文第一行；正文也空就是「无题」
    static func titleText(for entry: JournalEntry) -> Text {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return Text(verbatim: title) }
        let firstLine = entry.textPreview
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        if !firstLine.isEmpty { return Text(verbatim: String(firstLine.prefix(30))) }
        return Text("无题")
    }

    /// 「2026年9月」/「September 2026」/「2026年9月」(ja) …… 用系统模板，各语言的年月顺序都对
    static func monthTitle(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: appLocale).year().month(.wide))
    }

    /// 「9月27日」/「Sep 27」/「27 sept.」……
    static func dayTitle(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: appLocale).month(.abbreviated).day())
    }
}

// MARK: - 宫格里的一页

/// 一篇日记的小样：有照片的上半是照片、下面标题；没照片的就是一页纸，标题加几行正文
private struct EntryPageThumbnail: View {
    let entry: JournalEntry

    @Environment(ThemeManager.self) private var themeManager
    @State private var photo: UIImage?

    var body: some View {
        let theme = themeManager.current
        let photoName = entry.coverPhotoFilename
        // 纸张的尺寸由底下这块 Color 定（宽 × 0.73 的比例），内容放在 overlay 里 ——
        // 照片怎么铺都撑不大这一页，标题也不会被挤出去（2026-10-08 实测踩过）
        theme.cardBackground
            .aspectRatio(0.73, contentMode: .fit)
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if photoName != nil {
                        // 照片取方形，占这页上面六成多，下面留给标题
                        Color(hex: "#E8DDC9").opacity(0.5)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if let photo {
                                    Image(uiImage: photo)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .transition(.opacity)
                                }
                            }
                            .clipped()
                    }
                    BookContentsView.titleText(for: entry)
                        .font(.system(size: 9, weight: .medium, design: .serif))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                    if photoName == nil {
                        Text(verbatim: entry.textPreview)
                            .font(.system(size: 7))
                            .foregroundStyle(theme.textSecondary)
                            .lineSpacing(1.5)
                            .lineLimit(9)
                    }
                }
                .padding(7)
            }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
        .task(id: photoName) {
            guard let photoName else { return }
            let image = await EntryThumbnailCache.image(photoName)
            withAnimation(.easeOut(duration: 0.2)) { photo = image }
        }
    }
}

/// 宫格小样的照片缓存。小样只有约 110pt 宽，按 300px 解码，不碰正文那套 600px 的缓存
@MainActor
private enum EntryThumbnailCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 150
        return c
    }()

    static func image(_ filename: String) async -> UIImage? {
        if let hit = cache.object(forKey: filename as NSString) { return hit }
        let url = PhotoPaperIO.photosDirectory.appendingPathComponent(filename)
        let image = await Task.detached(priority: .utility) {
            NotebookCoverStore.downsample(url, maxPixels: 300)
        }.value
        if let image { cache.setObject(image, forKey: filename as NSString) }
        return image
    }
}
