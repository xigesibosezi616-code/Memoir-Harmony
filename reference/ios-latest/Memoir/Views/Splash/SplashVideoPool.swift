import Foundation

/// 🔒 **已封存（2026-08-11）—— 当前不启用，但代码完整保留且参与编译。**
///
/// 开场现在用的是按主题的静态封面（`SplashCoverPool`）。封存原因：
/// **体积**。实测一条 3 秒屏录 = 7.1MB，压 HEVC 也要 4.6MB；按每条 4.6MB 算，
/// 70 条 ≈ 322MB，超过 App Store 蜂窝下载上限（200MB），
/// 用户必须连 Wi-Fi 才能装 —— 那是首次下载最大的流失点。
///
/// **怎么解封**（三步，不需要改这个文件）：
/// 1. `SplashView.style` 改回 `.video`
/// 2. 视频放回 `Memoir/Resources/SplashVideos/`（目录还在，现在是空的）
/// 3. `MemoirApp.showSplash` 的判断换回 `SplashVideoPool.shouldPlayToday()`
///
/// > 📌 **刻意不注释掉、不删除**：注释掉的代码不参与编译，重构 / 改 API / 升 SDK 时
/// > 不会跟着被修，等到想解封时它早就烂了。保持编译是封存的代价，也是封存的意义。
/// > 详见 `Memoir/MEMOIR_DEV_SPEC.md` 的「已封存的功能」一节。
///
/// ---
///
/// 启动视频池 —— **把视频拖进 Xcode 就生效，不用改任何代码**。
///
/// ## 怎么加视频
///
/// 把视频文件拖进 `Memoir/Resources/SplashVideos/`（Finder 里放进去也行）。
/// 本项目用的是 Xcode 的**文件系统同步文件夹**，目录下的文件会自动成为 target 资源，
/// 不需要手动勾 Target Membership，也不用动 `project.pbxproj`。
///
/// 视频**打包在 App 里**，随 App 一起从 App Store 下载 —— 装完就能用，不额外联网拉取。
/// 支持 `.mp4` / `.mov` / `.m4v`。文件名随意，中文也可以。
///
/// ## 播哪一条：洗牌队列 + 一天一条
///
/// - **一轮之内不重复**：本轮播过的记在 `playedThisRoundKey` 里，每次只从"还没播的"里随机取。
///   一轮播完（全部播过）就清空重开，等于把所有视频重新洗一次牌。
/// - **一天只播一次**：以**凌晨 4 点**为「新的一天」的分界（按用户设备所在时区）。
///   当天首次打开播一条，之后无论开多少次都不播，直到跨过下一个 4 点。
///
/// > 为什么用「记已播 + 从剩余随机取」而不是「预先生成打乱好的队列」：
/// > 两者产生的序列分布是等价的（每次从剩余均匀随机 = 一个均匀随机排列），
/// > 但前者**能容忍你中途增删视频** —— 新拖进来的片子立刻算作"还没播的"，
/// > 不用等这一轮结束；删掉的也不会在队列里留下找不到的名字。
///
/// ## ⚠️ 关于体积
///
/// 70 条视频很容易把 App 撑大。App Store 对**蜂窝网络下载**有体积上限，
/// 超了用户就必须连 Wi-Fi 才能装 —— 首次下载的流失点。
/// 建议每条压到 **1–3 秒、720p、H.265**，单条控制在 1MB 以内。
enum SplashVideoPool {

    /// 视频放在这个子目录下。找不到该目录时会退回扫描 bundle 根目录 ——
    /// 因为「拖进 Xcode」有两种落法：蓝色 folder reference 会保留目录结构，
    /// 而文件系统同步文件夹会把资源**平铺**到 bundle 根。两种都要认。
    static let directoryName = "SplashVideos"

    static let supportedExtensions = ["mp4", "mov", "m4v"]

    /// 🔴 **上架前必须改回 `true`**（已记进 `Docs/PRELAUNCH_CHECKLIST.md` 的 B 级清单）。
    ///
    /// - `false` = **测试模式**：只要设置页的「启动动画」开关是开的，**每次启动都播**。
    ///   方便反复看效果、挨条过一遍池子里的片子。
    ///   注意洗牌队列仍然生效 —— 每次启动播下一条，一轮之内不会重复。
    /// - `true` = **正式行为**：一天只播一次，凌晨 4 点换新的一天。
    ///
    /// 忘了改回来的后果：用户每次开 App 都要看一遍开场动画，是很快会被烦到的那种。
    static let limitToOncePerDay = false

