import SwiftUI

/// 首次启动的隐私告知与同意 —— 小卡片样式，背景是骑士与信鸽。
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
        ZStack(alignment: .bottom) {
            background
            // 🔴 **卡片必须待在下半屏**：背景画里骑士递信给信鸽这个主体
            // 位于画面纵向 0.30~0.50 处，卡片一旦居中就正好把它整个盖住
            // （2026-09-12 截图实测）。留出上半屏，画面才有意义。
            card
                .padding(.bottom, 44)
        }
        .ignoresSafeArea()
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

    // MARK: - 背景

    private var background: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // 底衬：同一张图铺满后重度模糊。
                // 先试过取画面底部平均色（#262517）填纯色，但卡片两侧的窄边
                // 仍能看出一条横向接缝；换成模糊版之后颜色与纹理都是连续的，
                // 接缝彻底消失。这一屏一辈子只出现一次，模糊的开销无所谓。
                Image("ConsentBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .blur(radius: 40)
                    .clipped()

                // 🔴 **按宽度铺满 + 顶部对齐，不要用 `scaledToFill`。**
                //
                // 原图 645×1147（比例 0.562）比屏幕（0.460）「胖」，
                // `scaledToFill` 会左右各裁掉 9% —— 而**骑士正好贴着左边缘**，
                // 一裁就只剩他的手臂，画面就失去意义了（2026-09-12 截图实测）。
                //
                // 改成按宽度铺满：左右一个像素都不裁，代价是底部空出 18%，
                // 而那一块正好被同意卡片盖住，用上面的 `backdrop` 补色即可。
                Image("ConsentBackground")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // 画面本身偏暗，再压一层让白卡片的对比度稳定
            .overlay(Color.black.opacity(0.20))
            .clipped()
        }
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
        .padding(.horizontal, 30)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }
}
