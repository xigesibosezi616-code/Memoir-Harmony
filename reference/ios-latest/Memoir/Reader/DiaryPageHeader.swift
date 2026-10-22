import SwiftUI
import UIKit

/// 每篇日记首页顶部的页眉：月份 + 日期大数字（前小后大）+ 写完时的心情 + 星期 + 短分割线 + 标题 + 标签。
/// 参考素笺主题 `EntryDetailView` 的 washiLayout 顶部结构，约束同一风格。
///
/// > 2026-09 之前这是一整页「扉页」（`CoverPageView`），正文要再翻一页才开始 ——
/// > 读者看到的是标题孤零零占一页（2026-09-16 实机反馈）。现在它只是正文首页的页眉。
///
/// ⚠️ 版式数字都在 `Metrics` 里，`estimatedHeight` 也按它们算 —— `Paginator` 靠它给首页正文留位置。
/// 改间距 / 字号时高度估算会自动跟上；**但加了新的一行元素，记得在 `estimatedHeight` 里也加上**，
/// 否则首页会装不下、正文被截断。
struct DiaryPageHeader: View {
    let diary: JournalEntry
    /// ⚠️ 靠 `PageContentViewController` 手工注入 —— 阅读器的每一页都活在
    /// 独立的 `UIHostingController` 里，**拿不到外层 SwiftUI 的 environment**。
    @Environment(ThemeManager.self) private var themeManager

    enum Metrics {
        static let monthFontSize: CGFloat = 11
        static let monthBottomGap: CGFloat = 4
        static let dayTensFontSize: CGFloat = 36
        static let dayOnesFontSize: CGFloat = 56
        static let dayTopGap: CGFloat = 2
        static let weekdayFontSize: CGFloat = 13
        static let weekdayTopGap: CGFloat = 2
        static let weekdayBottomGap: CGFloat = 16
        static let dividerBottomGap: CGFloat = 20
        static let titleFontSize: CGFloat = 22
        static let titleLineSpacing: CGFloat = 4
        static let titleBottomGap: CGFloat = 10
        static let tagFontSize: CGFloat = 11
        static let tagVerticalPadding: CGFloat = 3
    }

    var body: some View {
        let theme = themeManager.current
        return VStack(alignment: .leading, spacing: 0) {
            // 月份小字
            Text(diary.date.monthYearUppercased)
                .font(.system(size: Metrics.monthFontSize, weight: .regular))
                .tracking(3)
                .foregroundColor(theme.textTertiary)
                .padding(.bottom, Metrics.monthBottomGap)

            // 日期数字（前小后大）+ 写完时的心情（2026-10-17 换掉了心情印章，和数字基线对齐，不多占一行）
            HStack(alignment: .lastTextBaseline) {
                // 基线对齐（设计稿 MEMOIR_DETAIL_POLISH.md「十位 36pt + 个位 56pt，底部对齐」）。
                // 之前是 `.top`：小号的「1」顶着大号「6」的上沿，读起来像上标「¹6」。
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text(diary.date.dayTens)
                        .font(.system(size: Metrics.dayTensFontSize, weight: .light, design: .serif))
                    Text(diary.date.dayOnes)
                        .font(.system(size: Metrics.dayOnesFontSize, weight: .light, design: .serif))
                }
                .foregroundColor(theme.textPrimary)
                Spacer()
                if let level = diary.moodLevel {
                    MoodBadge(level: level)
                }
            }
            .padding(.top, Metrics.dayTopGap)

            // 星期
            Text(diary.date.weekdayString)
                .font(.system(size: Metrics.weekdayFontSize))
                .foregroundColor(theme.textSecondary)
                .padding(.top, Metrics.weekdayTopGap)
                .padding(.bottom, Metrics.weekdayBottomGap)

            // 短分割线
            Rectangle()
                .fill(theme.borderAccent)
                .frame(width: 32, height: 1)
                .padding(.bottom, Metrics.dividerBottomGap)

            // 标题（不截断，最多约三行，见 `JournalEntry.titleMaxLength`）
            if !diary.title.isEmpty {
                Text(diary.title)
                    .font(.custom("Georgia", size: Metrics.titleFontSize))
                    .fontWeight(.medium)
                    .foregroundColor(theme.textPrimary)
                    .lineSpacing(Metrics.titleLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Metrics.titleBottomGap)
            }

            // 标签
            if !diary.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(diary.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: Metrics.tagFontSize))
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, Metrics.tagVerticalPadding)
                            .background(theme.accentBackground)
                            .cornerRadius(12)
                    }
                }
            }
        }
    }

    /// 页眉的渲染高度估算，供 `Paginator` 给首页正文留位置。
    /// 按 UIKit 字体度量逐行累加，标题按真实折行测高。偏大无妨（首页底部多点留白），偏小才会挤掉正文。
    static func estimatedHeight(for diary: JournalEntry, width: CGFloat) -> CGFloat {
        var h: CGFloat = 0
        h += UIFont.systemFont(ofSize: Metrics.monthFontSize).lineHeight + Metrics.monthBottomGap

        let dayBase = UIFont.systemFont(ofSize: Metrics.dayOnesFontSize, weight: .light)
        let dayFont = dayBase.fontDescriptor.withDesign(.serif)
            .map { UIFont(descriptor: $0, size: Metrics.dayOnesFontSize) } ?? dayBase
        h += Metrics.dayTopGap + dayFont.lineHeight

        h += Metrics.weekdayTopGap + UIFont.systemFont(ofSize: Metrics.weekdayFontSize).lineHeight
            + Metrics.weekdayBottomGap
        h += 1 + Metrics.dividerBottomGap

        if !diary.title.isEmpty {
            let titleFont = UIFont(name: "Georgia", size: Metrics.titleFontSize)
                ?? .systemFont(ofSize: Metrics.titleFontSize)
            h += TextMeasure.height(of: diary.title, font: titleFont,
                                    lineSpacing: Metrics.titleLineSpacing, width: width)
            h += Metrics.titleBottomGap
        }
        if !diary.tags.isEmpty {
            h += UIFont.systemFont(ofSize: Metrics.tagFontSize).lineHeight + Metrics.tagVerticalPadding * 2
        }
        return ceil(h)
    }
}
