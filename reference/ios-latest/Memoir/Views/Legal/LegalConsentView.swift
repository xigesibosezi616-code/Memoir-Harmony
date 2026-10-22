import SwiftUI

/// 首次启动的隐私告知与同意 —— 主题底色上一张居中的小卡片。
///
/// 2026-10-17 产品定：去掉原来骑士递信给信鸽的背景画（`ConsentBackground` 已删），只留纯色底。
///
/// **为什么必须有**：《个人信息保护法》要求在处理个人信息前以显著方式告知并取得同意；
/// 国内应用商店与 iOS 中国区审核都会实际检查这一步。在用户点「同意并继续」之前，
/// 尺素不发起任何网络请求、不申请任何系统权限。
///
/// **为什么「暂不使用」不退出 App**：程序化退出（`exit(0)`）违反 App Store 审核指南，
/// 会被拒。这里的做法是**停在这一屏**——不同意就过不去，效果等同于无法使用，
/// 但没有自杀式退出。
struct LegalConsentView: View {
    /// 用户点了同意，把版本号写进去
    let onAccept: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @State private var showingDeclineAlert = false
    @State private var presentedDocument: LegalDocument?

    var body: some View {
        ZStack {
            // 刚装好时是素笺的米白；老用户因协议改版重新同意时是他自己的主题色
            themeManager.current.background
                .ignoresSafeArea()
            card
        }
        // 协议全文必须在同意**之前**就能读到 ——「先同意才能看」不合规。
        // 这里用 sheet 而不是 navigationDestination：卡片本身不在导航栈里
        .sheet(item: $presentedDocument) { doc in
            NavigationStack {
                LegalDocumentView(document: doc)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("关闭") { presentedDocument = nil }
                        }
                    }
            }
            .environment(themeManager)
        }
        .alert("需要您的同意才能继续", isPresented: $showingDeclineAlert) {
            Button("再看看", role: .cancel) {}
        } message: {
            Text("尺素需要保存您的手机号以便登录，也需要在您求信时把日记文字送去生成回信。不同意的话，这些功能都无法提供，很抱歉。")
        }
        .interactiveDismissDisabled(true)
    }

    private func documentLink(_ doc: LegalDocument, _ label: LocalizedStringKey) -> some View {
        Button {
            presentedDocument = doc
        } label: {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.25))
                .underline()
                .lineLimit(1)
        }
    }

    // MARK: - 卡片

    private var card: some View {
        VStack(spacing: 0) {
            Text("用户隐私协议")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color(white: 0.10))
                .padding(.top, 26)
                .padding(.bottom, 16)

            // 正文可滚动。**不要改成固定高度的 Text** —— 七种语言里
            // 德法西的行长差异很大，写死高度必然有语言被截断
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("欢迎使用尺素。在开始之前，请您阅读并同意《隐私政策》与《用户协议》。")
                    Text("**您写下的日记正文、照片与录音不会上传到我们的服务器。** 它们保存在您的设备上，并通过您本人的 iCloud 在您的设备之间同步，我们无法访问也无法读取。")
                    Text("只有在您**主动向笔友求信**时，被选中那几篇日记的文字才会经由我们的服务器送去生成回信，且我们不会保存这些内容。")
                    Text("登录需要您的手机号；获取天气需要位置权限。这些都可以随时在设置中关闭。")
                    Text("点击「同意并继续」，即表示您已充分理解并同意上述两份协议的全部内容。")
                }
                .font(.system(size: 14))
                .foregroundStyle(Color(white: 0.32))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.bottom, 14)
            }
            .frame(maxHeight: 230)

            // 一行放不下就自动改成上下两行 —— 法语的
            // 「« Politique de confidentialité »」一个词就顶掉半行，
            // 硬排一行会折行并和另一个链接叠在一起（2026-09-12 法语实测）
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    documentLink(.privacy, "《隐私政策》")
                    documentLink(.terms, "《用户协议》")
                }
                VStack(spacing: 7) {
                    documentLink(.privacy, "《隐私政策》")
                    documentLink(.terms, "《用户协议》")
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)

            HStack(spacing: 12) {
                Button {
                    showingDeclineAlert = true
                } label: {
                    Text("暂不使用")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.12))
                        // 七种语言里法语、西语最长（"Accepter et continuer"），
                        // 不夹这两句会折行，按钮高度当场乱掉
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color(white: 0.12), lineWidth: 1)
                        )
                }

                Button {
                    onAccept()
                } label: {
                    Text("同意并继续")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .background(Color(white: 0.99), in: RoundedRectangle(cornerRadius: 4))
        // 浅色底上白卡片：一圈极细的边 + 很淡的影子就托得住（原来那层重影子是为了压在暗色的画上）
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        .padding(.horizontal, 30)
        .shadow(color: .black.opacity(0.10), radius: 20, y: 6)
    }
}
