import SwiftUI

/// 导出页「怎么打印这本日记」的小弹窗（2026-10-23 用户提：导出来的 PDF 是什么规格、该怎么印，连开发者自己都不清楚）。
///
/// 四句话说清：这是 A5、为双面左边装订排的；在家用 A5 或 A4 纸怎么印；不能双面也行；想印成真正的书怎么跟打印店说。
/// 导出页主按钮下面的小链接随时能打开；第一次导出完成时自动弹一次
struct BookPrintTipsView: View {
    let theme: any AppTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("怎么打印这本日记")
                .font(theme.headingFont)
                .foregroundStyle(theme.textPrimary)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    row("doc.text", "这本日记是 A5（148 × 210 毫米）大小。左右留白一宽一窄，宽的一边留给装订。")
                    row("printer", "在家打印：有 A5 纸就选 A5、双面（长边翻页）。只有 A4 纸也行，A4 和 A5 比例一样，整页会等比放大。")
                    row("doc.on.doc", "打印机不能双面也没关系，单面印出来一样能装订。")
                    row("books.vertical", "想做成一本真正的书：把 PDF 发给打印店或网上印书，说「A5、双面、装订成册」。第一页是封面，最后一页是封底。")
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            Button { dismiss() } label: {
                Text("知道了")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.cardBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.background)
    }

    private func row(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(theme.accent)
                .frame(width: 22)
                .padding(.top, 1)
            Text(text)
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
