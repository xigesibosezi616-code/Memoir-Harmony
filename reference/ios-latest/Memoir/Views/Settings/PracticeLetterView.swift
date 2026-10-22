import SwiftUI

/// 测试包：练习拆信（设置 → 关于 → TEST BUILD，2026-10-21 加）。
///
/// 一封封着的火漆信，拆法和信箱里一模一样（`SealedLetterOpener`：轻点 / 上滑 / 捏住封舌掀），拆完摊成信纸；
/// 点「Seal another」再封上一封，接着拆。**不碰真信**：不读、不写库、不调接口 —— 测拆信的手感，不用真寄一封再等回信。
/// 和「练习投信」一样只在测试包里有入口（`LetterDelivery.isTestBuild`），App Store 版看不到
struct PracticeLetterView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @AppStorage("penPalName") private var penPalName: String = "青鸟"

    @State private var sealed = true
    /// 每再封一封就加一：拆信那一页整个换新的，从火漆完好开始
    @State private var round = 0

    var body: some View {
        let theme = themeManager.current
        let palette = LetterPalette.of(themeID: themeManager.currentThemeID)
        Group {
            if sealed {
                SealedLetterOpener(
                    palette: palette,
                    sealMark: WaxSeal.initial(of: penPalName),
                    sender: Text("来自\(penPalName)"),
                    onFinished: {
                        withAnimation(.easeInOut(duration: LetterOpeningFeel.unfoldDuration)) { sealed = false }
                    }
                )
                .id(round)
                .transition(.opacity.combined(with: .offset(y: 30)))
            } else {
                ScrollView {
                    VStack(spacing: 28) {
                        LetterStationery(
                            palette: palette,
                            date: Date.now.dayAndWeekday,
                            salutation: salutation,
                            content: "Practice letter. Nothing was read, written or sent."
                        )
                        Button {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                round += 1
                                sealed = true
                            }
                        } label: {
                            Text(verbatim: "Seal another")
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                                .overlay(Capsule().stroke(theme.accent.opacity(0.5), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 60)
                }
                .transition(.opacity.combined(with: .offset(y: 16)))
            }
        }
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("来信")
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    /// 抬头和真信一样：「致{昵称}」，没登录 / 没昵称就光秃秃的「致」
    private var salutation: Text {
        if let name = env.session.user?.displayName, !name.isEmpty {
            Text("致\(name)")
        } else {
            Text("致")
        }
    }
}
