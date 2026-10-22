import SwiftUI

/// 末页：装饰短线 + "已读完所有日记" + 底部"再向左翻无更多内容"提示。
struct EndingPageView: View {
    let diary: JournalEntry
    let hasNextDiary: Bool
    /// ⚠️ 靠 `PageContentViewController` 手工注入，见该文件注释
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        return ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Rectangle()
                    .fill(theme.borderAccent)
                    .frame(width: 40, height: 1)

                Text("已读完所有日记")
                    .font(.custom("Georgia", size: 16))
                    .foregroundColor(theme.textSecondary)

                Rectangle()
                    .fill(theme.borderAccent)
                    .frame(width: 40, height: 1)

                Spacer()

                Text("再向右翻无更多内容")
                    .font(.system(size: 10))
                    .foregroundColor(theme.textTertiary)
                    .padding(.bottom, 30)
            }
        }
    }
}
