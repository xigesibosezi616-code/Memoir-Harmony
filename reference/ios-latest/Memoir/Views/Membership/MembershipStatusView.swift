import SwiftUI
import StoreKit

/// 设置 →「尺素会员」（已开通时）。方案、有效期、管理订阅、恢复购买。
///
/// 管理订阅（换方案、退订）交给系统的订阅管理页 —— Apple 要求订阅类 App 给出这个入口，
/// 而且退订本来就只能在 Apple 那边做。
struct MembershipStatusView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(StoreKitManager.self) private var store
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var showManage = false
    @State private var restoring = false
    @State private var restoreMessage: String?

    var body: some View {
        let theme = themeManager.current
        SettingsSubpage(title: "尺素会员") {
            Section {
                VStack(spacing: 12) {
                    WaxSeal(size: 60, mark: WaxSeal.initial(of: env.session.user?.displayName))
                    Text("尺素会员")
                        .font(theme.headingFont)
                        .foregroundStyle(theme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                HStack {
                    Text("方案")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text(planName)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }
                .listRowBackground(themeManager.settingsCard)

                if let expiresAt = store.expiresAt {
                    HStack {
                        Text("有效期至")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Text(verbatim: expiresAt.formatted(.dateTime.year().month().day().locale(appLocale)))
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textTertiary)
                    }
                    .listRowBackground(themeManager.settingsCard)
                }
            }

            Section {
                Button { showManage = true } label: {
                    Text("管理订阅")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                }
                .listRowBackground(themeManager.settingsCard)

                Button {
                    Task { await restore() }
                } label: {
                    HStack {
                        Text("恢复购买")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        if restoring { ProgressView() }
                    }
                }
                .disabled(restoring)
                .listRowBackground(themeManager.settingsCard)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let restoreMessage {
                        Text(verbatim: restoreMessage)
                    }
                    Text("换方案、退订都在「管理订阅」里。退订后，已经用上的相纸和封面会保持原样。")
                }
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
            }

            // 测试期的假会员可以关掉，回到免费版测试（见 `StoreKitManager.testUnlock`）
            if store.isTestMember {
                Section {
                    Button {
                        Task {
                            await store.testDeactivate()
                            // 已经不是会员了，这一页没有可看的，退回设置
                            dismiss()
                        }
                    } label: {
                        Text("关闭测试会员")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.destructive)
                    }
                    .listRowBackground(themeManager.settingsCard)
                } footer: {
                    Text("测试期间开通不收费，关掉后回到免费版。")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
        .manageSubscriptionsSheet(isPresented: $showManage)
    }

    private var planName: LocalizedStringKey {
        store.activeProductID == StoreKitManager.monthlyID ? "月付" : "年付"
    }

    private func restore() async {
        restoring = true
        defer { restoring = false }
        do {
            try await store.restore()
            restoreMessage = NSLocalizedString("已与 App Store 同步", bundle: .appLanguage, comment: "会员页：恢复购买完成")
        } catch {
            let ns = error as NSError
            NSLog("❌ [Membership] 恢复购买失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            restoreMessage = NSLocalizedString("没能恢复购买，请稍后再试", bundle: .appLanguage, comment: "付费页：恢复购买失败")
        }
    }
}
