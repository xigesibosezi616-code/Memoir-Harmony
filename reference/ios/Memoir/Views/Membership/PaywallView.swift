import SwiftUI
import StoreKit

/// 尺素会员的付费页（规则见 `Memoir/Docs/MEMBERSHIP.md`）。
///
/// 调性是**一封邀请函**，不是促销页：顶上一枚火漆印，中间一张纸写清会员有什么，
/// 年付默认选中，续费规则写在按钮下面（Apple 的硬性要求），最后一句「不开通也没关系」。
///
/// 只在心动的时刻出现（收到一封信、在相纸选择器里看到更美的那张），**绝不打断写作**。
struct PaywallView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(StoreKitManager.self) private var store
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID = StoreKitManager.yearlyID
    @State private var busy = false
    @State private var inlineError: String?
    @State private var legalDocument: LegalDocument?

    var body: some View {
        let theme = themeManager.current
        ScrollView {
            VStack(spacing: 0) {
                WaxSeal(size: 68, mark: WaxSeal.initial(of: sealName))
                    .padding(.top, 28)

                Text("尺素会员")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                    .padding(.top, 18)
                Text("让每一篇，都有回音")
                    .font(theme.captionFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 6)

                benefits(theme: theme)
                    .padding(.top, 26)

                plans(theme: theme)
                    .padding(.top, 22)

                purchaseButton(theme: theme)
                    .padding(.top, 18)

                if let inlineError {
                    Text(verbatim: inlineError)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                }

                renewalNote(theme: theme)
                    .padding(.top, 12)

                links(theme: theme)
                    .padding(.top, 14)

                Text("不开通也没关系：写日记、同步和备份永远免费。")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 22)
                    .padding(.bottom, 36)
            }
            .padding(.horizontal, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(theme.surfaceBackground, in: Circle())
            }
            .padding(.leading, 16)
            .padding(.top, 12)
            .disabled(busy)
        }
        .interactiveDismissDisabled(busy)
        // 全屏弹出的页面不继承根视图的深色设置：不补这句，皮革主题下状态栏是深字压深底（实测）
        .preferredColorScheme(theme.preferredColorScheme)
        .sheet(item: $legalDocument) { document in
            NavigationStack { LegalDocumentView(document: document) }
        }
    }

    /// 火漆印上压谁的名字：笔友回信时称呼用户的那个昵称
    private var sealName: String? {
        return env.session.user?.displayName
    }

    // MARK: - 会员有什么

    private func benefits(theme: any AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            benefit(theme: theme, icon: "envelope.open", title: "写一篇，回一篇",
                    detail: "免费是每周一封；会员的每篇日记，笔友都会回信")
            benefit(theme: theme, icon: "seal", title: "火漆封口的信",
                    detail: "每封信装进火漆封口的信封，拆开是讲究的信纸")
            benefit(theme: theme, icon: "person.2", title: "挑一位合你心意的笔友",
                    detail: "温柔的、话少的、爱引诗的……笔友的性格由你选")
            benefit(theme: theme, icon: "calendar", title: "月度与年度回望",
                    detail: "每月一封「这个月的你」，年底一份「这一年」")
            benefit(theme: theme, icon: "photo.on.rectangle", title: "全部相纸与封面版式",
                    detail: "六种相纸、三种日记本封面版式，全部可用")
            benefit(theme: theme, icon: "book.closed", title: "印成一本书",
                    detail: "把一本日记本导出成精装 PDF，可以拿去打印")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.border, lineWidth: 0.5))
    }

    private func benefit(theme: any AppTheme, icon: String, title: LocalizedStringKey,
                         detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(theme.accent)
                .frame(width: 24)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(detail)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 方案

    private struct Plan: Identifiable {
        let id: String
        let name: LocalizedStringKey
        /// 大字价格（「首年 ¥58」「¥12 / 月」）
        let headline: String
        /// 小字说明（「之后每年 ¥88 · 约每月 4.8 元」）
        let detail: String?
        let badge: LocalizedStringKey?
        /// 按钮下的续费说明（只写价格和周期，不写「约每月」这类促销口径）
        let renewal: String
    }

    /// 年付在前。有首年优惠时按优惠价写，没有就按原价
    private var plansToShow: [Plan] {
        if let yearly = store.products.first(where: { $0.id == StoreKitManager.yearlyID }),
           let monthly = store.products.first(where: { $0.id == StoreKitManager.monthlyID }) {
            return [yearlyPlan(regular: yearly.displayPrice, intro: introPrice(of: yearly), perMonth: perMonth(of: yearly)),
                    monthlyPlan(price: monthly.displayPrice)]
        }
        // 测试期（`StoreKitManager.testUnlock`）：App Store Connect 还没建商品，用预设价格把页面画出来
        if StoreKitManager.testUnlock {
            return [yearlyPlan(regular: "¥88", intro: store.isEligibleForIntroOffer ? "¥58" : nil,
                               perMonth: store.isEligibleForIntroOffer ? "¥4.8" : "¥7.3"),
                    monthlyPlan(price: "¥12")]
        }
        return []
    }

    private func yearlyPlan(regular: String, intro: String?, perMonth: String) -> Plan {
        if let intro {
            return Plan(
                id: StoreKitManager.yearlyID,
                name: "年付",
                headline: String(format: NSLocalizedString("首年 %@", bundle: .appLanguage, comment: "付费页：年付首年优惠价"), intro),
                detail: String(format: NSLocalizedString("之后每年 %1$@ · 约每月 %2$@", bundle: .appLanguage, comment: "付费页：年付续费价与折合月价"), regular, perMonth),
                badge: "首年优惠",
                renewal: String(format: NSLocalizedString("首年 %1$@，之后每年 %2$@。到期前 24 小时内自动续费，可随时在系统设置的 Apple 账户 → 订阅中取消。", bundle: .appLanguage, comment: "付费页续费说明：%1$@ 首年价，%2$@ 续费年价"), intro, regular)
            )
        }
        return Plan(
            id: StoreKitManager.yearlyID,
            name: "年付",
            headline: String(format: NSLocalizedString("%@ / 年", bundle: .appLanguage, comment: "付费页：年付价格"), regular),
            detail: String(format: NSLocalizedString("约每月 %@", bundle: .appLanguage, comment: "付费页：年付折合月价"), perMonth),
            badge: nil,
            renewal: String(format: NSLocalizedString("每年 %@。到期前 24 小时内自动续费，可随时在系统设置的 Apple 账户 → 订阅中取消。", bundle: .appLanguage, comment: "付费页续费说明：%@ 年价"), regular)
        )
    }

    private func monthlyPlan(price: String) -> Plan {
        Plan(
            id: StoreKitManager.monthlyID,
            name: "月付",
            headline: String(format: NSLocalizedString("%@ / 月", bundle: .appLanguage, comment: "付费页：月付价格"), price),
            detail: nil,
            badge: nil,
            renewal: String(format: NSLocalizedString("每月 %@。到期前 24 小时内自动续费，可随时在系统设置的 Apple 账户 → 订阅中取消。", bundle: .appLanguage, comment: "付费页续费说明：%@ 月价"), price)
        )
    }

    /// 首年优惠价（还有资格时）
    private func introPrice(of product: Product) -> String? {
        guard store.isEligibleForIntroOffer, let offer = product.subscription?.introductoryOffer else { return nil }
        return offer.displayPrice
    }

    /// 折合每月多少钱：有首年优惠按优惠价算
    private func perMonth(of product: Product) -> String {
        let yearly = (store.isEligibleForIntroOffer ? product.subscription?.introductoryOffer?.price : nil) ?? product.price
        return (yearly / 12).formatted(product.priceFormatStyle.precision(.fractionLength(1)))
    }

    @ViewBuilder
    private func plans(theme: any AppTheme) -> some View {
        let plans = plansToShow
        if plans.isEmpty {
            Text("暂时无法连接 App Store，请稍后再试")
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
                .padding(.vertical, 18)
        } else {
            VStack(spacing: 10) {
                ForEach(plans) { plan in
                    planCard(plan, theme: theme)
                }
            }
        }
    }

    private func planCard(_ plan: Plan, theme: any AppTheme) -> some View {
        let selected = plan.id == selectedID
        return Button {
            withAnimation(.smooth(duration: 0.2)) { selectedID = plan.id }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? theme.accent : theme.textTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.name)
                            .font(theme.bodyFont.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        if let badge = plan.badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.background)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(theme.accent, in: Capsule())
                        }
                    }
                    if let detail = plan.detail {
                        Text(verbatim: detail)
                            .font(theme.labelFont)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                Text(verbatim: plan.headline)
                    .font(theme.headingFont)
                    .foregroundStyle(theme.textPrimary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? theme.accent : theme.border, lineWidth: selected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: - 购买

    private func purchaseButton(theme: any AppTheme) -> some View {
        let canBuy = !plansToShow.isEmpty && !busy
        return Button {
            Task { await purchase() }
        } label: {
            ZStack {
                Text("开通尺素会员")
                    .font(theme.bodyFont.weight(.semibold))
                    .opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(theme.background) }
            }
            .foregroundStyle(theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(canBuy ? theme.accent : theme.textTertiary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!canBuy)
    }

    /// 续费规则。Apple 要求在购买按钮附近写清楚价格、周期、自动续费和怎么取消
    @ViewBuilder
    private func renewalNote(theme: any AppTheme) -> some View {
        if let plan = plansToShow.first(where: { $0.id == selectedID }) {
            Text(verbatim: plan.renewal)
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func links(theme: any AppTheme) -> some View {
        HStack(spacing: 14) {
            Button("恢复购买") { Task { await restore() } }
            Text(verbatim: "·").foregroundStyle(theme.textTertiary)
            Button("用户协议") { legalDocument = .terms }
            Text(verbatim: "·").foregroundStyle(theme.textTertiary)
            Button("隐私政策") { legalDocument = .privacy }
        }
        .font(theme.labelFont)
        .foregroundStyle(theme.textSecondary)
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func purchase() async {
        // 测试期：不走付款，直接开通（见 `StoreKitManager.testUnlock`）
        if StoreKitManager.testUnlock {
            await store.testActivate()
            finishWithSuccess()
            return
        }
        guard let product = store.products.first(where: { $0.id == selectedID }) else { return }
        inlineError = nil
        busy = true
        defer { busy = false }
        do {
            switch try await store.purchase(product) {
            case .purchased:
                finishWithSuccess()
            case .pending:
                inlineError = NSLocalizedString("已提交，等待批准后会员会自动生效", bundle: .appLanguage, comment: "付费页：购买等待批准（家长批准等）")
            case .cancelled:
                break
            }
        } catch {
            let ns = error as NSError
            NSLog("❌ [Paywall] 购买失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            inlineError = NSLocalizedString("没能完成购买，请稍后再试", bundle: .appLanguage, comment: "付费页：购买失败")
        }
    }

    private func restore() async {
        inlineError = nil
        busy = true
        defer { busy = false }
        do {
            try await store.restore()
            if store.isMember {
                finishWithSuccess()
            } else {
                inlineError = NSLocalizedString("这个 Apple 账户下没有找到尺素会员", bundle: .appLanguage, comment: "付费页：恢复购买没找到")
            }
        } catch {
            let ns = error as NSError
            NSLog("❌ [Paywall] 恢复购买失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            inlineError = NSLocalizedString("没能恢复购买，请稍后再试", bundle: .appLanguage, comment: "付费页：恢复购买失败")
        }
    }

    /// 开通成功：关掉付费页（成功后的「眼前一亮」由各功能自己呈现，比如相纸当场解锁）
    private func finishWithSuccess() {
        dismiss()
    }
}
