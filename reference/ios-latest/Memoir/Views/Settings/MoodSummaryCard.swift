import SwiftUI

/// 写作统计「情绪捕捉」最上面的情绪小结（2026-10-27，会员）：每周 / 每月 / 每年一份，一段小结 + 两三条建议。
///
/// - 会员：切换周 / 月 / 年，看最新那一期；正在写、没写成、还没有（不够 3 篇）各有一句话；往期在「往期小结」里
/// - 不是会员：一张说明卡，点了弹付费页
/// - 心情很沉的那一期（`heavy`）：下面附求助卡片，和危险的那封信同一张（`CrisisHelpCard`）
struct MoodSummaryCard: View {
    @Environment(ThemeManager.self) private var themeManager
    /// 全部小结，新的在前
    let summaries: [MoodSummary]
    let writing: Set<MoodSummary.Period>
    let failed: Set<MoodSummary.Period>
    let isMember: Bool
    let isLoggedIn: Bool
    let onRetry: (MoodSummary.Period) -> Void
    let onUnlock: () -> Void

    @State private var period: MoodSummary.Period = .week
    @State private var showHistory = false

    private var latest: MoodSummary? { summaries.first { $0.periodKind == period } }

    var body: some View {
        let theme = themeManager.current
        ThemedCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Text("情绪小结")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                        .tracking(theme.letterSpacingWide)
                    if !isMember { MemberBadge(size: 15) }
                    Spacer()
                    if isMember { periodPicker(theme) }
                }
                if isMember { memberContent(theme) } else { teaser(theme) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showHistory) {
            MoodSummaryHistorySheet(summaries: summaries.filter { $0.periodKind == period }, period: period)
        }
    }

    // MARK: -

    private func periodPicker(_ theme: any AppTheme) -> some View {
        HStack(spacing: 4) {
            ForEach(MoodSummary.Period.allCases, id: \.self) { p in
                let on = p == period
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { period = p }
                } label: {
                    Text(p.shortTitle)
                        .font(theme.labelFont)
                        .foregroundStyle(on ? theme.background : theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(on ? theme.accent : Color.clear)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(on ? Color.clear : theme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func memberContent(_ theme: any AppTheme) -> some View {
        if writing.contains(period) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在写这一期的小结…")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }
        } else if failed.contains(period), latest == nil {
            HStack {
                Text("这期小结没写成，下次打开会再试。")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Button { onRetry(period) } label: {
                    Text("重试").font(theme.labelFont).foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
            }
        }

        if let summary = latest {
            MoodSummaryBody(summary: summary)
            if summaries.filter({ $0.periodKind == period }).count > 1 {
                Button { showHistory = true } label: {
                    HStack(spacing: 4) {
                        Text("往期小结")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                    }
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        } else if !writing.contains(period) && !failed.contains(period) {
            Text(isLoggedIn ? period.emptyHint : "登录尺素账号后，每过完一期就会自动写一份小结。")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func teaser(_ theme: any AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("每周、每月、每年，一段小结和几条建议，陪你看清这段时间的心情。")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onUnlock) {
                Text("了解尺素会员")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.background)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(theme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// 一期小结的正文：哪一段时间、小结、建议；很沉的那期附求助卡片
struct MoodSummaryBody: View {
    @Environment(ThemeManager.self) private var themeManager
    let summary: MoodSummary

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: summary.periodLabel)   // 已按 appLocale 格式化，是数据不是文案
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
            Text(verbatim: summary.text)          // 服务端按 App 语言写好的
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(summary.suggestionList.enumerated()), id: \.offset) { _, s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(theme.accent.opacity(0.6)).frame(width: 5, height: 5)
                        Text(verbatim: s)
                            .font(theme.labelFont)
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 2)
            if summary.heavy {
                CrisisHelpCard(language: summary.language, palette: LetterPalette.of(themeID: themeManager.currentThemeID))
                    .padding(.top, 6)
            }
        }
    }
}

/// 往期小结：同一种（周 / 月 / 年）的全部，新的在前
private struct MoodSummaryHistorySheet: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss
    let summaries: [MoodSummary]
    let period: MoodSummary.Period

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(summaries) { summary in
                        ThemedCard { MoodSummaryBody(summary: summary).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("往期小结")
                        .font(theme.labelFont)
                        .tracking(theme.letterSpacingWide)
                        .foregroundStyle(theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("完成").font(theme.labelFont).foregroundStyle(theme.accent)
                    }
                }
            }
        }
    }
}

extension MoodSummary.Period {
    var shortTitle: LocalizedStringKey {
        switch self {
        case .week: return "周"
        case .month: return "月"
        case .year: return "年"
        }
    }

    var emptyHint: LocalizedStringKey {
        switch self {
        case .week: return "每过完一周，打开这里就会有一份那一周的小结（那一周要记满 3 篇心情）。"
        case .month: return "每过完一个月，打开这里就会有一份那个月的小结（那个月要记满 3 篇心情）。"
        case .year: return "每过完一年，打开这里就会有一份那一年的小结（那一年要记满 3 篇心情）。"
        }
    }
}

extension MoodSummary {
    /// 「10月19日至25日」「2026年10月」「2026年」，按 App 语言
    var periodLabel: String {
        switch periodKind {
        case .week:
            let f = DateIntervalFormatter()
            f.locale = appLocale
            f.dateTemplate = "MMMd"
            return f.string(from: periodStart, to: periodEnd.addingTimeInterval(-1))
        case .month:
            let f = DateFormatter()
            f.locale = appLocale
            f.setLocalizedDateFormatFromTemplate("yMMMM")
            return f.string(from: periodStart)
        case .year:
            let f = DateFormatter()
            f.locale = appLocale
            f.setLocalizedDateFormatFromTemplate("y")
            return f.string(from: periodStart)
        }
    }
}
