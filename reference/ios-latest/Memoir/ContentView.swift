import SwiftUI
import UIKit
import SwiftData

struct ContentView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(StoreKitManager.self) private var storeKitManager
    @Environment(LanguageManager.self) private var languageManager
    /// 桌面长按图标的快捷操作，由系统经 UIKit 送进来（见 `QuickActions.swift`）
    @EnvironmentObject private var quickActions: QuickActionSceneDelegate
    /// 点击「回信到了」通知，由系统经 UIKit 送进来（见 `AppDelegate.swift`）
    @EnvironmentObject private var appDelegate: AppDelegate
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// 用户同意过的政策版本。空串 = 从没同意过。
    /// 存版本号而不是布尔值，政策更新后才能重新征求同意（见 `LegalDocument.currentVersion`）
    @AppStorage("acceptedLegalVersion") private var acceptedLegalVersion = ""
    /// 自己那位笔友的名字。老用户还没起名的，进了主界面先补起一次（`PenPalNamingSheet`）
    @AppStorage(PenPalName.storageKey) private var penPalName = ""
    /// 底栏出不出搜索那颗圆（设置 → 外观，默认关）
    @AppStorage(DiarySearch.tabStorageKey) private var showSearchTab = false
    /// 新手指引走到哪一步（`FirstStep`）：要换 tab 的那几步在底栏上方指一下
    @AppStorage(FirstStep.storageKey) private var firstStepRaw = 0
    /// 第一封回信是谁写的（`FirstReplyWatcher` 记下）
    @AppStorage(FirstStep.replyFromKey) private var firstReplyFrom = ""
    @State private var selectedTab = 0
    /// 快捷操作「应用图标」→ 让设置页直接推出图标选择页
    @State private var openAppIconPicker = false
    /// 设置页的「身份」。离开设置 tab 时换一个新值，整页重建 = 导航栈回到首页。
    /// 需求：每次回到设置页都得是首页，不能停在上次打开的二级页（2026-09-15）
    @State private var settingsResetID = UUID()
    /// 点「回信到了」通知 → 让邮筒页直接推出信箱
    @State private var openLetterbox = false
    /// 从微信 /「文件」点开 `.memoir` 时待处理的备份包
    @State private var pendingBackup: BackupFileRef?

    /// 还没同意当前版本的政策（含从没同意过、以及政策更新后需要重新同意）
    private var needsLegalConsent: Bool {
        acceptedLegalVersion != LegalDocument.currentVersion
    }

    var body: some View {
        content
            // 🔴 隐私告知与同意 —— **必须在处理任何个人信息之前**（上架清单 A6）。
            // 盖在最上层且不可下滑关闭：不同意就过不去。
            //
            // 用只读 Binding 而不是 @State：能否关闭完全由「同意记录」决定，
            // 除了点同意之外没有第二条路能把它关掉。
            .fullScreenCover(isPresented: Binding(get: { needsLegalConsent }, set: { _ in })) {
                LegalConsentView {
                    acceptedLegalVersion = LegalDocument.currentVersion
                }
                .environment(themeManager)
            }
            // 系统把 .memoir 拷进 Documents/Inbox/ 后走这里进来。
            // 不判 onboarding 有没有走完 —— 「换新机 → 装 App → 从微信点开备份」
            // 恰恰是最典型的路径，这时候拦住用户毫无道理。
            .onOpenURL { url in
                guard url.pathExtension.lowercased() == BackupFormat.fileExtension else { return }
                pendingBackup = BackupFileRef(url: url)
            }
            .sheet(item: $pendingBackup) { pending in
                BackupImportView(fileURL: pending.url)
            }
            // 快捷操作：`initial: true` 不能省 —— 冷启动时动作在界面出现**之前**就到了，
            // 不带 initial 的 onChange 只看得见「之后的变化」，会把它漏掉
            .onChange(of: quickActions.pendingAction, initial: true) { _, action in
                handleQuickAction(action)
            }
            // 点了回信通知。`initial: true` 不能省：冷启动时通知在界面出现**之前**就到了
            .onChange(of: appDelegate.openLetterboxRequested, initial: true) { _, requested in
                guard requested else { return }
                appDelegate.openLetterboxRequested = false
                guard hasCompletedOnboarding else { return }
                selectedTab = 2
                openLetterbox = true
            }
            .onAppear { QuickAction.registerShortcutItems() }
            // 回到前台：补排在路上的信的到达通知（原因见 `LetterNotifications.rescheduleInTransit`）
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                let inTransit = ((try? modelContext.fetch(FetchDescriptor<Letter>())) ?? [])
                    .filter { LetterDelivery.isInTransit($0) }
                    .map { LetterNotifications.InTransit(id: $0.id, arrivesAt: LetterDelivery.arrival(of: $0), penPalName: $0.fromCharacter) }
                guard !inTransit.isEmpty else { return }
                Task { await LetterNotifications.rescheduleInTransit(inTransit) }
            }
            // 投进邮筒、还没写好的信：在前台就接着寄（App 被杀过、断过网的都从这里续上）。
            // 每 30 秒看一次，没有要寄的信时只读一下本地状态就返回（原因见 `LetterOutbox`）
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    // 放进独立的 Task：下拉控制中心、弹权限框都会让场景短暂变成 inactive，
                    // 这个 .task 随之取消 —— 不能连带把正在路上的请求也掐掉
                    await Task {
                        await LetterOutbox.process(context: modelContext, ai: env.ai, session: env.session,
                                                   isMember: storeKitManager.isMember, errors: env.errors)
                    }.value
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            // 尺素会员：签名交易或登录状态一变就交给服务器（笔友来信的额度只认服务器）。
            // 回到前台时先重查 Apple 的订阅状态 —— 续费、到期、退款会改变签名交易，进而触发这里
            .task(id: MembershipSyncKey(jws: storeKitManager.latestSignedTransaction, token: env.session.token)) {
                await syncMembershipToServer()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await storeKitManager.refreshEntitlements() }
            }
            // 回到前台：把两台设备各自建出来的同名日记本合成一本（原因见 `dedupeTagsByName`）
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                dedupeTagsByName(context: modelContext)
            }
            // 回到前台：把桌面图标对回「应该是哪个」（原因见 `ThemeManager.reconcileAppIcon`）
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                themeManager.reconcileAppIcon()
            }
            // 换了语言要重新登记，不然长按菜单还是旧语言
            .onChange(of: languageManager.appLanguage) {
                QuickAction.registerShortcutItems()
            }
    }

    private func handleQuickAction(_ action: QuickAction?) {
        guard let action else { return }
        quickActions.pendingAction = nil
        // 引导还没走完时界面上根本没有 tab，没地方可跳，直接丢掉
        guard hasCompletedOnboarding else { return }
        switch action {
        case .appIcon:
            selectedTab = 3
            openAppIconPicker = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if hasCompletedOnboarding {
            TabView(selection: $selectedTab) {
                Tab("记录", systemImage: "book.fill", value: 0) {
                    HomeView()
                }
                Tab("日记本", systemImage: "books.vertical.fill", value: 1) {
                    BookshelfView()
                }
                Tab("邮筒", systemImage: "envelope.fill", value: 2) {
                    PostBoxView(openLetterbox: $openLetterbox)
                }
                Tab("设置", systemImage: "gearshape", value: 3) {
                    SettingsView(openAppIconPicker: $openAppIconPicker)
                        .id(settingsResetID)
                }
                // 搜日记（2026-10-26）：系统原生的搜索标签 —— 单独一颗放大镜在右边，点开在底部展开搜索框（见文件末尾的 `SearchTabStandsApart`）。
                // 设置 → 外观里打开才有，默认关（`DiarySearch.tabStorageKey`）
                if showSearchTab {
                    Tab("搜索", systemImage: "magnifyingglass", value: 4, role: .search) {
                        DiarySearchView()
                    }
                }
            }
            .modifier(SearchTabStandsApart())
            .tint(themeManager.current.accent)
            .toolbarBackground(.thinMaterial, for: .tabBar)
            .toolbarBackgroundVisibility(.visible, for: .tabBar)
            // 🔴 在**离开**设置 tab 时重置，不在进入时 —— 否则桌面快捷操作
            //「应用图标」切进设置的同一刻要推出的图标页，会被这次重置冲掉
            .onChange(of: selectedTab) { old, new in
                // 新手指引 ④⑤：去邮筒寄第一封时，邮筒那一页可能还停在上次打开的信箱里 —— 退回邮筒首页，那叠信才看得见
                if new == 2, [.sendFirst, .pushPile].contains(FirstStep.current) { openLetterbox = false }
                guard old == 3, new != 3 else { return }
                openAppIconPicker = false
                settingsResetID = UUID()
            }
            // 照片 / 录音与 iCloud 对账：把本机新照片登记上去、把别的设备同步来的写回磁盘。
            // 放 task 里而不是 onAppear —— 它要读写文件，不该卡住首屏。
            .task {
                MediaStorage.reconcileWithCloud(in: modelContext)
            }
            // 不再建默认日记本（2026-10-27 用户定）：新用户只有「全部日记」，第一次写的时候由新手指引带着自己做一本
            .overlay(alignment: .top) {
                if let toast = env.errors.current {
                    ErrorToastView(toast: toast) { env.errors.dismiss() }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: env.errors.current)
            // 邮筒上「有没读的信」的小红点（没拆的欢迎信、第一封回信也靠它）
            .overlay { PostBoxUnreadDot(showsSearch: showSearchTab, color: themeManager.current.destructive, visible: selectedTab != 4) }
            .overlay { tabGuide }
            // 回信读过了才被杀掉的：重进时直接到结束语
            .onAppear { FirstStep.reconcile(in: modelContext) }
            .animation(.easeOut(duration: 0.3), value: firstStepRaw)
            // 老用户补起名（首启时起名还能跳过的那批）。挂在 TabView 上，不和外层的备份导入页抢同一个 sheet 槽位；
            // 只读绑定：起好名字 `needsNaming` 变成 false 才收起，除此之外关不掉。等隐私同意之后再弹
            .sheet(isPresented: Binding(get: { !needsLegalConsent && PenPalName.needsNaming(penPalName) },
                                        set: { _ in })) {
                PenPalNamingSheet()
                    .environment(themeManager)
            }
        } else {
            OnboardingView()
        }
    }

    /// 把当前生效的会员交易交给服务器。没登录、没会员时什么也不做。
    ///
    /// 失败只记日志、不打扰用户：这是后台同步，下次回到前台或重新打开 App 会再交一次。
    /// 用户自己点的购买 / 恢复失败，由付费页当场提示
    private func syncMembershipToServer() async {
        guard let jws = storeKitManager.latestSignedTransaction, let token = env.session.token else { return }
        do {
            let status = try await env.auth.syncAppleSubscription(signedTransaction: jws, token: token)
            NSLog("✅ [Membership] 已同步给服务器 isActive=%@", status.isActive ? "true" : "false")
        } catch {
            let ns = error as NSError
            NSLog("❌ [Membership] 同步给服务器失败（下次回到前台再试） domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(QuickActionSceneDelegate())
        .environmentObject(AppDelegate())
        .environment(ThemeManager())
        .environment(StoreKitManager())
        .modelContainer(for: [JournalEntry.self, Tag.self], inMemory: true)
}

extension ContentView {
    /// 新手指引里要换 tab 的那几步（回记录写第一篇、去邮筒寄出、回信到了去邮筒），和两张卡（寄出去了、结束语）
    @ViewBuilder
    fileprivate var tabGuide: some View {
        let theme = themeManager.current
        // 按阶段，不按刚走到哪一步：中途杀掉程序再进来停在别的 tab，也知道该往哪去
        switch FirstStep(rawValue: firstStepRaw) ?? .off {
        case .writeFirst, .createNotebook, .compose:
            if selectedTab != 0 {
                GuideTabHint(text: "试着写下你的第一篇日记吧，\n回到「记录」", tab: 0, showsSearch: showSearchTab, theme: theme)
            }
        case .sendFirst, .pushPile:
            if selectedTab != 2 {
                GuideTabHint(text: "你已经写下一篇日记了，\n去「邮筒」试着把它寄给你的笔友", tab: 2, showsSearch: showSearchTab, theme: theme)
            }
        case .sent:
            // ⑥ 第一封寄出去了：说一声会有回信（点「好」以后静静等着）
            ZStack {
                Color.black.opacity(0.22).ignoresSafeArea()
                GuideCard(text: "信寄出去了。\n\(PenPalName.display(penPalName))读完会给你回信，几个小时后就到，会放进信箱。",
                          button: "好", theme: theme) {
                    withAnimation(.easeOut(duration: 0.3)) { FirstStep.advance(to: .waitReply, from: [.sent]) }
                }
            }
        case .replyArrived:
            if selectedTab != 2 {
                GuideTabHint(text: "有一封来自\(firstReplyFrom)的回信，\n去「邮筒」看看", tab: 2, showsSearch: showSearchTab, theme: theme)
            }
        case .finale:
            // ⑩ 结束语：读完第一封回信
            ZStack {
                Color.black.opacity(0.22).ignoresSafeArea()
                GuideCard(text: "请多记录你的生活。\n点点滴滴都可以留在这里，想分享了，就寄给你的笔友。",
                          button: "好", theme: theme) {
                    withAnimation(.easeOut(duration: 0.3)) { FirstStep.finish() }
                }
            }
        case .waitReply, .readReply, .off:
            EmptyView()
        }
        // ⑥⑦ 寄出去以后盯着第一封回信
        if [.sent, .waitReply].contains(FirstStep(rawValue: firstStepRaw)) {
            FirstReplyWatcher()
        }
    }
}

/// 会员同步的触发键：签名交易或登录态任一变化就重新同步一次
private struct MembershipSyncKey: Equatable {
    let jws: String?
    let token: String?
}

/// 搜索 tab 单独一颗圆、不并进标签栏（用户定，2026-10-27）：点那颗放大镜就直接激活底部的搜索框。
/// 🔴 **不加这句，iOS 27 会把搜索 tab 并进标签栏当第五格**（iOS 26 默认是单独一颗圆）——
/// 在 27.0 模拟器上用 harness 实测：`.search` 不加 / `.searchable` 挂在 TabView 上都会并进去，只有这句和 27 新增的 `.prominent` 单独成圆；
/// `.prominent` 的搜索框跑到页面顶上，和 26 不一样，所以选这句。点搜索框旁的 ✕ 回到原来那个 tab（系统行为）
private struct SearchTabStandsApart: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabViewSearchActivation(.searchTabSelection)
        } else {
            content
        }
    }
}