    /// 「新的一天」从凌晨几点开始。**不是 0 点** ——
    /// 熬夜到两三点的人，那仍然是"今天"，不该因为过了午夜就又给他放一次开场。
    static let dayBoundaryHour = 4

    private static let playedThisRoundKey = "splashPlayedThisRound"
    private static let lastPlayedDayKey = "splashLastPlayedDay"

    // MARK: - 池子

    /// 池子里所有视频。按文件名排序，保证顺序稳定（便于排查"这次播的是哪条"）。
    static var all: [URL] {
        var found: [URL] = []
        for ext in supportedExtensions {
            // 先按子目录找（folder reference 的落法）
            let inSubdir = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: directoryName) ?? []
            // 再找 bundle 根（文件系统同步文件夹的落法）
            let inRoot = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
            found.append(contentsOf: inSubdir)
            found.append(contentsOf: inRoot)
        }
        // 两种落法可能同时命中同一个文件，按文件名去重
        var seen = Set<String>()
        return found
            .filter { seen.insert($0.lastPathComponent).inserted }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - 今天该不该播

    /// 今天是否还没播过（池子为空时也返回 false —— 没片子就没有开场）。
    ///
    /// 调用方（`MemoirApp`）用它决定**要不要进入启动页分支**。
    /// 在那一层就判断掉，今天已播过时连一帧启动页背景都不会闪。
    static func shouldPlayToday(now: Date = .now) -> Bool {
        guard !all.isEmpty else { return false }
        // 测试模式：不看"今天播没播过"，每次启动都放（是否显示仍由设置页开关决定）
        guard limitToOncePerDay else { return true }
        return UserDefaults.standard.string(forKey: lastPlayedDayKey) != dayKey(for: now)
    }

    /// 取今天要播的那条。今天已经播过、或池子为空时返回 nil。
    ///
    /// **有副作用**：取到之后就从本轮队列里划掉；正式模式下还会记为"今天已播"。
    static func videoForToday(now: Date = .now) -> URL? {
        guard shouldPlayToday(now: now), let picked = dequeue() else { return nil }
        // 测试模式下不记"今天已播"，否则第二次启动就又不播了
        if limitToOncePerDay {
            UserDefaults.standard.set(dayKey(for: now), forKey: lastPlayedDayKey)
            // 这一步发生在 App 刚启动的几秒内，而用户完全可能看完开场就把 App 从后台划掉。
            // UserDefaults 平时是异步落盘的，那种情况下记录有丢失的风险 ——
            // 丢了的后果是同一天再打开又播一次。启动期只写这一次，强制落盘的开销可以忽略。
            UserDefaults.standard.synchronize()
        }
        return picked
    }

    // MARK: - 内部

    /// 「今天」的标识。把时间往前挪 `dayBoundaryHour` 小时再取日期 ——
    /// 于是凌晨 4 点之前算作前一天。
    private static func dayKey(for date: Date) -> String {
        let shifted = date.addingTimeInterval(-Double(dayBoundaryHour) * 3600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current   // 跟随用户设备所在时区
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 从"本轮还没播的"里随机取一条；全播过了就开新一轮。
    private static func dequeue() -> URL? {
        let pool = all
        guard !pool.isEmpty else { return nil }
        let names = pool.map(\.lastPathComponent)

        // 只保留仍然存在于池子里的记录 —— 用户可能删掉了某些视频
        var played = Set(UserDefaults.standard.stringArray(forKey: playedThisRoundKey) ?? [])
        played.formIntersection(names)

        var remaining = names.filter { !played.contains($0) }
        if remaining.isEmpty {
            // 一轮结束：重新洗牌，全部视频再来一遍
            played.removeAll()
            remaining = names
        }

        guard let pickedName = remaining.randomElement() else { return nil }
        played.insert(pickedName)
        UserDefaults.standard.set(Array(played), forKey: playedThisRoundKey)
        return pool.first { $0.lastPathComponent == pickedName }
    }
}
