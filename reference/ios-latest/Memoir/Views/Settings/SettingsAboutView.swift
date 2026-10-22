import SwiftUI

/// 设置 →「关于」二级页。
struct SettingsAboutView: View {
    /// 测试用：回信加速到达（见 `LetterDelivery.debugTimeScale`）。
    /// **常驻测试包（Debug、TestFlight），App Store 版里看不到**，不是临时钩子 —— 测邮筒时要用，3 天等不起。
    /// 默认开（和 `LetterDelivery.debugFastDeliveryOn` 一致）
    @AppStorage(LetterDelivery.debugFastDeliveryKey) private var debugFastDelivery = true
    /// 测试用：练习投信，只放动画不寄（见 `LetterDelivery.practicePosting`）。同样只在测试包里有，默认关
    @AppStorage(LetterDelivery.practicePostingKey) private var practicePosting = false
    /// 是不是测试包。TestFlight 要运行时问 StoreKit，进页面再问（`LetterDelivery.detectTestBuild`）
    @State private var isTestBuild = LetterDelivery.isTestBuild
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        SettingsSubpage(title: "关于") {
            Section {
                // 🔴 **这两行必须是真能点开的**（上架清单 A6）。
                // 2026-09-10 之前「隐私政策」是个光秃秃的行 ——
                // 没有 Button、没有 NavigationLink，**点了没有任何反应**，
                // 而「用户协议」整行都不存在。审核必查，链接打不开直接拒。
                //
                // 正文走 bundle 里的 md、不联网：网络不通也一定打得开。
                NavigationLink {
                    LegalDocumentView(document: .privacy)
                } label: {
                    SettingsRow(icon: "lock.shield", title: "隐私政策", theme: theme)
                }
                .listRowBackground(theme.cardBackground)

                NavigationLink {
                    LegalDocumentView(document: .terms)
                } label: {
                    SettingsRow(icon: "doc.text", title: "用户协议", theme: theme)
                }
                .listRowBackground(theme.cardBackground)

                HStack {
                    SettingsRow(icon: "info.circle", title: "版本", theme: theme)
                    Spacer()
                    Text(appVersion)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }
                .listRowBackground(theme.cardBackground)
            } footer: {
                // 国内合规硬性要求：App 内必须可见 ICP 备案号与主办单位。
                // 放在 footer 而不是单开一行 —— 这是给监管看的，不是给用户点的。
                VStack(alignment: .leading, spacing: 3) {
                    Text(ComplianceInfo.icpLicense)
                    Text(ComplianceInfo.companyName)
                }
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
            }

            if isTestBuild {
                Section {
                    Toggle(isOn: $debugFastDelivery) {
                        Text(verbatim: "Fast letter delivery")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                    }
                    .tint(theme.accent)
                    .listRowBackground(theme.cardBackground)
                } header: {
                    Text(verbatim: "TEST BUILD")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                } footer: {
                    Text(verbatim: "1 min ≈ 1 day: replies arrive 5 s – 5 min after sending, depending on distance. On by default. Only affects letters sent while on. Debug and TestFlight builds only.")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                }

                Section {
                    Toggle(isOn: $practicePosting) {
                        Text(verbatim: "Practice posting")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                    }
                    .tint(theme.accent)
                    .listRowBackground(theme.cardBackground)

                    NavigationLink {
                        PracticeLetterView()
                    } label: {
                        Text(verbatim: "Practice opening")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                    }
                    .listRowBackground(theme.cardBackground)
                } footer: {
                    Text(verbatim: "Practice posting: push the stack into the slot as often as you like. Plays the animation, sound and haptics only; no letter is written, nothing is sent, the stack stays. Practice opening: a sealed letter to open again and again; nothing is read or sent. Debug and TestFlight builds only.")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                }
            }

            Section {
                EmptyView()
            } footer: {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Memoir")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textTertiary)
                        Text("by Sinara")
                            .font(theme.labelFont)
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
        // TestFlight 包要运行时才分得出来，进页面问一次
        .task { isTestBuild = await LetterDelivery.detectTestBuild() }
    }

    /// 版本号从 bundle 读，别写死 —— 写死的那个迟早和实际发布版本对不上
    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
