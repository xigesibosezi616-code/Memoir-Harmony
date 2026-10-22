import SwiftUI

/// 正文页：每篇日记的第 0 页顶部是页眉（日期 + 标题 + 标签），续页顶部是一行小标题；
/// 下面是这一页的正文块，末页附录音，底部页码。
///
/// ⚠️ 版式尺寸与 `Paginator` 共用 `ReaderLayout` —— 分页按同一套数字估算每页装多少，
/// 这里改了间距而那边没跟上，正文就会被截断。
struct ContentPageView: View {
    let diary: JournalEntry
    let pageIndex: Int
    let totalPages: Int
    let blocks: [ContentBlock]
    /// ⚠️ 靠 `PageContentViewController` 手工注入，见该文件注释
    @Environment(ThemeManager.self) private var themeManager

    private var isFirstPageOfDiary: Bool {
        pageIndex == 0
    }
    private var isLastPageOfDiary: Bool {
        pageIndex + 1 == totalPages
    }

    var body: some View {
        let theme = themeManager.current
        return ZStack {
            ZStack {
                theme.background
                Image("Texture_Paper")
                    .resizable()
                    .opacity(0.15)
                    .blendMode(.multiply)
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                if isFirstPageOfDiary {
                    // 首页：页眉，正文紧跟其后
                    DiaryPageHeader(diary: diary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, ReaderLayout.headerBottomGap)
                } else {
                    // 续页：顶部小标题（居中，避开左上角返回按钮）
                    Text(diary.title.isEmpty ? " " : diary.title)
                        .font(.system(size: ReaderLayout.runningTitleFontSize))
                        .foregroundColor(theme.textTertiary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, ReaderLayout.runningTitleBottomGap)
                }

                // 正文 + 末页录音
                VStack(alignment: .leading, spacing: ReaderLayout.blockSpacing) {
                    ContentBlockRenderer(
                        blocks: blocks,
                        theme: BambooTheme(),
                        availableWidth: Paginator.shared.contentWidth,
                        fullTextFont: .custom("Georgia", size: ReaderLayout.bodyFontSize),
                        fullLineSpacing: ReaderLayout.bodyLineSpacing,
                        fullTextColor: theme.textPrimary,
                        headingFont: .custom("Georgia-Bold", size: ReaderLayout.headingFontSize),
                        highlightColor: RichTextAppearance.forTheme(id: themeManager.currentThemeID, theme: theme).highlightColor,
                        writtenDate: diary.createdAt,
                        laterInkColor: RichTextAppearance.forTheme(id: themeManager.currentThemeID, theme: theme).laterInkColor
                    )

                    // 末页才出现录音（避免每页重复）
                    // 正文里有位置的录音跟着正文走；这里只放没有位置的（老日记的录音）
                    if isLastPageOfDiary, !diary.looseAudioURLs.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(Array(diary.looseAudioURLs.enumerated()), id: \.offset) { _, url in
                                AudioPlayerCard(audioURL: url)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, ReaderLayout.bodyTopGap)

                // 底部页码
                Text("\(pageIndex + 1) / \(totalPages)")
                    .font(.custom("Georgia", size: ReaderLayout.pageNumberFontSize))
                    .foregroundColor(theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, ReaderLayout.pageNumberTopGap)
            }
            .padding(.horizontal, ReaderLayout.hInset)
            .padding(.top, ReaderLayout.topInset)
            .padding(.bottom, ReaderLayout.bottomInset)
        }
    }
}
