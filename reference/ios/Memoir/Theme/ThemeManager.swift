import SwiftUI
import UIKit

@Observable
class ThemeManager {
    var current: any AppTheme = BambooTheme()
    var currentThemeID: String = "bamboo" {
        didSet {
            current = Self.theme(for: currentThemeID)
            UserDefaults.standard.set(currentThemeID, forKey: "selectedTheme")
            // 只有「跟随主题」时才跟着换图标 —— 用户手动选过的话，
            // 换主题不该把他的选择覆盖掉
            if isFollowingThemeIcon && !suppressIconFollow {
                Task { @MainActor in applyAppIcon() }
            }
        }
    }

    /// 按 id 取主题实例，**不改变当前生效的主题**。
    ///
    /// 主题介绍弹窗要用「即将切换过去的那套主题」的配色渲染自己 ——
    /// 用户在按下确认之前就能看到这套主题长什么样，弹窗本身就是预览。
    static func theme(for id: String) -> any AppTheme {
        switch canonicalThemeID(id) {
        case "leather": return LeatherTheme()
        case "kent": return KentTheme()
        default: return BambooTheme()
        }
    }

    /// 2026-09-16 主题改名（素笺 / 皮革 / 肯特）时，内部标识也跟着改了：
    /// `washi` → `bamboo`、`nordic` → `kent`（`leather` 不变）。
    ///
    /// 这张表把老设备上存着的旧值映射过来 —— **不做的话，装过旧版本的机器一升级，
    /// 主题和图标选择都会掉回默认**。图标选择存的是 `AppIconOption.rawValue`，
    /// 与主题 id 同名，所以两者共用这一张表。
    ///
    /// **正式上架后可以整块删掉** —— 那之后不会再有存着旧 id 的设备。
    private static let legacyThemeIDs = ["washi": "bamboo", "nordic": "kent"]

    /// 把可能是旧值的 id 归一成当前用的 id
    static func canonicalThemeID(_ id: String) -> String {
        legacyThemeIDs[id] ?? id
    }

    init() {
        // 🔴 **init 里的赋值必须挡住图标联动。**
        // `@Observable` 会把存储属性改写成计算属性，所以 `didSet` 在 `init` 里**照样会触发**
        // （普通存储属性不会，这里很容易看走眼）。下面的迁移会把 `appIconSelection`
        // 从旧 id 改成新 id，不挡的话启动过程中就会调一次 `setAlternateIconName` ——
        // 而 iOS 在 App 还没活跃时会直接拒绝（`NSCocoaErrorDomain code=3072 已取消操作`，
        // 2026-09-27 真机日志实证），白失败一次还可能弹系统提示。
        suppressIconFollow = true
        defer { suppressIconFollow = false }

        // 读出来的值可能是改名前的，先归一再用，并把归一结果写回去（每台机器只会发生一次）
        let savedIcon = UserDefaults.standard.string(forKey: Self.iconStorageKey) ?? ""
        let icon = Self.canonicalThemeID(savedIcon)
        if icon != savedIcon { UserDefaults.standard.set(icon, forKey: Self.iconStorageKey) }
        appIconSelection = icon

        let savedTheme = UserDefaults.standard.string(forKey: "selectedTheme") ?? "bamboo"
        let themeID = Self.canonicalThemeID(savedTheme)
        if themeID != savedTheme { UserDefaults.standard.set(themeID, forKey: "selectedTheme") }
        self.currentThemeID = themeID
        current = Self.theme(for: themeID)
    }

    // MARK: - App 图标

    /// 用户在设置里选的图标。**空串 = 跟随主题**（默认）。
    ///
    /// 存字符串而不是枚举，是因为 `@Observable` 里要落 UserDefaults，
    /// 而且以后删掉某个图标时，老用户存的旧值能安全地退回「跟随主题」。
    var appIconSelection: String = "" {
        didSet {
            guard appIconSelection != oldValue else { return }
            UserDefaults.standard.set(appIconSelection, forKey: Self.iconStorageKey)
            guard !suppressIconFollow else { return }
            applyAppIcon()
        }
    }

    static let iconStorageKey = "appIconSelection"

    /// 挡住上面两个 didSet 里的自动图标联动。
    ///
    /// `switchTheme` 要自己决定换不换图标，而且要能把失败上报给调用方 ——
    /// didSet 里那条联动是静默的（只写 NSLog），用户在弹窗里明确选了
    /// 「一并更换图标」时，失败必须让他看见。
    @ObservationIgnored private var suppressIconFollow = false

