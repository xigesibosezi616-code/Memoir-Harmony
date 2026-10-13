import SwiftUI

/// 翻页阅读容器：包 `PageCurlReaderView` + 悬浮返回按钮。
/// 通过 `.fullScreenCover` 从 `BookDetailView` 打开 —— **三个主题都能用**。
///
/// > 2026-08-12 之前只有和纸能进来，因为整个阅读器写死了和纸的配色（24 处硬编码色值）。
/// > 现在全部接进 `ThemeManager`，纸张与文字跟随当前主题。
struct DiaryReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @StateObject private var dataSource: PageDataSource

    init(initialDiary: JournalEntry, entries: [JournalEntry]) {
        _dataSource = StateObject(wrappedValue: PageDataSource(
            entries: entries,
            initialDiary: initialDiary
        ))
    }

    var body: some View {
        let theme = themeManager.current
        return ZStack(alignment: .topLeading) {
            // 翻页主体
            PageCurlReaderView(dataSource: dataSource, themeManager: themeManager)
                .ignoresSafeArea()

            // 悬浮返回按钮
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(theme.accentBackground.opacity(0.92))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
            }
            // 贴着安全区顶部放，占的是系统导航栏那一条（安全区下 8–44pt）。
            // 页面内容从安全区下 56pt 开始（`ReaderLayout.topInset`），两者互不重叠。
            //
            // ⚠️ 之前是 `.padding(.top, 50)`：按钮落在安全区下 50–86pt，
            // 正好压住首页的「2026年9月」—— 左边三个字符被圆形底盖掉，
            // 只剩「6 年 9 月」，看起来像日期算错了（2026-09-16 实机反馈）。
            .padding(.top, 8)
            .padding(.leading, 16)
        }
        .navigationBarHidden(true)
    }
}
