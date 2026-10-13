import SwiftUI
import SwiftData

@main
struct MemoirApp: App {
    /// 桥接回 UIKit，接住 SwiftUI 生命周期本身接不了的系统回调：
    /// 桌面长按图标的快捷操作、点击回信到达通知。详见 `AppDelegate.swift`。
    /// 2026-09-14 加，用户确认过这条注入路径。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var themeManager = ThemeManager()
    @State private var storeKitManager = StoreKitManager()
    @State private var languageManager = LanguageManager()
    @State private var appEnvironment = AppEnvironment(ai: Self.makeAIService())
    /// 这次启动要不要放开场。
    ///
    /// **在这里就判断掉**，而不是进了 `SplashView` 再决定：
    /// 当前主题没配封面图时，连一帧启动页背景都不该闪。
    /// 用 `@State` 的初值只在进程启动时求值一次 —— 正是我们要的时机。
    ///
    /// > 🔒 视频轮播那套已封存（见 `SplashVideoPool`）。解封时这行换回
    /// > `SplashVideoPool.shouldPlayToday()`，并把 `SplashView.style` 改成 `.video`。
    @State private var showSplash = SplashCoverPool.coverForCurrentTheme != nil
    @AppStorage("showSplashAnimation") private var showSplashAnimation: Bool = true

    init() {
        // 进程级图片缓存（上限 100 张 / 50 MB），加速详情页滑动 + 翻页阅读器
        ImageCache.setup()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 🔴 **主界面常驻在最底层，启动页盖在它上面**，而不是 if/else 二选一。
                //
                // 原先是二选一：开场放完的那一刻才开始构建 `ContentView`
                // （TabView + 一堆 `@Query` + onAppear 里的示例数据/心情初始化），
                // 于是切换的瞬间主线程被占满 —— 用户看到的就是"闪一下、卡一下"。
                // 转场动画本身没问题，掉帧的是构建。
                //
                // 现在主界面在视频播放期间就已经建好、数据也加载完了，
                // 开场结束只是把上面那层淡掉，底下是现成的画面 —— 不会再有那一下停顿。
                ContentView()
                    // 皮革等深色主题：整个 App 走系统深色（原因见 `AppTheme.preferredColorScheme`）。
                    // 和纸 / 北欧是 nil = 不指定，和没加这一行完全一样
                    .preferredColorScheme(themeManager.current.preferredColorScheme)
                    .environment(themeManager)
                    .environment(storeKitManager)
                    .environment(languageManager)
                    .environment(appEnvironment)
                    .environment(\.locale, languageManager.currentLocale)
                    // 开始监听 CloudKit 同步事件。**只监听不发请求** ——
                    // 同步由系统托管，我们只是把它的成败记下来，好让设置页
                    // 能如实回答「数据到底上没上云」。
                    .task {
                        appEnvironment.cloudSync.start()
                    }
                    // 尺素会员：一启动就开始监听交易（续费、退款、别的设备上买的都从这里进来），
                    // 再查现有会员、拉商品。交给服务器那一步在 `ContentView`（那里才有登录态）
                    .task {
                        await storeKitManager.start()
                    }

                if showSplash && showSplashAnimation {
                    // 这里**不需要**再包 withAnimation / transition：
                    // 淡出是 `SplashView` 自己做的，回调进来时它已经完全透明了，
                    // 这一步只是把一层看不见的东西摘掉。
                    SplashView(onFinish: { showSplash = false })
                        .environment(themeManager)
                        .zIndex(1)   // 盖住主界面；不写的话 SwiftUI 不保证它在上层
                }

                // 隐藏的一次性 Tag 迁移触发器（仅当首次启动时跑一次）
                TagMigrationRunner()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
        }
        .modelContainer(Self.sharedModelContainer)
    }

    /// AI 服务实现选择 —— nil 表示用真后端（`ProxyAIService` → DeepSeek）。
    ///
    /// 想离线开发邮筒 UI（不消耗 DeepSeek 额度、不需要登录），把返回值改成 `MockAIService()`。
    private static func makeAIService() -> AIService? {
        nil
    }

    /// 🔴 **全进程唯一的一个容器。绝对不要写成 `.modelContainer(Self.makeModelContainer())`。**
    ///
    /// 那个写法看着人畜无害，实际上修饰符的参数**在每次 body 求值时都会重新求值** ——
    /// `showSplash` 一变（开场播完）body 就重算一次，于是**又新建一个带 CloudKit 的容器**。
    ///
    /// 后果在模拟器上完全看不出来：没有 iCloud 账号时 `.automatic` 退化成纯本地，
    /// 建一个容器只要几十毫秒，多建几个也不过是浪费点内存。
    /// **真机上每个容器都会拉起一整套 `NSPersistentCloudKitContainer` 同步引擎** ——
    /// 建 CKContainer 连接、注册 push 订阅、拉取整个私有库。
    /// 两套引擎同时对**同一个 store 文件**和**同一个 iCloud 容器**读写，
    /// SQLite 文件锁互相打架，启动期主线程卡死 → watchdog 杀进程（`8badf00d` / SIGKILL）。
    ///
    /// 2026-08-09 「真机一装就崩」查了两轮、白回退了一次 schema，真凶就是这一行。
    /// 当时归因到同一批上真机的 `Letter.toName` + SchemaV6，**归因是错的**。
    ///
    /// `static let` 是 lazy 且线程安全的，全进程只求值一次 —— 这正是我们要的。
    private static let sharedModelContainer: ModelContainer = makeModelContainer()

    /// SwiftData 容器构建 —— 走 `MemoirMigrationPlan` 版本化迁移路径。
    ///
    /// **Release**：任何失败直接 `fatalError`。schema 不能匹配 = 数据完整性已被破坏，
    /// 比静默清空 store 更安全（让 Crashlytics / 用户能看到问题，不悄悄丢数据）。
    ///
    /// **Debug**：保留删 store 重试的 fallback，方便本地开发期 schema 演进时自救。
    /// release 编译里这段 fallback 不存在。
    private static func makeModelContainer() -> ModelContainer {
        // CloudKit 私有数据库：数据在用户自己的 iCloud，我们看不到 ——
        // 和「私密日记」的产品承诺一致，也让换机/丢机不再等于日记全没。
        //
        // ⚠️ 上架前必须去 CloudKit Console 点一次「Deploy Schema Changes」，
        // 把开发环境的 schema 推到生产环境，否则线上版本同步全挂。
        let config = ModelConfiguration(
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: SchemaV8.self),
                migrationPlan: MemoirMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            // 🔴 打完整的 error，不是 localizedDescription ——
            // 后者常常只有「操作无法完成」这种没信息量的话，domain + code 才能定位。
            // 用 NSLog 而不是 print：从桌面点图标启动（没连 Xcode）时，
            // print 什么都看不到，NSLog 会进系统日志，Console.app / `log stream` 能抓到。
            let ns = error as NSError
            NSLog("🔴[Boot] ModelContainer 创建失败 domain=%@ code=%ld error=%@",
                  ns.domain, ns.code, String(describing: error))
            #if DEBUG
            print("⚠️ [DEBUG] ModelContainer 创建失败，尝试重置本地 store: \(error)")
            let appSupport = URL.applicationSupportDirectory
            for name in ["default.store", "default.store-shm", "default.store-wal"] {
                try? FileManager.default.removeItem(at: appSupport.appending(path: name))
            }
            do {
                let container = try ModelContainer(
                    for: Schema(versionedSchema: SchemaV8.self),
                    migrationPlan: MemoirMigrationPlan.self,
                    configurations: [config]
                )
                // ⚠️ 这条**必须醒目**：走到这里意味着本地库已经被清空重建了。
                // App 看着"能启动"，其实数据没了 —— 这个兜底掩盖过一次真实的迁移失败。
                NSLog("⚠️[Boot] 已重置本地 store 并重建成功 —— 本地数据已被清空，不要把这当成正常启动")
                return container
            } catch {
                // 删掉本地 store 后**第二次仍然失败**，说明问题不在本地库，
                // 而在容器这一层（典型：iCloud 里残留的 record type 与当前 schema 对不上）。
                NSLog("🔴[Boot] 重置 store 后仍失败 —— 问题不在本地 store，查 CloudKit: %@",
                      String(describing: error))
                fatalError("[DEBUG] ModelContainer 重建仍失败: \(error)")
            }
            #else
            fatalError("ModelContainer 创建失败: \(error)")
            #endif
        }
    }
}

