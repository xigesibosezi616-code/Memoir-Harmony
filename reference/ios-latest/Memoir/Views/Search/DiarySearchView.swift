import SwiftUI
import SwiftData

/// 搜日记（2026-10-26）：底部标签栏的搜索标签（系统原生：iOS 26 起是右边单独的一颗放大镜，点开在底部展开搜索框）。
///
/// - 搜**标题和正文**：正文用 `JournalEntry.content`（正文的纯文字，划掉的字不在里面 —— 本来就是给搜索留的）
/// - 不分大小写、全半角、变音符号；空格隔开的几个词**都要有**才算
/// - 结果按日期从新到旧，每条显示日期、所在日记本、标题，和关键字附近的一小段原文（关键字高亮）；点进去就是那篇日记
struct DiarySearchView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(LanguageManager.self) private var languageManager
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]

    @State private var query = ""
    /// 敲字时不每一下都全量过滤：停 0.15 秒再算
    @State private var results: [JournalEntry] = []
    @State private var searchedTerms: [String] = []

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            Group {
                if searchedTerms.isEmpty {
                    ContentUnavailableView {
                        Label("搜索日记", systemImage: "magnifyingglass")
                    } description: {
                        Text("搜标题和正文里写过的字")
                    }
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label("没有找到", systemImage: "magnifyingglass")
                    } description: {
                        Text("没有含「\(query.trimmingCharacters(in: .whitespaces))」的日记")
                    }
                } else {
                    List {
                        Section {
                            ForEach(results) { entry in
                                NavigationLink(value: entry) {
                                    SearchResultRow(entry: entry, terms: searchedTerms, theme: theme)
                                }
                                .listRowBackground(SettingsPalette.card(themeManager.currentThemeID))
                            }
                        } header: {
                            Text("\(results.count) 篇日记")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 和设置页一样的分层：页面底比卡片深一点
            .background(SettingsPalette.page(themeManager.currentThemeID))
            // 标题和占位字交给 UIKit，按 App 语言查好再给，切语言才跟着变（见 `LanguageManager.bundle`）
            .navigationTitle(NSLocalizedString("搜索", bundle: languageManager.bundle, comment: "搜索页标题"))
            .searchable(text: $query, prompt: NSLocalizedString("搜索日记", bundle: languageManager.bundle, comment: "搜索框占位"))
            .navigationDestination(for: JournalEntry.self) { entry in
                EntryDetailView(entry: entry)
            }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                runSearch()
            }
            // 写了新日记 / 改了日记，结果跟着变
            .onChange(of: entries.count) { runSearch() }
        }
        .tint(theme.accent)
    }

    private func runSearch() {
        let terms = DiarySearch.terms(of: query)
        searchedTerms = terms
        results = terms.isEmpty ? [] : entries.filter { DiarySearch.matches($0, terms: terms) }
    }
}

/// 匹配和截取的规则，搜索页和测试共用
enum DiarySearch {
    /// 底栏要不要出搜索那颗圆（设置 → 外观 →「搜索日记」）。**默认关**：关着就是原来四个 tab（用户定，2026-10-27）
    static let tabStorageKey = "showSearchTab"

    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// 空格（含全角空格）隔开的几个词
    static func terms(of query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
    }

    /// 每个词都要在标题或正文里出现
    static func matches(_ entry: JournalEntry, terms: [String]) -> Bool {
        terms.allSatisfy { term in
            entry.title.range(of: term, options: options) != nil || entry.content.range(of: term, options: options) != nil
        }
    }

    /// 正文里第一个关键字附近的一小段：前面留 14 个字、后面留到 60 个字左右，截断处加省略号；换行压成空格
    static func snippet(of text: String, terms: [String]) -> String? {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let hits = terms.compactMap { flat.range(of: $0, options: options) }
        guard let first = hits.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        let start = flat.index(first.lowerBound, offsetBy: -14, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(start, offsetBy: 74, limitedBy: flat.endIndex) ?? flat.endIndex
        var piece = String(flat[start..<end]).trimmingCharacters(in: .whitespaces)
        if start > flat.startIndex { piece = "…" + piece }
        if end < flat.endIndex { piece += "…" }
        return piece
    }

    /// 把文字里的关键字标出来：普通字一段、关键字一段（主题色加粗）拼起来。
    /// 不用 AttributedString —— 里面有一段带了颜色属性，外面 `.font` / `.foregroundStyle` 就整行都不管用了（模拟器实测：整行变成强调色、主题字体也没了）
    static func highlightedText(_ text: String, terms: [String], base: Color, accent: Color) -> Text {
        var ranges: [Range<String.Index>] = []
        for term in terms {
            var from = text.startIndex
            while from < text.endIndex, let r = text.range(of: term, options: options, range: from..<text.endIndex) {
                ranges.append(r)
                from = r.upperBound
            }
        }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for r in ranges {
            if let last = merged.last, r.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }
        var result = Text(verbatim: "")
        var cursor = text.startIndex
        for r in merged {
            if cursor < r.lowerBound {
                result = result + Text(verbatim: String(text[cursor..<r.lowerBound])).foregroundStyle(base)
            }
            result = result + Text(verbatim: String(text[r])).foregroundStyle(accent).bold()
            cursor = r.upperBound
        }
        if cursor < text.endIndex {
            result = result + Text(verbatim: String(text[cursor...])).foregroundStyle(base)
        }
        return result
    }
}

private struct SearchResultRow: View {
    let entry: JournalEntry
    let terms: [String]
    let theme: any AppTheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(verbatim: "\(Calendar.current.component(.day, from: entry.date))")
                    .font(.custom("Georgia", size: 20))
                    .foregroundStyle(theme.textPrimary)
                Text(verbatim: entry.date.formatted(.dateTime.month(.abbreviated).locale(appLocale)))
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                // 标题、正文是用户写的，不查翻译表
                if !entry.title.isEmpty {
                    DiarySearch.highlightedText(entry.title, terms: terms, base: theme.textPrimary, accent: theme.accent)
                        .font(theme.bodyFont)
                        .lineLimit(1)
                }
                if let snippet = DiarySearch.snippet(of: entry.content, terms: terms)
                    ?? (entry.title.isEmpty ? nil : firstLine) {
                    DiarySearch.highlightedText(snippet, terms: terms, base: theme.textSecondary, accent: theme.accent)
                        .font(theme.captionFont)
                        .lineLimit(3)
                }
                Text(verbatim: footnote)
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var firstLine: String? {
        entry.content.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
            .map { String($0.prefix(60)) }
    }

    /// 「2026 年 10 月 · 日记本名」
    private var footnote: String {
        let month = entry.date.formatted(.dateTime.year().month(.wide).locale(appLocale))
        guard let book = entry.tags.first, !book.isEmpty else { return month }
        return "\(month) · \(book)"
    }
}
