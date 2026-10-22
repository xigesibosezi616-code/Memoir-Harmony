import Foundation
import StoreKit

/// 回信的「寄送」规则（2026-09-14 产品决策）。
///
/// ## 机制
///
/// - **邮筒 = 寄信（主动）**：用户点邮筒寄出日记。就在这一刻 AI 读日记、写好回信，
///   但信**先扣着**，不给用户看
/// - **信箱 = 收信（被动）**：回信在寄出后 **6 小时 ~ 3 天**的随机时刻「到达」，
///   到了弹一条本地通知，信箱里这时才看得见
///
/// ## 不改 schema，靠两个现有字段表达
///
/// | 字段 | 含义 |
/// |---|---|
/// | `generatedAt` | **寄出时刻**（= AI 写好的时刻） |
/// | `deliveredAt` | **到达时刻**。寄出时就算好，在未来 |
/// | `status == pending` 且 `deliveredAt > 此刻` | 在路上 |
///
/// 🔴 **这是跨端行为规则**，鸿蒙侧必须一致。见 `Docs/Harmony/CHANGELOG.md` 2026-09-14。
enum LetterDelivery {

    /// 最快多久到（6 小时）
    static let minimumDelay: TimeInterval = 6 * 3600
    /// 最慢多久到（3 天）
    static let maximumDelay: TimeInterval = 72 * 3600

    /// 一次最多寄出多少篇日记。只是个保护上限 —— 太多篇塞进一封信，提示词会超长
    static let maximumEntriesPerLetter = 14

    /// 回信的到达时刻：寄出后 [6 小时, 3 天] 内均匀随机。
    ///
    /// - Parameter timeScale: 时间压缩倍率，正式包恒为 1。
    ///   开发时用来加速（见 `debugTimeScale`），比如 1440 = 1 分钟当 1 天过
    static func arrivalDate<R: RandomNumberGenerator>(
        sentAt: Date,
        timeScale: Double = 1,
        using random: inout R
    ) -> Date {
        let delay = Double.random(in: minimumDelay...maximumDelay, using: &random)
        return sentAt.addingTimeInterval(delay / max(timeScale, 1))
    }

    static func arrivalDate(sentAt: Date, timeScale: Double = 1) -> Date {
        var g = SystemRandomNumberGenerator()
        return arrivalDate(sentAt: sentAt, timeScale: timeScale, using: &g)
    }

    // MARK: - 信件在哪个阶段

    /// 这封信算不算「真正寄出过」的信。
    ///
    /// 2026-09-14 之前的流程是先插一条占位再等 AI，会在库里留下 `generating` / `failed` / 空正文的记录，
    /// 这些不删（是库里的数据），但一律不当作寄出过的信
    static func isRealLetter(_ letter: Letter) -> Bool {
        guard !letter.body.isEmpty else { return false }
        switch LetterStatus(rawValue: letter.status) {
        case .pending, .delivered, .read: return true
        default: return false
        }
    }

    /// 到达时刻。老数据没有 `deliveredAt` 的，按寄出时刻算（等于早就到了）
    static func arrival(of letter: Letter) -> Date {
        letter.deliveredAt ?? letter.generatedAt
    }

    static func hasArrived(_ letter: Letter, now: Date = .now) -> Bool {
        isRealLetter(letter) && arrival(of: letter) <= now
    }

    static func isInTransit(_ letter: Letter, now: Date = .now) -> Bool {
        isRealLetter(letter) && arrival(of: letter) > now
    }

    static func isUnread(_ letter: Letter, now: Date = .now) -> Bool {
        hasArrived(letter, now: now) && letter.status != LetterStatus.read.rawValue
    }

    // MARK: - 开发加速

    /// UserDefaults key。只在**测试包**（Debug 包、TestFlight 包）的「设置 → 关于」里有开关
    static let debugFastDeliveryKey = "debugFastLetterDelivery"

    /// 测试包里加速开没开。**没碰过开关就算开着**（2026-10-17 产品要求：TestFlight 包也要很快收到回信，
    /// 测试的人不会去「关于」里找开关）。默认值和 `SettingsAboutView` 的 `@AppStorage` 必须一致
    static var debugFastDeliveryOn: Bool {
        UserDefaults.standard.object(forKey: debugFastDeliveryKey) as? Bool ?? true
    }

    /// UserDefaults key：测试包的「练习投信」（2026-10-20）。打开时把信推进投信口**只放动画、声音和震动**，
    /// 不建信、不调寄信接口，那叠信也不收走 —— 可以一遍遍推着试手感。只在测试包的「设置 → 关于」里有开关，默认关
    static let practicePostingKey = "practicePosting"

    /// 现在是不是在练习投信。**App Store 上下载的永远是 false**
    static var practicePosting: Bool {
        isTestBuild && UserDefaults.standard.bool(forKey: practicePostingKey)
    }

    /// 测试包恒为 1 以外的唯一来源：测试包打开加速时 1440（1 分钟 ≈ 1 天：2 小时 ≈ 5 秒，5 天 ≈ 5 分钟）。
    /// **App Store 上下载的永远是 1**，开关在 UserDefaults 里留着也不生效
    static var debugTimeScale: Double {
        isTestBuild && debugFastDeliveryOn ? 1440 : 1
    }

    /// 这个包是不是测试包：Debug 包，或者从 TestFlight 装的。先 `detectTestBuild()` 问过才准
    private(set) static var isTestBuild: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// 问一次「是不是 TestFlight 装的」，记在内存里（2026-10-11：给陈总的 TestFlight 包里没有加速开关，测不了收信）。
    ///
    /// TestFlight 包是 **Release 编译**的，`#if DEBUG` 分不出来，只能运行时问 StoreKit：
    /// TestFlight 装的 App，`AppTransaction.environment` 是 `.sandbox`；App Store 下载的是 `.production`。
    ///
    /// 🔴 **只记在内存里，不落盘**：从 TestFlight 版直接覆盖装上 App Store 版时，UserDefaults 会原样留下，
    /// 落了盘的话正式版也会以为自己是测试包。问不到（断网）就当不是，下次再问
    @discardableResult
    static func detectTestBuild() async -> Bool {
        #if DEBUG
        return true
        #else
        if isTestBuild { return true }
        do {
            let environment = try await AppTransaction.shared.unsafePayloadValue.environment
            isTestBuild = environment == .sandbox
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [LetterDelivery] 判断是否 TestFlight 失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        }
        return isTestBuild
        #endif
    }
}
