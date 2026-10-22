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
                    .listRowBackground(theme.cardBackground)
                }

                Section {
                    entry(.data, "数据与备份", theme: theme) { SettingsDataView() }
                    entry(.stats, "写作统计", theme: theme) { StatsView() }
                }

                Section {
                    rateRow(theme: theme)
                    entry(.about, "关于", theme: theme) { SettingsAboutView() }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.background)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("设置")
                        .font(theme.labelFont)
                        .tracking(theme.letterSpacingWide)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            // 快捷操作直达：跳过「外观」这一层，返回一次就回到设置首页
            .navigationDestination(isPresented: $openAppIconPicker) {
                AppIconPickerView()
            }
        }
    }

    // MARK: - 账户卡

    @ViewBuilder
    private func accountSection(theme: any AppTheme) -> some View {
        Section {
            if env.session.isLoggedIn, let user = env.session.user {
                NavigationLink {
                    SettingsAccountView()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(theme.textSecondary)
                        VStack(alignment: .leading, spacing: 3) {
                            // 有昵称就以昵称为准 —— 一串脱敏手机号当账号名，用户看不出「这是我」
                            Text(user.displayName?.isEmpty == false
                                 ? user.displayName!
                                 : (user.maskedPhone
                                    ?? NSLocalizedString("已登录", bundle: .appLanguage, comment: "账号行兜底标题")))
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.textPrimary)
                            if user.displayName?.isEmpty == false, let phone = user.maskedPhone {
                                Text(phone)
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(theme.cardBackground)

                // 🔴 **未绑手机号的警告必须留在一级页**（见类型注释第 1 条）
                if user.phone == nil {
                    Text("未绑定手机号。手机号是账号的唯一凭据，不绑定的话，换手机或 Apple ID 不可用时将无法找回账号。")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.destructive)
                        .listRowBackground(theme.cardBackground)
                }
            } else {
                Button {
                    showLogin = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(theme.textSecondary)
                        Text("登录 / 注册")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(theme.cardBackground)
            }
        }
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
                .listRowBackground(theme.cardBackground)
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
                .listRowBackground(theme.cardBackground)
            }
        }
    }

    private func membershipLabel<Trailing: View>(theme: any AppTheme, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            WaxSeal(size: 24, mark: WaxSeal.initial(of: env.session.user?.displayName))
                .frame(width: 26)
            Text("尺素会员")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.vertical, 2)
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
        .listRowBackground(theme.cardBackground)
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
        Button(action: action) {
            HStack {
                groupLabel(.rate, "给我们评分", theme: theme)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(theme.cardBackground)
    }

    private func groupLabel(_ icon: SettingsIcon, _ title: LocalizedStringKey, theme: any AppTheme) -> some View {
        HStack(spacing: 12) {
            SettingsIconView(icon: icon, size: 22, color: theme.textSecondary)
                .frame(width: 26)
            Text(title)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.vertical, 2)
    }

    private var currentLanguageDisplay: String {
        // 没有「跟随系统」这一档 —— 首启就已按系统语言定下一个具体语言
        // 与 LanguageManager.supportedLanguages 保持一致 —— 那边是唯一真源
        LanguageManager.supportedLanguages
            .first { $0.id == languageManager.appLanguage }?
            .displayName ?? languageManager.appLanguage
    }
}
