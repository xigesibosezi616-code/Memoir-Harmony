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
                HomeView()
                    .tabItem {
                        Image(systemName: "book.fill")
                        Text("记录")
                    }
                    .tag(0)

                BookshelfView()
                    .tabItem {
                        Image(systemName: "books.vertical.fill")
                        Text("日记本")
                    }
                    .tag(1)

                PostBoxView(openLetterbox: $openLetterbox)
                    .tabItem {
                        Image(systemName: "envelope.fill")
                        Text("邮筒")
                    }
                    .tag(2)

                SettingsView(openAppIconPicker: $openAppIconPicker)
                    .id(settingsResetID)
                    .tabItem {
                        Image(systemName: "gearshape")
                        Text("设置")
                    }
                    .tag(3)
            }
            .tint(themeManager.current.accent)
            .toolbarBackground(.thinMaterial, for: .tabBar)
            .toolbarBackgroundVisibility(.visible, for: .tabBar)
            // 🔴 在**离开**设置 tab 时重置，不在进入时 —— 否则桌面快捷操作
            //「应用图标」切进设置的同一刻要推出的图标页，会被这次重置冲掉
            .onChange(of: selectedTab) { old, new in
                guard old == 3, new != 3 else { return }
                openAppIconPicker = false
                settingsResetID = UUID()
            }
            // 照片 / 录音与 iCloud 对账：把本机新照片登记上去、把别的设备同步来的写回磁盘。
            // 放 task 里而不是 onAppear —— 它要读写文件，不该卡住首屏。
            .task {
                MediaStorage.reconcileWithCloud(in: modelContext)
            }
            .onAppear {
                ensureDefaultTagsExist()
            }
            .overlay(alignment: .top) {
                if let toast = env.errors.current {
                    ErrorToastView(toast: toast) { env.errors.dismiss() }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: env.errors.current)
        } else {
            OnboardingView()
        }
    }

    private func ensureDefaultTagsExist() {
        let descriptor = FetchDescriptor<Tag>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }
        let defaultNames = ["生活", "读书笔记", "旅行", "工作"]
        for (index, name) in defaultNames.enumerated() {
            let tag = Tag(name: name)
            tag.sortOrder = index
            modelContext.insert(tag)
        }
        try? modelContext.save()
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

/// 会员同步的触发键：签名交易或登录态任一变化就重新同步一次
private struct MembershipSyncKey: Equatable {
    let jws: String?
    let token: String?
}