    /// 主题介绍弹窗里那两个按钮，统一走这里。
    ///
    /// **顺序是有讲究的**：先换主题、最后才动图标。反过来（先回到「跟随主题」）
    /// 会先切到**旧主题**的图标、再切一次新的 —— 每切一次，系统就弹一次
    /// 「您已更改图标」，用户要吃两遍。
    ///
    /// - Parameters:
    ///   - alsoIcon: `true` = 一并更换图标（回到「跟随主题」）；
    ///     `false` = 只换主题，**图标保持现在这个不动**（把当前图标固定下来）
    ///   - onIconFailure: 图标没换成时的回调。**主题切换不回滚** ——
    ///     换图标失败通常是图标资源没打包进去，不该把用户选的主题也一起撤掉
    /// 图标选择页用：记下用户的选择，并且**只切换一次**。
    ///
    /// 🔴 不能写成「`appIconSelection = x` 再调 `applyAppIcon(onFailure:)`」——
    /// 前者的 didSet 已经静默切过一次，而那次是异步的，第二次调用时
    /// `alternateIconName` 往往还没变成目标值，于是又切一次，
    /// **用户要连吃两遍系统的「您已更改图标」提示**。
    @MainActor
    func selectAppIcon(_ option: AppIconOption?, onFailure: ((Error) -> Void)? = nil) {
        suppressIconFollow = true
        appIconSelection = option?.rawValue ?? ""
        suppressIconFollow = false
        applyAppIcon(onFailure: onFailure)
    }

    @MainActor
    func switchTheme(to id: String, alsoIcon: Bool, onIconFailure: ((Error) -> Void)? = nil) {
        suppressIconFollow = true
        if alsoIcon {
            // 回到「跟随主题」；真正的切换交给下面那次 applyAppIcon，只切一次
            appIconSelection = ""
        } else if isFollowingThemeIcon {
            // 「仅更换主题」：把当前图标固定下来，否则换完主题它会自己跟着变
            appIconSelection = resolvedAppIcon.rawValue
        }
        currentThemeID = id
        suppressIconFollow = false

        if alsoIcon {
            applyAppIcon(onFailure: onIconFailure)
        }
    }

    /// 当前该用哪个图标：选了就用选的，没选就跟着主题走
    var resolvedAppIcon: AppIconOption {
        if let picked = AppIconOption(rawValue: appIconSelection) {
            return picked
        }
        return AppIconOption.forTheme(currentThemeID)
    }

    /// 是否处于「跟随主题」模式
    var isFollowingThemeIcon: Bool {
        AppIconOption(rawValue: appIconSelection) == nil
    }

    /// 把系统当前的桌面图标对回「按用户的选择应该是哪个」。**App 每次变为活跃时调一次。**
    ///
    /// 🔴 **`setAlternateIconName` 只在 App 活跃时才work。** 息屏、启动过程中、
    /// 弹窗动画里调用，iOS 一律拒绝并回 `NSCocoaErrorDomain 3072「已取消操作」`
    /// —— 2026-09-27 真机实测：同一台机器，活跃时切 KentIcon / LeatherIcon 都成功，
    /// 不活跃时连「切回主图标」都被拒。而我们只在日志里记一笔，用户什么都看不到，
    /// 于是表现成「图标怎么点都不换」。
    ///
    /// 有了这个对账，两种失配都能自愈：
    /// - 图标资源改过名（`NordicIcon` → `KentIcon`），老设备上系统退回了主图标
    /// - 用户在主题弹窗里选了「一并更换图标」，但那一刻 App 恰好不活跃、切换被拒
    @MainActor
    func reconcileAppIcon() {
        // applyAppIcon 内部已经有「已经是目标就不调」的判断，这里直接交给它
        applyAppIcon()
    }

    /// 把 `resolvedAppIcon` 真正应用到系统。
    ///
    /// 🔴 **原先这里的失败是完全静默的** —— 没接 completion handler，
    /// 而当时 `LeatherIcon` 这个 appiconset 根本不存在，于是「切到皮革主题图标不变」
    /// 这件事从头到尾没有任何提示。**图标切换失败的原因几乎总是资源没打包进去**
    /// （`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` 漏加），
    /// 所以必须打出完整的 domain + code，不能只打 localizedDescription。
    ///
    /// `onFailure` 交给调用方决定要不要提示用户：主题联动时静默记日志就行，
    /// 用户在图标选择页手动点的，必须让他看见失败。
    @MainActor
    func applyAppIcon(onFailure: ((Error) -> Void)? = nil) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let target = resolvedAppIcon.alternateName
        // 已经是目标图标就不要再调 —— 每次调用系统都会弹一次
        // 「你已更改 App 图标」的提示，重复调用等于骚扰用户
        guard UIApplication.shared.alternateIconName != target else { return }

        UIApplication.shared.setAlternateIconName(target) { error in
            guard let error else { return }
            let ns = error as NSError
            NSLog("🔴[AppIcon] 切换失败 target=%@ domain=%@ code=%ld error=%@",
                  target ?? "AppIcon(主图标)", ns.domain, ns.code, String(describing: error))
            Task { @MainActor in onFailure?(error) }
        }
    }
}
