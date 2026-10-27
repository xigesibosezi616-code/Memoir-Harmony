import StoreKit
import SwiftUI

/// 设置页（一级）。
///
/// 2026-09-13 从「一页 771 行、8 个分组、22 个条目全铺开」改成两级结构：
/// 这一页只留**账户卡 + 八个入口**，具体条目进各自的二级页
/// （`SettingsAppearanceView` / `SettingsJournalView` / … ，都在本目录下）。
///
/// 几条刻意为之、改的时候别顺手抹掉：
///
/// 1. 🔴 **账户卡不收进二级页，而且未绑手机号时直接在卡上报警。**
///    手机号是账号的唯一凭据 —— 账号上只有 Apple 登录时，一旦 Apple ID 不可用
///    就再也找不回账号。2026-08-12 的账号分裂事故就是这么来的。
///    把这个警告藏进二级页 = 取消这个警告，用户根本不会点进去才发现。
/// 2. **「语言」不套二级页**，直接进选择页 —— 它本来就只有一件事可做，
///    多一层跳转纯属折磨（尤其对那些正因为语言不对而来找它的用户）。
/// 3. **「写作统计」是内容页不是设置项**，所以单列一行、不塞进「日记」分组里。
///
/// 2026-10-26 照苹果「设置」的样子重排：大标题；账户卡（手写 m. 头像 + 名字 + 一行说明，没绑手机号时卡里多一行红点提醒）；
/// 每行前面是原来的线条图标、套一个细线方框（不填色，用户定）；页面底比卡片深一点，分组看得出来（`SettingsPalette`）；
/// 最后一组「关注我们」。二级、三级页同样用这组页面底 / 卡片色（`ThemeManager.settingsPage` / `settingsCard`），写作统计是内容页除外
struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(LanguageManager.self) private var languageManager
    @Environment(AppEnvironment.self) private var env
    @Environment(StoreKitManager.self) private var store
    @State private var showPaywall = false

    @State private var showLogin = false
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    /// 为 true 时直接推出「应用图标」页 —— 桌面长按图标的快捷操作用（见 `QuickActions.swift`）。
    /// 返回时由 NavigationStack 自动置回 false。
    @Binding var openAppIconPicker: Bool

    /// 显式写出来：这个 struct 里有 `private` 的 `@State`，
    /// 编译器合成的逐成员初始化器会跟着变成 private，外面就调不到了
    init(openAppIconPicker: Binding<Bool>) {
        _openAppIconPicker = openAppIconPicker
    }

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            List {
                accountSection(theme: theme)

                membershipSection(theme: theme)

                Section {
                    entry(.appearance, "外观", theme: theme) { SettingsAppearanceView() }
                    entry(.journal, "日记", theme: theme) { SettingsJournalView() }
                    entry(.penPal, "笔友", theme: theme) { SettingsPenPalView() }
                    entry(.location, "位置与天气", theme: theme) { SettingsLocationView() }
                    // 语言直通选择页，右侧顺带把当前语言显出来
                    NavigationLink {
                        LanguagePickerView()
                    } label: {
                        HStack {
                            groupLabel(.language, "语言", theme: theme)
                            Spacer()
                            Text(currentLanguageDisplay)
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .listRowBackground(card)
                }

                Section {
                    entry(.data, "数据与备份", theme: theme) { SettingsDataView() }
                    entry(.stats, "写作统计", theme: theme) { StatsView() }
                }

                Section {
                    rateRow(theme: theme)
                    actionRow(.feedback, "反馈与建议", theme: theme, action: writeToUs)
                    entry(.about, "关于", theme: theme) { SettingsAboutView() }
                }

                OfficialAccountsSection(theme: theme, themeID: themeID)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(SettingsPalette.page(themeID))
            .tint(theme.accent)
            .sheet(isPresented: $showLogin) {
                LoginView()
            }
            .paywallCover(isPresented: $showPaywall)
            .task {
                // 打开设置页时静默刷新登录态：绑定状态保持最新；token 过期(401)自动登出
                guard let token = env.session.token else { return }
                do {
                    let me = try await env.auth.fetchMe(token: token)
                    env.session.updateUser(me.user)
                } catch {
                    // unauthorized = token 过期；not_found = 账号已不存在（开发期库重建）——都应登出
                    if case AuthError.server(let code, _, _) = error,
                       code == "unauthorized" || code == "not_found" {
                        env.session.clear()
                    }
                    // 其他失败（离线等）静默：本地快照继续可用
                }
            }
            // 不写 `.navigationTitle("设置")`：那样 App 里切语言后大标题不跟着变（见 `LanguageManager.bundle`）
            .navigationTitle(NSLocalizedString("设置", bundle: languageManager.bundle, comment: "设置页大标题"))
            .navigationBarTitleDisplayMode(.large)
            // 快捷操作直达：跳过「外观」这一层，返回一次就回到设置首页
            .navigationDestination(isPresented: $openAppIconPicker) {
                AppIconPickerView()
            }
        }
    }

    // MARK: - 账户卡

    /// 苹果设置最上面那张卡的样子：头像 + 名字 + 一行说明；没绑手机号时卡里多一行带红点的提醒
    @ViewBuilder
    private func accountSection(theme: any AppTheme) -> some View {
        if env.session.isLoggedIn, let user = env.session.user {
            Section {
                NavigationLink {
                    SettingsAccountView()
                } label: {
                    accountLabel(theme: theme,
                                 // 有昵称就以昵称为准 —— 一串脱敏手机号当账号名，用户看不出「这是我」
                                 title: Text(verbatim: user.displayName?.isEmpty == false
                                             ? user.displayName!
                                             : (user.maskedPhone
                                                ?? NSLocalizedString("已登录", bundle: .appLanguage, comment: "账号行兜底标题"))),
                                 subtitle: Text("账号、手机号与登录方式"))
                }
                .listRowBackground(card)

                // 🔴 **未绑手机号的警告必须留在一级页**（见类型注释第 1 条）：卡里一行红点提醒，下面的小字说清楚为什么
                if user.phone == nil {
                    NavigationLink {
                        SettingsAccountView()
                    } label: {
                        HStack {
                            Text("还没有绑定手机号")
                                .font(.body)
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Text(verbatim: "1")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(theme.destructive))
                        }
                    }
                    .listRowBackground(card)
                }
            } footer: {
                if user.phone == nil {
                    Text("未绑定手机号。手机号是账号的唯一凭据，不绑定的话，换手机或 Apple ID 不可用时将无法找回账号。")
                        .foregroundStyle(theme.destructive)
                }
            }
        } else {
            Section {
                Button {
                    showLogin = true
                } label: {
                    HStack {
                        accountLabel(theme: theme, title: Text("登录 / 注册"), subtitle: Text("登录后才能收到笔友的回信"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(card)
            }
        }
    }

    private func accountLabel(theme: any AppTheme, title: Text, subtitle: Text) -> some View {
        HStack(spacing: 14) {
            MarkAvatar(size: 60, themeID: themeID)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 尺素会员

    /// 账户卡正下方单独一组：没开通是「开通」→ 付费页；开通了是有效期 → 会员页。
    /// 图标是一枚压着用户首字的小火漆印（和付费页那枚是同一枚）
    @ViewBuilder
    private func membershipSection(theme: any AppTheme) -> some View {
        Section {
            if store.isMember {
                NavigationLink {
                    MembershipStatusView()
                } label: {
                    membershipLabel(theme: theme) {
                        if let expiresAt = store.expiresAt {
                            Text("有效期至\(expiresAt.formatted(.dateTime.year().month().day().locale(appLocale)))")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                }
                .listRowBackground(card)
            } else {
                Button { showPaywall = true } label: {
                    membershipLabel(theme: theme) {
                        HStack(spacing: 4) {
                            Text("开通")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.accent)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(card)
            }
        }
    }

    private func membershipLabel<Trailing: View>(theme: any AppTheme, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            // 火漆印本身就是这一行的图标，不另放小方块；和下面各行的小方块一样宽，字才对得齐
            WaxSeal(size: 26, mark: WaxSeal.initial(of: env.session.user?.displayName))
                .frame(width: SettingsTile<EmptyView>.size)
            Text("尺素会员")
                .font(.body)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            trailing()
        }
    }

    // MARK: - 分组入口

    private func entry<Destination: View>(
        _ icon: SettingsIcon,
        _ title: LocalizedStringKey,
        theme: any AppTheme,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            groupLabel(icon, title, theme: theme)
        }
        .listRowBackground(card)
    }

    /// 去 App Store 评分。是个动作不是页面，所以右侧是「外跳」箭头而不是 `>`。
    /// App ID 没填时的行为见 `AppStoreLinks.appID`
    @ViewBuilder
    private func rateRow(theme: any AppTheme) -> some View {
        if let url = AppStoreLinks.writeReviewURL {
            rateButton(theme: theme) { openURL(url) }
        } else {
            #if DEBUG
            rateButton(theme: theme) { requestReview() }
            #endif
        }
    }

    private func rateButton(theme: any AppTheme, action: @escaping () -> Void) -> some View {
        actionRow(.rate, "给我们评分", theme: theme, action: action)
    }

    /// 反馈与建议（2026-10-27）：打开手机自己的邮件 App 写到 connect@（`FeedbackMail`）。
    /// 没有能接 mailto 的邮件 App 就把地址复制下来，提示一句 —— 不让用户点了没反应
    private func writeToUs() {
        guard let url = FeedbackMail.url else { return }
        openURL(url) { accepted in
            guard !accepted else { return }
            UIPasteboard.general.string = FeedbackMail.address
            env.errors.present(String(format: NSLocalizedString("邮箱地址已复制：%@", bundle: .appLanguage,
                                                                comment: "反馈与建议：手机上没有邮件 App 时"),
                                      FeedbackMail.address),
                               kind: .success)
        }
    }

    /// 点了是个动作、不是进页面的一行：右侧是「外跳」箭头而不是 `>`（评分、反馈与建议）
    private func actionRow(_ icon: SettingsIcon, _ title: LocalizedStringKey, theme: any AppTheme,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                groupLabel(icon, title, theme: theme)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(card)
    }

    private func groupLabel(_ icon: SettingsIcon, _ title: LocalizedStringKey, theme: any AppTheme) -> some View {
        HStack(spacing: 14) {
            SettingsTile(theme: theme) {
                SettingsIconView(icon: icon, size: 20, color: theme.textSecondary, weight: 1.1)
            }
            Text(title)
                .font(.body)
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var themeID: String { themeManager.currentThemeID }
    /// 一级页的卡片底色（和页面底分得开，见 `SettingsPalette`）
    private var card: Color { SettingsPalette.card(themeID) }

    private var currentLanguageDisplay: String {
        // 没有「跟随系统」这一档 —— 首启就已按系统语言定下一个具体语言
        // 与 LanguageManager.supportedLanguages 保持一致 —— 那边是唯一真源
        LanguageManager.supportedLanguages
            .first { $0.id == languageManager.appLanguage }?
            .displayName ?? languageManager.appLanguage
    }
}
