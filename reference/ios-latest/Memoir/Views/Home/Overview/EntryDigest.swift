import SwiftUI

/// 一篇日记在总览格子里要显示的东西，算一次记下来。
///
/// 正文存在 `contentBlocksData`（JSON）里，`coverPhotoFilename`、`textPreview` 每取一次都要解一遍 JSON；
/// 日期的几种写法每次都新建一个 DateFormatter。一屏 64 格、滚动时格子不停地新建，这些都不能放在 body 里现算。
/// 按「日记 id + 改过的时间 + App 语言」记，日记改了、换了语言就重算
struct EntryDigest {
    let id: UUID
    let date: Date
    /// 标题；没写标题用正文第一行；都空是 nil（显示「无题」）
    let title: String?
    let preview: String
    let cover: String?
    let mood: MoodLevel?
    /// 「2026年10月」/「October 2026」：总览按它分组
    let monthKey: String
    /// 年 × 100 + 月：分组比字符串快
    let month: Int
    /// 「10月19日 星期一」
    let dayAndWeekday: String
    /// 「19日 周一」/「Mon 19」
    let dayWithWeekday: String
    let day: Int

    var titleText: Text {
        title.map { Text(verbatim: $0) } ?? Text("无题")
    }

    var accessibilityText: String {
        [dayAndWeekday, title ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

extension EntryDigest {
    private struct Stamp: Equatable {
        let updatedAt: Date
        let date: Date
        let locale: String
    }

    @MainActor private static var cache: [UUID: (stamp: Stamp, digest: EntryDigest)] = [:]

    @MainActor
    static func of(_ entry: JournalEntry) -> EntryDigest {
        let locale = appLocale
        let stamp = Stamp(updatedAt: entry.updatedAt, date: entry.date, locale: locale.identifier)
        if let hit = cache[entry.id], hit.stamp == stamp { return hit.digest }

        // 正文只解这一次
        let blocks = entry.contentBlocks
        let photos = blocks.filter { $0.type == .photo }
        let cover = photos.first(where: { $0.isCover == true })?.photoFilename ?? photos.first?.photoFilename
        let preview = blocks
            .compactMap { $0.type == .text ? $0.visibleText : nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = preview.split(whereSeparator: \.isNewline).first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        let title: String? = !trimmedTitle.isEmpty ? trimmedTitle : (firstLine.isEmpty ? nil : String(firstLine.prefix(30)))

        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day], from: entry.date)
        let digest = EntryDigest(
            id: entry.id,
            date: entry.date,
            title: title,
            preview: preview,
            cover: cover,
            mood: entry.moodLevel,
            monthKey: entry.date.yearMonthKey(locale: locale),
            month: (parts.year ?? 0) * 100 + (parts.month ?? 0),
            dayAndWeekday: entry.date.dayAndWeekday(locale: locale),
            dayWithWeekday: entry.date.formatted(Date.FormatStyle(locale: locale).day().weekday(.abbreviated)),
            day: parts.day ?? 0
        )
        cache[entry.id] = (stamp, digest)
        return digest
    }
}
