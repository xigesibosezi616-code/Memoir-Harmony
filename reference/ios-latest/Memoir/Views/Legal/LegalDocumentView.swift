import SwiftUI

/// 隐私政策 / 用户协议的阅读页。
///
/// 内容来自 bundle 里的 md（见 `LegalDocument`），**不联网** ——
/// 审核时网络不通也一定打得开。
struct LegalDocumentView: View {
    let document: LegalDocument

    @Environment(ThemeManager.self) private var themeManager
    @Environment(LanguageManager.self) private var languageManager

    /// 解析结果按「文档 + 语言」缓存。正文数千字，
    /// 每次 body 求值都重新解析会在滚动时掉帧。
    @State private var blocks: [LegalMarkdown.Block] = []

    var body: some View {
        let theme = themeManager.current
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(blocks) { block in
                    switch block {
                    case .title(let text):
                        Text(text)
                            .font(theme.titleFont)
                            .foregroundStyle(theme.textPrimary)
                            .padding(.bottom, 10)

                    case .heading(let text):
                        Text(text)
                            .font(theme.headingFont)
                            .foregroundStyle(theme.textPrimary)
                            .padding(.top, 22)
                            .padding(.bottom, 8)

                    case .subheading(let text):
                        Text(text)
                            .font(theme.bodyFont)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.textPrimary)
                            .padding(.top, 14)
                            .padding(.bottom, 6)

                    case .paragraph(let text):
                        Text(text)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textSecondary)
                            .lineSpacing(5)
                            .padding(.bottom, 12)

                    case .bullet(let text):
                        HStack(alignment: .top, spacing: 8) {
                            // 用圆点而不是 md 原文的「-」：法律文档里连字符
                            // 容易和正文里的连接号混淆
                            Text("•")
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.textTertiary)
                            Text(text)
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.textSecondary)
                                .lineSpacing(5)
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(theme.background)
        .navigationTitle(document.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: languageManager.appLanguage) {
            blocks = LegalMarkdown.parse(
                document.loadMarkdown(language: languageManager.appLanguage)
            )
        }
    }
}
