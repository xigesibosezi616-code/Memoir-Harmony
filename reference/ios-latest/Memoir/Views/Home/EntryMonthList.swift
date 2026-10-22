import SwiftUI

/// 记录页列表模式的两种看法（2026-10-22 用户定，同信箱的「全部来信 / 按日期」）。
/// 存进 UserDefaults 的是 rawValue（记住上次选的）
enum HomeListGrouping: String, CaseIterable {
    /// 原来的样子：一篇一张卡片，月份标题吸顶
    case all
    /// 一月一张卡片，点组头展开 / 收起 —— 日记多了，先找到哪个月再点开
    case month

    static let storageKey = "homeListGrouping"

    var title: LocalizedStringKey {
        switch self {
        case .all:   return "全部日记"
        case .month: return "按月份"
        }
    }
}

/// 列表顶上的切换（样子同信箱顶上那个）
struct HomeListGroupingPicker: View {
    @Binding var selection: HomeListGrouping
    let theme: any AppTheme
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HomeListGrouping.allCases, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.smooth(duration: 0.25)) { selection = option }
                } label: {
                    Text(option.title)
                        .font(theme.captionFont)
                        .foregroundStyle(selected ? theme.accent : theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(theme.accent.opacity(0.14))
                                    .matchedGeometryEffect(id: "selected", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.cardBackground))
        .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
    }
}

/// 按月份：一月一张卡片，最近的月份在上（同信箱的「按日期」）。
///
/// - 组头：月份 …… 几篇 · ›（几篇只写数字，免得七种语言各配一套单复数）；点组头展开 / 收起
/// - **没动过的时候只展开最近的那个月**；切到「全部日记」或大屏再回来就忘（展开状态只活在这一层视图里）
/// - 展开后组里一行一篇，最近的在上，点一行进详情
struct EntryMonthCards: View {
    /// 已经按月分好、最近的在前（`HomeView.groupedEntries`）
    let groups: [(key: String, entries: [JournalEntry])]
    let theme: any AppTheme

    /// 动过之后展开着的月份；nil = 还没动过
    @State private var opened: Set<String>?

    private func isExpanded(_ key: String) -> Bool {
        if let opened { return opened.contains(key) }
        return key == groups.first?.key
    }

    private func toggle(_ key: String) {
        var set = opened ?? Set(groups.first.map { [$0.key] } ?? [])
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        opened = set
    }

    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(groups, id: \.key) { group in
                monthCard(group, expanded: isExpanded(group.key))
            }
        }
    }

    private func monthCard(_ group: (key: String, entries: [JournalEntry]), expanded: Bool) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { toggle(group.key) }
            } label: {
                header(group, expanded: expanded)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(group.key), \(group.entries.count)"))
            .accessibilityHint(expanded ? Text("收起") : Text("展开"))
            .accessibilityAddTraits(.isButton)

            if expanded {
                Divider().overlay(theme.border)
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().overlay(theme.border).padding(.leading, 68)
                    }
                    NavigationLink(value: entry) {
                        EntryCompactRow(entry: entry, theme: theme)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// 组头：月份 …… 几篇 · ›
    private func header(_ group: (key: String, entries: [JournalEntry]), expanded: Bool) -> some View {
        HStack(spacing: 12) {
            // 月份是按 App 语言排好的日期（同「全部日记」里的月份标题），原样显示
            Text(verbatim: group.key)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(verbatim: "\(group.entries.count)")
                .font(theme.labelFont.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(theme.surfaceBackground))
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

/// 月份卡片里的一行：左边几号、星期，右边标题（没标题用正文第一行，再没有「无题」）和一行正文，心情在最右
struct EntryCompactRow: View {
    let entry: JournalEntry
    let theme: any AppTheme

    /// 正文第一行（去掉空行和首尾空白）
    private var firstLine: String? {
        entry.content
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(verbatim: "\(Calendar.current.component(.day, from: entry.date))")
                    .font(.custom("Georgia", size: 20))
                    .foregroundStyle(theme.textPrimary)
                Text(verbatim: entry.date.formatted(.dateTime.weekday(.abbreviated).locale(appLocale)))
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                // 标题、正文是用户写的，不查翻译表
                Group {
                    if !entry.title.isEmpty {
                        Text(verbatim: entry.title)
                    } else if let firstLine {
                        Text(verbatim: String(firstLine.prefix(30)))
                    } else {
                        Text("无题")
                    }
                }
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)

                if !entry.title.isEmpty, let firstLine {
                    Text(verbatim: String(firstLine.prefix(60)))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let level = entry.moodLevel {
                MoodBadge(level: level)
            }
        }
    }
}
