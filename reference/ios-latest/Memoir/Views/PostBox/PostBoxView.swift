import SwiftUI
import SwiftData
import UIKit

/// 邮筒 —— 寄信的地方（主动）。
///
/// ## 设定（2026-09-14 定，2026-10-11 重做）
///
/// 整页就是一个邮筒。下面一叠「这次寄出的日记」（上次寄信之后新写的），
/// 默认全勾，取消勾选的这次不寄 —— **服务器只收到勾上的那几篇**。
///
/// 把那叠信往上推进投信口 = 投信（2026-10-20 起；原来是点邮筒，拿邮筒玩时容易误触）：
/// 日记收进信封（会员盖上自己的火漆）→ 推进投信口（`LetterPostingFlight`，配震动和纸声 `LetterPostingFeel`）。
/// 邮筒左右拨得转、上下拨得晃，点一下是「戳」（`MailboxStage`）。**投进去就算寄出，不用等 AI**：信在后台写
/// （`LetterOutbox`），写不出来会悄悄重试，实在不行退回邮筒页。回信 6 小时 ~ 3 天后随机到达信箱，
/// 到了弹通知（`LetterDelivery`）。
///
/// - 寄出后留一枚邮戳（日期 + 日记里记的地点）和「在路上」
/// - 寄信贴邮票（2026-10-16 起取代来信节奏）：邮票用完了一进页面就先说明，不等点了再拒（`GET /me/stamps`）
/// - 右上角是信箱入口，有未读就带红点
/// - 左上角「笔友」、那叠日记信纸抬头的「寄给」都打开世界笔友地图（`WorldMapPage`，2026-10-15 定）：
///   在地图上看笔友住哪儿、挑这次寄给谁。寄给几位就落几封信（各自贴邮票、各自按路程到达）。
///   世界笔友只能寄服务端备好人设的那几位（`GET /penpals`）；总开关是 `PenPalRoster.canSendToWorldPenPals`
///
/// 邮筒图由主题提供（`AppTheme.mailboxImageName`），每个主题一个。
struct PostBoxView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    @Query(sort: \Letter.generatedAt, order: .reverse) private var letters: [Letter]
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]

    /// 当前笔友名（用户在 Onboarding/设置页改，AppStorage 共享 key）
    @AppStorage(PenPalName.storageKey) private var penPalName: String = ""

    /// 为 true 时直接推出信箱 —— 点「回信到了」通知时由外面置位
    @Binding var openLetterbox: Bool

    /// 「此刻」，每隔几秒推进 —— 在路上的信到点了，右上角红点要自己亮起来
    @State private var now = Date.now
    /// 这一叠里取消勾选的
    @State private var excluded: Set<UUID> = []
    /// 正在投的这一封（投信动画放完就清掉）
    @State private var posting: PostingRun?
    /// 服务端说现在能不能寄。问不到（没登录、断网）就是 nil，当作能寄 —— 最终由服务端拦
    /// 邮票夹（服务端说了算）。问不到（没登录、断网、老服务端）就是 nil，当作能寄 —— 最终由服务端拦
    @State private var stamps: StampWallet?
    /// 每周领邮票的小卡片（`StampPackCard`）。nil = 不显示
    @State private var stampPack: StampPackCard.Phase?
    /// 新手指引（`FirstStep`）：⑤ 指那叠信、⑧ 回信到了指「信箱」。两处在哪（全局坐标）
    @AppStorage(FirstStep.storageKey) private var firstStepRaw = 0
    @AppStorage(FirstStep.replyFromKey) private var firstReplyFrom = ""
    @State private var letterboxFrame: CGRect = .zero
    @State private var pileFrame: CGRect = .zero
    @State private var slotFrame: CGRect = .zero
    @State private var showLogin = false
    /// 服务端已经备好人设、现在能寄的世界笔友
    @State private var availablePenPals: Set<String> = []
    @State private var feel = LetterPostingFeel()
    /// 你大概在哪：世界笔友地图上的「你」、信要走多远、地图是白天还是夜里（只在本机用，不上传）
    @State private var location = ApproximateLocation()
    /// 打开世界笔友地图
    @State private var showWorldMap = false
    /// 这次寄给谁（笔友 id，逗号隔开），记住上一次的选择。自己起名的那位是 `WorldMapPage.ownID`
    @AppStorage("postRecipients") private var recipientsStorage = WorldMapPage.ownID

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
                    liftPreview: PostingRun(items: outgoingItems, excluded: excluded, recipients: recipientNames,
                                            hasSeal: store.isMember, sealMark: WaxSeal.initial(of: env.session.user?.displayName)),
                    canPost: canPost,
                    pileScrolls: OutgoingPile.scrolls(outgoingItems.count),
                    onPoke: poke,
                    onPost: postIfReady,
                    onSlotFrame: { slotFrame = $0 }
                ) {
                    bottom
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pileFrame = $0 }
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
                ToolbarItem(placement: .topBarLeading) {
                    penPalsButton(theme: theme)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    letterboxButton(theme: theme)
                }
            }
            .navigationDestination(isPresented: $openLetterbox) {
                LetterboxView()
            }
            .navigationDestination(isPresented: $showWorldMap) {
                WorldMapPage(
                    roster: PenPalRoster.all,
                    ownPenPalName: PenPalName.display(penPalName),
                    location: location,
                    isMember: store.isMember,
                    sendable: sendablePenPals,
                    recipients: recipientsBinding,
                    stampBalance: stamps?.balance
                )
            }
        }
        .overlay { guideOverlay(theme: theme) }
        .animation(.easeOut(duration: 0.3), value: firstStepRaw)
        .sheet(isPresented: $showLogin) { LoginView() }
        // 这周的邮票到了：领取的小卡片。挂在导航外面，遮罩连顶栏一起压暗
        .overlay {
            if let phase = stampPack {
                ZStack {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    StampPackCard(phase: phase, theme: theme, ink: postmarkInk, paper: palette.paper,
                                  onClaim: claimStampPack,
                                  onLater: { withAnimation(.easeOut(duration: 0.25)) { stampPack = nil } })
                        .transition(.opacity.combined(with: .offset(y: 14)))
                }
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
        .task(id: StampsKey(sent: sentLetterCount, loggedIn: env.session.isLoggedIn)) {
            await refreshStamps()
        }
        // 新手指引：④ 来了邮筒 → ⑤ 指那叠信
        .onAppear { FirstStep.advance(to: .pushPile, from: [.sendFirst]) }
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
        /// 邮票不够这次寄的
        case noStamps(StampWallet)
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
        if let stamps, stamps.balance < postageNeeded, !stamps.packReady { return .noStamps(stamps) }
        if !entriesToSend.isEmpty { return .ready }
        if latestInTransit != nil { return .inTransit }
        return entries.isEmpty ? .noEntries : .nothingNew
    }

    private var statusText: Text {
        // 投信动画放的时候，状态行先不变，信进了邮筒再换；练习投信时一直是这句
        if posting != nil || practicing { return Text("把勾上的日记推进投信口，寄给\(recipientNames)") }
        switch situation {
        case .returned: return Text("有一封信没能寄出去")
        case .notLoggedIn: return Text("登录之后，\(PenPalName.display(penPalName))才能给你回信")
        case .justPosted:
            return entriesToSend.isEmpty ? Text("信已经投进邮筒了") : Text("上一封信刚寄出，过一会儿再寄下一封")
        case .noStamps(let wallet):
            return Text("邮票用完了，新的一包\(wallet.nextPackAt.formatted(.relative(presentation: .named).locale(locale)))送到")
        case .ready:
            return checkedEntries.isEmpty ? Text("一篇都没勾，信封里是空的") : Text("把勾上的日记推进投信口，寄给\(recipientNames)")
        case .inTransit: return Text("已寄出，写了新日记可以再来寄")
        case .nothingNew: return Text("上次寄信之后还没写新日记，先写点什么再寄吧")
        case .noEntries: return Text("先写几篇日记，再来寄信吧")
        }
    }

    // MARK: - 下面那块

    /// 下面那块**不空着**（2026-10-16 产品定）：没有退信、没有刚寄出的邮戳时，就摆着那一叠信纸 ——
    /// 一篇新日记都没有也摆一张空的，写一篇多一行，像桌上一直放着一页没写完的信
    @ViewBuilder
    private var bottom: some View {
        if practicing {
            pile
        } else {
            situationBottom
        }
    }

    @ViewBuilder
    private var situationBottom: some View {
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
        case .noStamps where latestInTransit == nil:
            // 这周寄不了，新写的先摆着，下次一起寄
            OutgoingPile(palette: palette, items: outgoingItems, excluded: $excluded, recipients: recipientNames,
                         interactive: false)
                .opacity(0.5)
        default:
            if case .ready = situation {
                pile
            } else if let letter = latestInTransit {
                InTransitNote(
                    sentAt: letter.generatedAt,
                    place: Postmark.place(from: liveEntries(of: letter).map(\.locationInfo)),
                    ink: postmarkInk,
                    hasOthers: inTransitCount > 1
                )
            } else {
                pile
            }
        }
    }

    /// 那一叠信纸：有新日记就一行一篇，没有就是一页空格线。抬头的「寄给」随时能点开地图挑收件人
    private var pile: some View {
        OutgoingPile(palette: palette, items: outgoingItems, excluded: $excluded, recipients: recipientNames,
                     onTapRecipients: { showWorldMap = true })
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
        letters.filter { LetterDelivery.isRealLetter($0) && !$0.isWelcome }.count
    }

    /// 上次寄信的时刻。写好的信、还在写的信都算；退回来的不算（那几篇还没寄出去）
    private var lastSentAt: Date? {
        // Sinara 的欢迎信不是寄出去换来的回信，不算
        letters.filter { (LetterDelivery.isRealLetter($0) || LetterOutbox.isQueued($0)) && !$0.isWelcome }.map(\.generatedAt).max()
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

    // MARK: - 收件人

    /// 现在能寄的世界笔友：服务端备好人设的那几位（总开关 `canSendToWorldPenPals` 关着时一个都没有）
    private var sendablePenPals: Set<String> {
        PenPalRoster.canSendToWorldPenPals ? availablePenPals : []
    }

    /// 这次寄给谁。寄不了的世界笔友（没放开、服务端没备好、不是会员）去掉；一位都不剩时退回自己那位
    private var recipients: Set<String> {
        let ids = Set(recipientsStorage.split(separator: ",").map(String.init)).filter { id in
            id == WorldMapPage.ownID || (store.isMember && sendablePenPals.contains(id))
        }
        return ids.isEmpty ? [WorldMapPage.ownID] : ids
    }

    /// 这次要贴几张：一位一张，南极两张
    private var postageNeeded: Int {
        recipients.reduce(0) { sum, id in
            sum + (id == WorldMapPage.ownID ? 1 : (PenPalRoster.penPal(id: id)?.postage ?? 1))
        }
    }

    private var recipientsBinding: Binding<Set<String>> {
        Binding(
            get: { recipients },
            set: { recipientsStorage = $0.sorted().joined(separator: ",") }
        )
    }

    /// 「阿远」「阿远、天野和 McRae」
    private var recipientNames: String {
        WorldMapPage.names(of: recipients, ownPenPalName: PenPalName.display(penPalName), roster: PenPalRoster.all, locale: locale)
    }

    // MARK: - 世界笔友入口

    private func penPalsButton(theme: any AppTheme) -> some View {
        Button {
            showWorldMap = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: globeSymbol)
                Text("笔友")
            }
            .font(theme.captionFont)
            .foregroundStyle(theme.textPrimary)
        }
        .accessibilityLabel(Text("笔友地图"))
    }

    /// 地球图标朝着你那一面：亚洲、欧非、美洲（不知道你在哪就是亚洲那一面）
    private var globeSymbol: String {
        guard let longitude = location.coordinate?.longitude else { return "globe.asia.australia" }
        switch longitude {
        case -30..<60: return "globe.europe.africa"
        case -180 ..< -30: return "globe.americas"
        default: return "globe.asia.australia"
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { letterboxFrame = $0 }
    }

    // MARK: - 投信

    /// 这会儿能寄：有勾上的日记、邮票够、没在投
    private var canPost: Bool {
        // 练习投信：随时能推（推的是一叠画，什么都不寄）
        if practicing { return posting == nil }
        guard posting == nil, case .ready = situation else { return false }
        return !checkedEntries.isEmpty
    }

    /// 测试包在练习投信（见 `LetterDelivery.practicePosting`）
    private var practicing: Bool {
        return LetterDelivery.practicePosting
    }

    /// 点了一下邮筒：戳，翻板「哐」地落回去（2026-10-16 起戳着玩；2026-10-20 起点邮筒**只是戳**，不再投信）
    private func poke() {
        // 投信动画还在放：不理，也不震
        guard posting == nil else { return }
        feel.playPoke()
    }

    /// 寄：信封合上后松手 / 推到了投信口（读屏点邮筒也走这里）。
    /// `start` = 投信动画从时间轴的哪一刻接着放：推着寄的，信封在推的途中已经装到了这一刻；读屏寄的是 0（从头放）
    private func postIfReady(from start: Double) {
        guard canPost else { return }
        if practicing {
            practicePost(from: start)
        } else {
            post(from: start)
        }
    }

    private func post(from start: Double) {
        let toSend = checkedEntries
        let items = outgoingItems
        let skipped = excluded
        let sealed = store.isMember
        // 信推进投信口的这一刻 = 寄出时刻，到达时刻从这里起算
        let sentAt = Date.now

        // 投进去就算寄出：**寄给几位就落几封「写信中」的信**，各自在后台写（`LetterOutbox`）、各自按路程到达
        let ownID = WorldMapPage.ownID
        let worldIDs = PenPalRoster.all.map(\.id).filter { recipients.contains($0) }
        var created: [Letter] = []
        func makeLetter(fromCharacter: String) -> Letter {
            let letter = Letter(
                relatedEntries: toSend,
                status: .generating,
                body: "",
                fromCharacter: fromCharacter,
                // 写信当刻的昵称快照；没登录 / 没设昵称时是 nil，抬头退回只写「致」
                toName: env.session.user?.displayName,
                triggerKind: .weekly
            )
            // 信纸也在寄出这一刻定下：会员寄出的是火漆信，以后停了会员也不变
            letter.stationery = Letter.stationery(isMember: sealed)
            letter.generatedAt = sentAt
            return letter
        }
        if recipients.contains(ownID) {
            // 自己起名的那位没有住址，就在身边：几个小时就回（2026-10-15 定）
            let letter = makeLetter(fromCharacter: PenPalName.display(penPalName))
            letter.postage = 1
            letter.deliveredAt = PenPalTravel.arrivalDate(sentAt: sentAt, replyTime: .ownPenPal, timeScale: LetterDelivery.debugTimeScale)
            created.append(letter)
        }
        for id in worldIDs {
            guard let penPal = PenPalRoster.penPal(id: id) else { continue }
            // 署名用寄出这一刻的姓（按 App 语言），以后换语言也不变 —— 同 `fromCharacter` 的快照语义
            let letter = makeLetter(fromCharacter: penPal.surname.resolved(for: appLocale))
            letter.penPalID = id
            letter.postage = penPal.postage
            letter.deliveredAt = PenPalTravel.arrivalDate(
                sentAt: sentAt,
                replyTime: PenPalTravel.replyTime(to: penPal, from: location.coordinate),
                timeScale: LetterDelivery.debugTimeScale
            )
            created.append(letter)
        }
        created.forEach(modelContext.insert)
        do {
            try modelContext.save()
        } catch {
            created.forEach(modelContext.delete)
            env.errors.present(error, fallback: NSLocalizedString(
                "没能寄出，稍后再试", bundle: .appLanguage, comment: "寄信失败"))
            return
        }
        created.forEach { LetterOutbox.enqueue($0.id) }
        excluded = []
        // 新手指引 ⑥：第一封寄出去了，投信动画放完再说一声「会有回信」
        let guideFinale = { FirstStep.advance(to: .sent, from: [.sendFirst, .pushPile]) }

        if reduceMotion {
            feel.playQuiet()
            guideFinale()
            Task { await LetterNotifications.requestAuthorizationIfNeeded() }
        } else {
            playPosting(items: items, excluded: skipped, sealed: sealed, from: start) {
                guideFinale()
                // 第一次寄信之后才问通知权限 —— 这时用户最明白「为什么要通知」。
                // 放在动画之后：系统弹窗不该把投信打断
                Task { await LetterNotifications.requestAuthorizationIfNeeded() }
            }
        }

        Task { await processOutbox() }
    }

    /// 练习投信（测试包，`LetterDelivery.practicePosting`）：只放动画、声音和震动，不建信、不调接口，那叠信也不收走
    private func practicePost(from start: Double) {
        let sealed = store.isMember
        // 测试包练习投信也算寄出（测试的人不用真寄一封、没登录也能往下走；练习投信不会有回信，回信那几步要真寄才看得到）
        let guideFinale = { FirstStep.advance(to: .sent, from: [.sendFirst, .pushPile]) }
        if reduceMotion {
            feel.playQuiet()
            guideFinale()
            return
        }
        playPosting(items: outgoingItems, excluded: excluded, sealed: sealed, from: start) { guideFinale() }
    }

    /// 投信动画：信收进信封、推进投信口，配震动和声音（`LetterPostingFeel`）。正式寄信和练习投信共用。
    /// 推着寄的从 `start`（信封在推的途中装到的那一刻）接着放，只放后半截的声音；读屏寄的从头放
    private func playPosting(items: [OutgoingItem], excluded: Set<UUID>, sealed: Bool, from start: Double,
                             completion: @escaping () -> Void) {
        posting = PostingRun(items: items, excluded: excluded, recipients: recipientNames, hasSeal: sealed,
                             sealMark: WaxSeal.initial(of: env.session.user?.displayName), t: start)
        Task { @MainActor in
            // 🔴 先让起点那一帧画出来再推进：浮层插入和推进放在同一帧里，SwiftUI 会直接画终点
            // （2026-10-11 录屏发现动画整个没播）
            try? await Task.sleep(for: .milliseconds(30))
            if start > 0 {
                feel.playTail(sealed: sealed, from: start)
            } else {
                feel.play(sealed: sealed)
            }
            withAnimation(.linear(duration: max(0.1, LetterPostingTimeline.total - start))) {
                posting?.t = LetterPostingTimeline.total
            } completion: {
                posting = nil
                completion()
            }
        }
    }

    private func processOutbox() async {
        await LetterOutbox.process(context: modelContext, ai: env.ai, session: env.session,
                                   isMember: store.isMember, errors: env.errors)
    }

    /// 问一下邮票夹；新的一包到了、邮票夹又没满，就浮出领取的小卡片（`StampPackCard`）。顺便问现在能寄哪几位世界笔友。
    /// 不点「领取」也不耽误寄信：寄的时候服务端会把到期的那一包补上
    private func refreshStamps() async {
        guard env.session.isLoggedIn else {
            stamps = nil
            return
        }
        do {
            let wallet = try await env.ai.fetchStamps()
            stamps = wallet
            // 新手指引还在看信、写第一篇的那几步：先不弹，两张卡叠在一起会乱
            let guideBusy = FirstStep.beforeSending.contains(FirstStep.current) || FirstStep.current == .sendFirst
            if wallet.packReady, wallet.balance < wallet.cap, stampPack == nil, !guideBusy {
                withAnimation(.easeOut(duration: 0.35)) { stampPack = .ready }
            }
        } catch {
            // 只是提前问一声：问不到就照常让用户寄，最终由服务端拦（拦下了信会退回并说明原因）
            let ns = error as NSError
            NSLog("⚠️ [PostBox] 查邮票夹失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        }
        guard PenPalRoster.canSendToWorldPenPals else { return }
        do {
            availablePenPals = try await env.ai.fetchAvailablePenPals()
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [PostBox] 查世界笔友失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        }
    }

    /// 新手指引在邮筒页的几步
    @ViewBuilder
    private func guideOverlay(theme: any AppTheme) -> some View {
        switch FirstStep(rawValue: firstStepRaw) {
        case .replyArrived where letterboxFrame != .zero && !openLetterbox:
            GuideHint(text: "\(firstReplyFrom)的回信到了，\n点开「信箱」看看", target: letterboxFrame, below: true, theme: theme)
        case .pushPile where posting == nil && !showWorldMap && !openLetterbox:
            if !env.session.isLoggedIn && !practicing {
                VStack {
                    Spacer()
                    GuideCard(text: "登录之后，就能把日记寄给笔友", button: "去登录", theme: theme) { showLogin = true }
                        .padding(.bottom, 120)
                }
            } else if pileFrame != .zero {
                // 只留呼吸的上滑箭头（用户 10-27：这一步不要提示框）：从那叠信一路往上走到邮筒的投信口、淡掉，再来一遍
                GeometryReader { proxy in
                    let origin = proxy.frame(in: .global).origin
                    let path = slotFrame == .zero
                        ? pileFrame
                        : CGRect(x: pileFrame.midX - 20, y: slotFrame.maxY,
                                 width: 40, height: max(pileFrame.midY - slotFrame.maxY, 1))
                    // 邮筒页底是深色（皮革、极夜）时用浅色箭头，不然墨色压在深底上看不见
                    GestureCue(kind: .swipeUp, envelope: path.offsetBy(dx: -origin.x, dy: -origin.y),
                               color: pageIsDark ? Color(white: 0.96) : palette.ink,
                               travel: slotFrame == .zero ? 0.75 : 0.85, arrowLength: 80)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        default:
            EmptyView()
        }
    }

    /// 点了「领取」：领这一包 →「+N」停一下再收起
    private func claimStampPack() {
        let before = stamps?.balance ?? 0
        stampPack = .claiming
        Task {
            do {
                let wallet = try await env.ai.claimStamps()
                stamps = wallet
                withAnimation(.easeInOut(duration: 0.3)) { stampPack = .claimed(max(0, wallet.balance - before)) }
                try await Task.sleep(for: .seconds(1.4))
                withAnimation(.easeOut(duration: 0.35)) { stampPack = nil }
            } catch is CancellationError {
                stampPack = nil
            } catch {
                let ns = error as NSError
                NSLog("⚠️ [PostBox] 领邮票失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
                stampPack = .ready
                env.errors.present(error, fallback: NSLocalizedString(
                    "邮票没领到，过一会儿再试", bundle: .appLanguage, comment: "每周领邮票：领取失败"))
            }
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

/// 邮票夹要重新问服务端的时机：写好的信数变了、登录状态变了
private struct StampsKey: Equatable {
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
