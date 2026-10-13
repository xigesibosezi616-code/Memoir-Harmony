import Foundation
import CoreData
import CloudKit
import Observation

/// CloudKit 同步的**真实**状态。
///
/// ## 为什么需要这个东西
///
/// 2026-08-12 出了一次真实的数据丢失：用户卸载重装后，原来的日记**一篇都没回来**。
/// 而设置页当时显示的是「iCloud 同步：已开启」——那句话只查了
/// `FileManager.ubiquityIdentityToken`（系统登没登 iCloud 账户），
/// **跟我们的容器能不能同步、数据有没有真的上去毫无关系**。
/// 用户看到「已开启」，理所当然地以为数据在云上。
///
/// 教训：**「系统登录了 iCloud」≠「你的数据在 iCloud 里」**。
/// 这两件事之间隔着容器配置、schema 匹配、网络、配额、以及同步引擎本身是否健康。
///
/// ## 它怎么知道真相
///
/// SwiftData 底层是 `NSPersistentCloudKitContainer`，每次同步（建立/导入/导出）
/// 都会发 `eventChangedNotification`，带成功与否和完整的 error。
/// 这是**唯一**能如实回答「数据到底有没有上去」的信号源。
///
/// > `hasEverExported` 会持久化。它回答的是那个最要紧的问题：
/// > **这台设备究竟有没有成功往云上推过一次数据。**
/// > 如果一直是 false，那么此刻卸载 App，本地的日记就是永久丢失 —— 云上根本没有副本。
@Observable
final class CloudSyncMonitor {

    enum AccountState: Equatable {
        case checking
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case failed(String)
    }

    private(set) var account: AccountState = .checking
    /// 最后一次**成功把本地改动推上云**的时间
    private(set) var lastExportAt: Date?
    /// 最后一次**成功从云端拉回改动**的时间
    private(set) var lastImportAt: Date?
    /// 最后一次失败的完整描述（domain + code，不是没信息量的 localizedDescription）
    private(set) var lastFailure: String?

    /// **这台设备有没有成功导出过哪怕一次。** 持久化 —— 这是判断
    /// 「现在卸载会不会丢数据」的唯一依据，不能只活在内存里。
    private(set) var hasEverExported: Bool {
        didSet { UserDefaults.standard.set(hasEverExported, forKey: Self.everExportedKey) }
    }

    private static let everExportedKey = "cloudSyncHasEverExported"
    private var observer: NSObjectProtocol?

    init() {
        hasEverExported = UserDefaults.standard.bool(forKey: Self.everExportedKey)
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - 启动监听

    /// App 启动时调一次。**只监听、不主动发请求** —— 同步由系统托管，我们只是把它的动静记下来。
    func start() {
        // 一行就能拆穿「环境不匹配」这种隐形问题 —— 出问题时先看这行连的是哪个库
        NSLog("☁️[Sync] CloudKit 数据库环境：%@（容器 iCloud.com.sinaratech.memoir）",
              Self.databaseEnvironment)
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            self?.handle(event)
        }
        Task { await refreshAccountStatus() }
    }

    /// 这次运行连的是**哪个 CloudKit 数据库**。
    ///
    /// 🔴 **Development 和 Production 是两个完全隔离的库，数据不互通。**
    /// 项目没有显式设 `com.apple.developer.icloud-container-environment`，
    /// 所以走默认：**Debug 构建连 Development，Release 构建连 Production**。
    ///
    /// 这个差异是**隐形**的 —— 同一个 App、同一个 iCloud 账户，用 Xcode 装的版本
    /// 和 TestFlight 装的版本看到的是两批数据。2026-08-12「数据在 Console 里看得见、
    /// 装回去却一条都没有」高度怀疑就是这个。所以启动时如实打出来。
    static var databaseEnvironment: String {
        #if DEBUG
        return "Development"
        #else
        return "Production"
        #endif
    }

    /// 查我们**自己那个容器**的账户状态。
    /// 与 `ubiquityIdentityToken` 的区别：那个只说系统有没有 iCloud 账户，
    /// 这个说的是「这个账户能不能用 `iCloud.com.sinaratech.memoir` 这个容器」——
    /// 后者才是同步能否工作的真条件。
    func refreshAccountStatus() async {
        do {
            let status = try await CKContainer(identifier: "iCloud.com.sinaratech.memoir").accountStatus()
            await MainActor.run {
                switch status {
                case .available: account = .available
                case .noAccount: account = .noAccount
                case .restricted: account = .restricted
                case .temporarilyUnavailable: account = .temporarilyUnavailable
                case .couldNotDetermine: account = .failed("无法确定")
                @unknown default: account = .failed("未知状态 \(status.rawValue)")
                }
                NSLog("☁️[Sync] 账户状态：%@", String(describing: self.account))
            }
        } catch {
            let ns = error as NSError
            await MainActor.run {
                account = .failed("\(ns.domain) code=\(ns.code)")
                NSLog("🔴[Sync] 账户状态查询失败 domain=%@ code=%ld error=%@",
                      ns.domain, ns.code, String(describing: error))
            }
        }
    }

    // MARK: - 事件处理

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        // endDate 为 nil 表示这次同步刚开始、还没有结论，不做判断
        guard event.endDate != nil else { return }

        if let error = event.error {
            let ns = error as NSError
            lastFailure = "\(typeName(event.type)) 失败：\(ns.domain) code=\(ns.code)"
            // 🔴 完整 error，不是 localizedDescription —— 后者常常只有
            // 「操作无法完成」这种没信息量的话（CLAUDE.md 调试方法一节）
            NSLog("🔴[Sync] %@ 失败 domain=%@ code=%ld error=%@",
                  typeName(event.type), ns.domain, ns.code, String(describing: error))
            return
        }

        switch event.type {
        case .export:
            lastExportAt = event.endDate
            if !hasEverExported {
                hasEverExported = true
                NSLog("☁️[Sync] ✅ 首次成功导出 —— 数据从这一刻起在 iCloud 上有副本了")
            }
            NSLog("☁️[Sync] 导出成功 %@", String(describing: event.endDate))
        case .import:
            lastImportAt = event.endDate
            NSLog("☁️[Sync] 导入成功 %@", String(describing: event.endDate))
        case .setup:
            NSLog("☁️[Sync] 同步引擎建立完成")
        @unknown default:
            break
        }
        lastFailure = nil
    }

    /// **只用于 NSLog 与内部诊断字符串，故意用英文** ——
    /// 这是给开发者看的，不进本地化表；且与 Apple 的 API 术语一致，便于对着文档查。
    private func typeName(_ t: NSPersistentCloudKitContainer.EventType) -> String {
        switch t {
        case .setup: return "setup"
        case .import: return "import"
        case .export: return "export"
        @unknown default: return "unknown"
        }
    }

    // MARK: - 给 UI 的结论

    /// 数据此刻在 iCloud 上是否有副本 —— 设置页据此决定要不要警告用户。
    var isProtected: Bool {
        account == .available && hasEverExported
    }
}