// MARK: - Tag 迁移触发器

/// 隐藏 view —— 启动时跑一次旧 Tag 颜色/纹理迁移到 BookColor / BookTexture 系统，
/// 以及日记的单本整理。
/// 用 `@AppStorage` 守卫保证幂等：迁移成功后置位 true，后续启动直接跳过。
private struct TagMigrationRunner: View {
    @Environment(\.modelContext) private var modelContext
    /// ⚠️ **给迁移函数加了新逻辑就要换这个 key**，否则老用户早已置位 true，
    /// 新加的那步永远不会执行。
    /// `V21Colors`（2026-08-08）：封面配色从 12 色收敛到 9 色，
    /// 赭红/橄榄褐/古铜要就近映射到保留色。
    /// `LinenOnly`（2026-10）：皮革下架，纹理一律改成亚麻，牛皮映射到琥珀棕。
    /// 迁移函数本身幂等，重跑一次是安全的。
    @AppStorage("didMigrateCoverLinenOnly") private var didMigrate: Bool = false
    /// 2026-10：一篇日记只属于一本日记本，多于一本的退回「全部日记」（见 `migrateEntriesToSingleNotebook`）。
    /// 与上面的封面迁移各用各的 key，互不牵连
    @AppStorage("didMigrateSingleNotebook") private var didMigrateSingleNotebook: Bool = false

    var body: some View {
        Color.clear
            .task {
                if !didMigrate {
                    migrateTagsToBookCoverSystem(context: modelContext)
                    didMigrate = true
                }
                if !didMigrateSingleNotebook {
                    migrateEntriesToSingleNotebook(context: modelContext)
                    didMigrateSingleNotebook = true
                }
            }
    }
}
