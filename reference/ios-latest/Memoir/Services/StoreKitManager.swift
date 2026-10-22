import StoreKit

/// 尺素会员的 StoreKit 2 这一层：商品、购买、恢复、交易监听、本机会员判定。
/// 产品规则见 `Memoir/Docs/MEMBERSHIP.md`（2026-10-09 定）。
///
/// ## 两处判定，各管一摊
/// - **本机（这里）**：相纸、封面版式这类界面上的会员能力。按 Apple 的订阅状态判，
///   断网、没登录也能用 —— 订阅属于 Apple ID，不需要我们的服务器点头
/// - **服务器**：笔友来信这种有成本的权益，只认服务器的订阅表（`rhythm.ts`）。
///   所以拿到签名交易后要交给服务器（`latestSignedTransaction` → `ContentView` 负责同步）
///
/// ## 必须一启动就开始监听交易（`start()`）
/// 续费、退款、家长批准的「请求购买」、在别的设备上买的，都从 `Transaction.updates` 进来。
/// 不监听的话这些交易一直不 `finish`，Apple 会反复推送，会员状态也跟着不对。
///
/// > 2026-08 前这里是皮革主题的单次购买（已封存后删除，皮革 2026-08-12 起免费）。
/// > App Store Connect 里那条 `com.sinaratech.memoir.theme.leather` 内购仍要手动下架（上架清单 B10）。
@Observable
final class StoreKitManager {
    /// 产品 ID **必须和 App Store Connect、后端 `membership.ts` 完全一致**
    static let yearlyID = "com.sinaratech.memoir.plus.yearly"     // 年付 ¥88，首年 ¥58
    static let monthlyID = "com.sinaratech.memoir.plus.monthly"   // 月付 ¥12
    static let productIDs: [String] = [yearlyID, monthlyID]

    // MARK: - 测试期：假开通

    /// 🔴 **上架前必须改成 `false`**（上架清单 A0c）。
    ///
    /// 2026-10-10 产品要求：App Store Connect 的订阅还没建好之前，会员要能全部试用。
    /// 打开时付费页照常显示（商品拉不到就用预设价格 ¥58 / ¥88 / ¥12 把页面画出来），
    /// 点「开通尺素会员」**不走付款**，直接在本机记成会员；会员页可以「关闭测试会员」回到免费。
    /// Debug、Release、TestFlight 包都生效 —— 就是给测试的人用的。
    ///
    /// 假会员**不交给服务器**（没有签名交易），笔友来信的额度只认服务器；
    /// 测试期来信节奏另由服务端开关 `LETTER_RHYTHM_OFF` 放开。
    static let testUnlock = true
    private static let testMemberKey = "memoir.testMember"

    /// 现在是不是测试期的假会员
    var isTestMember: Bool {
        Self.testUnlock && UserDefaults.standard.bool(forKey: Self.testMemberKey)
    }

    /// 测试期：点「开通」直接记成会员
    func testActivate() async {
        guard Self.testUnlock else { return }
        UserDefaults.standard.set(true, forKey: Self.testMemberKey)
        await refreshEntitlements()
    }

    /// 测试期：回到免费，方便测免费版
    func testDeactivate() async {
        UserDefaults.standard.removeObject(forKey: Self.testMemberKey)
        await refreshEntitlements()
    }

    /// 年付在前（付费页默认选中年付）
    private(set) var products: [Product] = []
    private(set) var isMember = false
    /// 当前生效的那一笔
    private(set) var activeProductID: String?
    private(set) var expiresAt: Date?
    /// 首年 ¥58 这类新用户优惠还能不能享受（同一订阅组每个 Apple ID 只有一次）
    private(set) var isEligibleForIntroOffer = true
    /// 当前生效那一笔的签名交易（JWS），交给服务器验证用。没会员时为 nil
    private(set) var latestSignedTransaction: String?
    /// 商品加载失败时的原因（付费页据此显示「暂时无法连接 App Store」）
    private(set) var productsError: Error?

    private var updatesTask: Task<Void, Never>?

    enum PurchaseOutcome {
        case purchased
        /// 等待中：家长批准的「请求购买」、需要额外验证的付款方式。批下来后从 `Transaction.updates` 进来
        case pending
        case cancelled
    }

    // MARK: - 启动

    /// App 启动时调一次：先开始监听，再查现有会员、拉商品
    func start() async {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { return }
                    if case .verified(let transaction) = result {
                        await transaction.finish()
                    } else {
                        NSLog("⚠️ [Membership] 收到一笔验签不过的交易更新，忽略")
                    }
                    await self.refreshEntitlements()
                }
            }
        }
        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { ($0.id == Self.yearlyID ? 0 : 1) < ($1.id == Self.yearlyID ? 0 : 1) }
            productsError = nil
            // StoreKit 遇到不存在的 ID 不报错、只是不返回 —— 不打这行的话「ASC 里没建 / ID 对不上」完全无声
            if products.count < Self.productIDs.count {
                let missing = Set(Self.productIDs).subtracting(products.map(\.id))
                NSLog("⚠️ [Membership] 商品没拉全，缺 %@（App Store Connect 里还没建，或 ID 对不上）", missing.sorted().joined(separator: ", "))
            }
            if let yearly = products.first(where: { $0.id == Self.yearlyID }),
               let subscription = yearly.subscription {
                isEligibleForIntroOffer = await subscription.isEligibleForIntroOffer
            }
        } catch {
            let ns = error as NSError
            NSLog("❌ [Membership] 商品加载失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            productsError = error
        }
    }

    // MARK: - 会员判定

    /// 按 Apple 的现有权益重算会员状态。取到期时间最晚的那一笔
    func refreshEntitlements() async {
        var best: (transaction: Transaction, jws: String)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let expires = transaction.expirationDate, expires <= .now { continue }
            if best == nil || (transaction.expirationDate ?? .distantFuture) > (best!.transaction.expirationDate ?? .distantFuture) {
                best = (transaction, result.jwsRepresentation)
            }
        }

        #if DEBUG
        // 调试用：启动参数 `-membership member` / `-membership free` 强制会员状态，不加则按真实购买
        if let forced = UserDefaults.standard.string(forKey: "membership") {
            isMember = forced == "member"
            activeProductID = isMember ? Self.yearlyID : nil
            expiresAt = isMember ? Calendar.current.date(byAdding: .year, value: 1, to: .now) : nil
            latestSignedTransaction = nil   // 假会员不能交给服务器
            return
        }
        #endif

        // 测试期的假会员（见 `testUnlock`）。真买过的话以真的为准
        if best == nil, isTestMember {
            isMember = true
            activeProductID = Self.yearlyID
            expiresAt = Calendar.current.date(byAdding: .year, value: 1, to: .now)
            latestSignedTransaction = nil   // 假会员不能交给服务器
            return
        }

        isMember = best != nil
        activeProductID = best?.transaction.productID
        expiresAt = best?.transaction.expirationDate
        latestSignedTransaction = best?.jws
    }

    // MARK: - 购买与恢复

    /// 买。失败（网络、商店出错、验签不过）抛错，交给调用方展示
    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                await refreshEntitlements()
                return .purchased
            case .unverified(_, let error):
                // 不 finish：这笔没验过，不当成买到
                let ns = error as NSError
                NSLog("❌ [Membership] 购买结果验签不过 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
                throw error
            }
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// 恢复购买：让 App Store 把这个 Apple ID 的交易重新同步一遍（会弹系统的 Apple ID 验证）
    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }
}
