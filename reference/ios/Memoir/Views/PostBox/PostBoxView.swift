import SwiftUI
import SwiftData
import UIKit

/// 邮筒 —— 寄信的地方（主动）。
///
/// ## 设定（2026-09-14 定，2026-10-11 重做）
///
/// 整页就是一个邮筒，**邮筒本身是按钮**。下面一叠「这次寄出的日记」（上次寄信之后新写的），
/// 默认全勾，取消勾选的这次不寄 —— **服务器只收到勾上的那几篇**。
///
/// 点邮筒 = 投信：日记收进信封（会员盖上自己的火漆）→ 推进投信口（`LetterPostingFlight`，
/// 配震动和纸声 `LetterPostingFeel`）。**投进去就算寄出，不用等 AI**：信在后台写
/// （`LetterOutbox`），写不出来会悄悄重试，实在不行退回邮筒页。回信 6 小时 ~ 3 天后随机到达信箱，
/// 到了弹通知（`LetterDelivery`）。
///
/// - 寄出后留一枚邮戳（日期 + 日记里记的地点）和「在路上」
/// - 这周已经寄过（免费）/ 今天已经寄过（会员）的，一进页面就先说明，不等点了再拒（`GET /me/rhythm`）
/// - 右上角是信箱入口，有未读就带红点
///
/// 邮筒图由主题提供（`AppTheme.mailboxImageName`），每个主题一个。
struct PostBoxView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Letter.generatedAt, order: .reverse) private var letters: [Letter]
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]

    /// 当前笔友名（用户在 Onboarding/设置页改，AppStorage 共享 key）
    @AppStorage("penPalName") private var penPalName: String = "青鸟"

    /// 为 true 时直接推出信箱 —— 点「回信到了」通知时由外面置位
    @Binding var openLetterbox: Bool

    /// 「此刻」，每隔几秒推进 —— 在路上的信到点了，右上角红点要自己亮起来
    @State private var now = Date.now
    /// 这一叠里取消勾选的
    @State private var excluded: Set<UUID> = []
    /// 正在投的这一封（投信动画放完就清掉）
    @State private var posting: PostingRun?
    /// 服务端说现在能不能寄。问不到（没登录、断网）就是 nil，当作能寄 —— 最终由服务端拦
    @State private var rhythm: LetterRhythm?
    @State private var feel = LetterPostingFeel()

    /// 邮筒图边角的颜色，当整页底色 —— 图不带透明底，底色差一点就会看出一个框
    @State private var pageColor: Color?
    /// 底色是不是深色，决定状态栏用白字还是黑字
    @State private var pageIsDark = false

    init(openLetterbox: Binding<Bool>) {
        _openLetterbox = openLetterbox
    }

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            ZStack {
                (pageColor ?? theme.background).ignoresSafeArea()

                PostBoxPage(
                    mailboxImageName: theme.mailboxImageName,
                    palette: palette,
                    status: statusText,
                    posting: posting,
                    onTapMailbox: tapMailbox
                ) {
                    bottom
                }
            }
            // 🔴 导航栏背景**设为可见、但填成和页面一模一样的颜色**，而不是 `.hidden`。
            // 用 `.hidden` 时系统拿不到栏的深浅，状态栏退回默认黑字 ——
            // 皮革主题深色底上时间和电量几乎看不见（2026-09-14 截图发现）。
            // 填同色后看起来和隐藏无异，再由 toolbarColorScheme 指定状态栏配色
            .toolbarBackground(pageColor ?? theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(pageIsDark ? .dark : .light, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    letterboxButton(theme: theme)
                }
            }
            .navigationDestination(isPresented: $openLetterbox) {
                LetterboxView()
            }
        }
        .task(id: theme.mailboxImageName) {
            let corner = UIImage(named: theme.mailboxImageName)?.cornerColor
            pageColor = corner.map(Color.init)
            pageIsDark = corner.map { c in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getRed(&r, green: &g, blue: &b, alpha: &a)
                return 0.299 * r + 0.587 * g + 0.114 * b < 0.5
            } ?? false
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                now = .now
            }
        }
        // 进邮筒就补领一次（服务端有、本机没有的信在这里落地），再把没寄完的接着寄
        .task {
            // 先问清是不是测试包（TestFlight 的「回信加速」要靠它），寄信和补领算到达时刻都要用
            await LetterDelivery.detectTestBuild()
            await LetterOutbox.reconcile(context: modelContext, ai: env.ai, session: env.session,
                                         isMember: store.isMember, errors: env.errors)
            await processOutbox()
        }
        // 能不能寄，问服务端。寄出、信写好、登录状态变了都重新问
        .task(id: RhythmKey(sent: sentLetterCount, loggedIn: env.session.isLoggedIn)) {
            await refreshRhythm()
        }
        // 先把震动引擎热起来，点下去那一刻才不会慢半拍
        .onAppear { feel.prepare() }
        .onDisappear { feel.stop() }
    }

    private var palette: LetterPalette { LetterPalette.of(themeID: themeManager.currentThemeID) }
    private var postmarkInk: Color { Postmark.ink(themeID: themeManager.currentThemeID) }

    // MARK: - 此刻的状况

    /// 邮筒页此刻是什么情况。按顺序判断，先命中先算
    private enum Situation {
        /// 有一封退回来了，等用户决定
        case returned(Letter)
        case notLoggedIn
        /// 刚投了一封、还在写（本机负责的）
        case justPosted
        /// 服务端说这会儿不能寄
        case blocked(LetterRhythm)
        /// 有新日记可寄
        case ready
        /// 寄过了、还在路上，也没有新日记
        case inTransit
        case nothingNew
        case noEntries
    }

    private var situation: Situation {
        if let letter = returnedLetters.first { return .returned(letter) }
        if !env.session.isLoggedIn { return .notLoggedIn }
        if letters.contains(where: { LetterOutbox.isQueued($0) && LetterOutbox.owns($0.id) }) { return .justPosted }
        if let rhythm, !rhythm.canRequestNow { return .blocked(rhythm) }
        if !entriesToSend.isEmpty { return .ready }
        if latestInTransit != nil { return .inTransit }
        return entries.isEmpty ? .noEntries : .nothingNew
    }

    private var statusText: Text {
        // 投信动画放的时候，状态行先不变，信进了邮筒再换
        if posting != nil { return Text("点邮筒，把勾上的日记寄给\(penPalName)") }
        switch situation {
        case .returned: return Text("有一封信没能寄出去")
        case .notLoggedIn: return Text("登录之后，\(penPalName)才能给你回信")
        case .justPosted:
            return entriesToSend.isEmpty ? Text("信已经投进邮筒了") : Text("上一封信刚寄出，过一会儿再寄下一封")
        case .blocked(let rhythm): return rhythmText(rhythm)
        case .ready:
            return checkedEntries.isEmpty ? Text("一篇都没勾，信封里是空的") : Text("点邮筒，把勾上的日记寄给\(penPalName)")
        case .inTransit: return Text("已寄出，写了新日记可以再来寄")
        case .nothingNew: return Text("上次寄信之后还没写新日记，先写点什么再寄吧")
        case .noEntries: return Text("先写几篇日记，再来寄信吧")
        }
    }

    /// 服务端拦着时提前说清楚。**不用「额度 / 剩余 N 封」这类计量词**（定价文档 §5.1）
    private func rhythmText(_ rhythm: LetterRhythm) -> Text {
        switch rhythm.reason {
        case "daily_cap": return Text("今天的信已经寄出了，明天再来寄吧")
        case "monthly_cap": return Text("这个月\(penPalName)已经回过几封了，下个月再来寄吧")
        case "welcome_pending": return Text("你的第一封信已经寄出了，\(penPalName)正在读")
        default: return Text("这周的信已经寄出了。\(penPalName)习惯每周回一次，下周再来寄吧")
        }
    }

    // MARK: - 下面那块

    @ViewBuilder
    private var bottom: some View {
        switch situation {
        case .returned(let letter):
            ReturnedLetterCard(
                palette: palette,
                ink: postmarkInk,
                sentAt: letter.generatedAt,
                reason: letter.errorMessage,
                onResend: { resend(letter) },
                onDiscard: { discard(letter) }
            )
        case .ready:
            OutgoingPile(palette: palette, items: outgoingItems, excluded: $excluded)
        case .blocked where latestInTransit == nil && !entriesToSend.isEmpty:
            // 这周寄不了，新写的先摆着，下次一起寄
            OutgoingPile(palette: palette, items: outgoingItems, excluded: $excluded, interactive: false)
                .opacity(0.5)
        default:
            if let letter = latestInTransit {
                InTransitNote(
                    sentAt: letter.generatedAt,
                    place: Postmark.place(from: liveEntries(of: letter).map(\.locationInfo)),
                    ink: postmarkInk,
                    hasOthers: inTransitCount > 1
                )
            }
        }
    }

    // MARK: - 信

    /// 在路上的信：本机投了还在写的，和写好了还没到的
    private var inTransitLetters: [Letter] {
        letters.filter {
            (LetterOutbox.isQueued($0) && LetterOutbox.owns($0.id)) || LetterDelivery.isInTransit($0, now: now)
        }
    }

    private var latestInTransit: Letter? { inTransitLetters.first }
    private var inTransitCount: Int { inTransitLetters.count }

    /// 退回来的信（本机投的、寄不出去的），最近的在前
    private var returnedLetters: [Letter] {
        letters.filter { LetterOutbox.isReturned($0) }
    }

    /// 已经寄出的信数（写好了的）。变了就重新问服务端能不能寄
    private var sentLetterCount: Int {
        letters.filter { LetterDelivery.isRealLetter($0) }.count
    }

    /// 上次寄信的时刻。写好的信、还在写的信都算；退回来的不算（那几篇还没寄出去）
    private var lastSentAt: Date? {
        letters.filter { LetterDelivery.isRealLetter($0) || LetterOutbox.isQueued($0) }.map(\.generatedAt).max()
    }

    /// 日记删了的话关系里会留下悬空的引用（见 `Letter.relatedEntries` 的注释），先滤掉
    private func liveEntries(of letter: Letter) -> [JournalEntry] {
        (letter.relatedEntries ?? [])
            .filter { !$0.isDeleted && $0.modelContext != nil }
            .sorted { $0.date > $1.date }
    }

    /// 这次要寄的日记：上次寄信之后新写的（退回来那封里的除外，它们等用户决定）。
    ///
    /// 按 `createdAt`（真正写下的时刻）判断，不按 `date` —— `date` 是用户可以改的日记日期，
    /// 补记一篇上周的日记也应该算「新写的」
    private var entriesToSend: [JournalEntry] {
        let held = Set(returnedLetters.flatMap { liveEntries(of: $0).map(\.id) })
        let fresh = (lastSentAt.map { last in entries.filter { $0.createdAt > last } } ?? entries)
            .filter { !held.contains($0.id) }
        return Array(fresh.prefix(LetterDelivery.maximumEntriesPerLetter))
    }

    /// 勾上的那几篇
    private var checkedEntries: [JournalEntry] {
        entriesToSend.filter { !excluded.contains($0.id) }
    }

    private var outgoingItems: [OutgoingItem] {
        entriesToSend.map { entry in
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = entry.content.split(whereSeparator: \.isNewline).first
                .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            return OutgoingItem(id: entry.id, date: entry.date, title: title.isEmpty ? String(firstLine.prefix(30)) : title)
        }
    }

    // MARK: - 信箱入口

    private var hasUnread: Bool {
        letters.contains { LetterDelivery.isUnread($0, now: now) }
    }

    private func letterboxButton(theme: any AppTheme) -> some View {
        Button {
            openLetterbox = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tray")
                Text("信箱")
            }
            .font(theme.captionFont)
            .foregroundStyle(theme.textPrimary)
            .overlay(alignment: .topTrailing) {
                if hasUnread {
                    Circle()
                        .fill(theme.destructive)
                        .frame(width: 8, height: 8)
                        .offset(x: 6, y: -4)
                }
            }
        }
        .accessibilityLabel(hasUnread ? Text("信箱，有新的回信") : Text("信箱"))
    }

    // MARK: - 投信

    private func tapMailbox() {
        // 投信动画还在放：不理，也不震 —— 否则像是又寄了一封
        guard posting == nil else { return }
        guard case .ready = situation, !checkedEntries.isEmpty else {
            // 邮筒这会儿不收：状态行已经写着为什么，手上轻轻一顿
            feel.playRefused()
            return
        }
        post()
    }

    private func post() {
        let toSend = checkedEntries
        let items = outgoingItems
        let skipped = excluded
        let sealed = store.isMember
        // 点下邮筒的这一刻 = 寄出时刻，到达时刻从这里起算
        let sentAt = Date.now

        // 投进去就算寄出：先落一封「写信中」的信，AI 在后台写（`LetterOutbox`）
        let letter = Letter(
            relatedEntries: toSend,
            status: .generating,
            body: "",
            fromCharacter: penPalName,
            // 写信当刻的昵称快照；没登录 / 没设昵称时是 nil，抬头退回只写「致」
            toName: env.session.user?.displayName,
            triggerKind: .weekly
        )
        // 信纸也在寄出这一刻定下：会员寄出的是火漆信，以后停了会员也不变
        letter.stationery = Letter.stationery(isMember: sealed)
        letter.generatedAt = sentAt
        letter.deliveredAt = LetterDelivery.arrivalDate(sentAt: sentAt, timeScale: LetterDelivery.debugTimeScale)
        modelContext.insert(letter)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(letter)
            env.errors.present(error, fallback: NSLocalizedString(
                "没能寄出，稍后再试", bundle: .appLanguage, comment: "寄信失败"))
            return
        }
        LetterOutbox.enqueue(letter.id)
        excluded = []

        if reduceMotion {
            feel.playQuiet()
            Task { await LetterNotifications.requestAuthorizationIfNeeded() }
        } else {
            posting = PostingRun(items: items, excluded: skipped, hasSeal: sealed,
                                 sealMark: WaxSeal.initial(of: env.session.user?.displayName))
            Task { @MainActor in
                // 🔴 先让 t = 0 的那一帧画出来再推进：浮层插入和推进放在同一帧里，SwiftUI 会直接画终点
                // （2026-10-11 录屏发现动画整个没播）
                try? await Task.sleep(for: .milliseconds(30))
                feel.play(sealed: sealed)
                withAnimation(.linear(duration: LetterPostingTimeline.total)) {
                    posting?.t = LetterPostingTimeline.total
                } completion: {
                    posting = nil
                    // 第一次寄信之后才问通知权限 —— 这时用户最明白「为什么要通知他」。
                    // 放在动画之后：系统弹窗不该把投信打断
                    Task { await LetterNotifications.requestAuthorizationIfNeeded() }
                }
            }
        }

        Task { await processOutbox() }
    }

    private func processOutbox() async {
        await LetterOutbox.process(context: modelContext, ai: env.ai, session: env.session,
                                   isMember: store.isMember, errors: env.errors)
    }

    private func refreshRhythm() async {
        guard env.session.isLoggedIn else {
            rhythm = nil
            return
        }
        do {
            rhythm = try await env.ai.fetchRhythm()
        } catch {
            // 只是提前问一声：问不到就照常让用户寄，最终由服务端拦（拦下了信会退回并说明原因）
            let ns = error as NSError
            NSLog("⚠️ [PostBox] 查来信节奏失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        }
    }

    // MARK: - 退回来的信

    private func resend(_ letter: Letter) {
        do {
            try LetterOutbox.resend(letter, context: modelContext)
        } catch {
            env.errors.present(error, fallback: NSLocalizedString(
                "没能寄出，稍后再试", bundle: .appLanguage, comment: "寄信失败"))
            return
        }
        Task { await processOutbox() }
    }

    private func discard(_ letter: Letter) {
        do {
            try LetterOutbox.discard(letter, context: modelContext)
        } catch {
            env.errors.present(error, fallback: NSLocalizedString(
                "没能放回这几篇日记", bundle: .appLanguage, comment: "退信不寄了，写库失败"))
        }
    }
}

/// 能不能寄要重新问服务端的时机：写好的信数变了、登录状态变了
private struct RhythmKey: Equatable {
    let sent: Int
    let loggedIn: Bool
}

// MARK: - 取图片边角颜色

private extension UIImage {
    /// 左上角 1 个像素的颜色。邮筒图不带透明底，拿它当页面底色才能严丝合缝。
    /// 放在运行时取而不是写死色值：以后换图（同名覆盖）不用跟着改代码
    var cornerColor: UIColor? {
        guard let cg = cgImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // 把整张图画进 1×1 画布时只取左上角：先平移，让原图左上角那个像素落在画布上
        ctx.draw(cg, in: CGRect(x: 0, y: -CGFloat(cg.height) + 1, width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255,
                       blue: CGFloat(px[2]) / 255, alpha: 1)
    }
}
