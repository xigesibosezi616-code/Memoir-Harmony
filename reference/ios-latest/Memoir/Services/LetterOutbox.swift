import Foundation
import SwiftData
import UIKit
import UserNotifications

/// 寄出去、还没写好的信（2026-10-11 产品定：**投进邮筒就算寄出，不用等 AI**）。
///
/// ## 怎么运转
/// - 点下邮筒那一刻，本机就落一封「写信中」的 `Letter`：`status = generating`、正文空、
///   带着勾上的日记，寄出时刻、到达时刻、信纸都定好了。界面上它就是「在路上」
/// - 这里把它真的寄出去：调后端写信 → 填上正文、`status = pending`、预约到达通知
/// - 寄不出去时：
///   - **断网 / 超时不算失败**，过一会儿接着寄（App 在前台时 `ContentView` 每 30 秒叫一次 `process`）
///   - 服务端出错，隔 1 分钟、5 分钟再试；**连续 3 次**不成就退回
///   - 重试也没用的（内容审核没过、这周已经寄过、没登录）直接退回
///   - 退回 = `status = failed`、`errorMessage` 写原因，邮筒页让用户选「重新寄出 / 不寄了」
/// - App 被杀掉：信已经在库里，下次回到前台接着寄
///
/// ## 只有投信的那台设备负责寄
/// 写信中的 `Letter` 会经 iCloud 同步到用户的其他设备。哪些信归本机寄，记在**本机** UserDefaults
/// （`stateKey`），别的设备看到的只是一封写信中的信，不会再寄一次。
///
/// ## 寄到了服务端、回执却丢了
/// 服务端是「写好 → 入库 → 返回」，响应没回到本机时信其实已经写好、额度也扣了
/// （2026-09-17 两台真机都这么卡住过）。所以**重发之前先补领**（`reconcile`）：
/// 服务端有、本机没有、写信时刻在这封寄出之后的，就是它的回信，直接填进去，不再写第二封
enum LetterOutbox {

    /// 一封归本机寄的信的重试情况
    private struct Item: Codable {
        /// 发出去过几次请求。>0 说明服务端可能已经写好了，下次先补领再重发
        var attempts = 0
        /// 服务端连续出错几次（断网不算）
        var failures = 0
        /// 下次最早什么时候再试；nil = 随时
        var nextAttemptAt: Date?
    }

    private static let stateKey = "letterOutbox.v1"
    /// 服务端连续出错几次就退回
    private static let maxFailures = 3
    /// 补领时认「是这封的回信」容许的时钟误差（手机和服务器的钟不一定对得上）
    private static let clockSkew: TimeInterval = 300

    /// 正在跑一轮（同一时间只跑一轮，免得同一封信被发两次）
    private static var isProcessing = false

    // MARK: - 本机负责的信

    /// 内存里的一份。邮筒页每次重绘都要问好几次「这封归不归本机」，别每次都去解 JSON；
    /// 所有写入都经过 `saveState`，进程内始终一致
    private static var cached: [String: Item]?

    private static func loadState() -> [String: Item] {
        if let cached { return cached }
        guard let data = UserDefaults.standard.data(forKey: stateKey) else {
            cached = [:]
            return [:]
        }
        do {
            let state = try JSONDecoder().decode([String: Item].self, from: data)
            cached = state
            return state
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [LetterOutbox] 读取寄信状态失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            return [:]
        }
    }

    private static func saveState(_ state: [String: Item]) {
        cached = state
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(state), forKey: stateKey)
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [LetterOutbox] 保存寄信状态失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        }
    }

    private static func update(_ id: UUID, _ change: (inout Item) -> Void) {
        var state = loadState()
        var item = state[id.uuidString] ?? Item()
        change(&item)
        state[id.uuidString] = item
        saveState(state)
    }

    private static func forget(_ id: UUID) {
        var state = loadState()
        state[id.uuidString] = nil
        saveState(state)
    }

    /// 这封信归不归本机寄（写信中、退回来的都算）
    static func owns(_ id: UUID) -> Bool {
        loadState()[id.uuidString] != nil
    }

    /// 刚投进邮筒的一封，交给本机寄
    static func enqueue(_ id: UUID) {
        update(id) { $0 = Item() }
    }

    // MARK: - 信在哪个阶段

    /// 写信中：投进邮筒了，回信还没写好
    static func isQueued(_ letter: Letter) -> Bool {
        letter.status == LetterStatus.generating.rawValue && letter.body.isEmpty
    }

    /// 退回来的：寄不出去，等用户决定重新寄还是不寄了
    static func isReturned(_ letter: Letter) -> Bool {
        letter.status == LetterStatus.failed.rawValue && letter.body.isEmpty && owns(letter.id)
    }

    // MARK: - 退回之后

    /// 重新寄出：回到写信中，重试次数清零（之前发过请求的记着，先补领再重发）
    static func resend(_ letter: Letter, context: ModelContext) throws {
        letter.status = LetterStatus.generating.rawValue
        letter.errorMessage = nil
        letter.updatedAt = .now
        try context.save()
        update(letter.id) { item in
            item.failures = 0
            item.nextAttemptAt = nil
        }
    }

    /// 不寄了：本机不再管它，带着的日记放回「要寄的日记」里。
    /// 这条记录本身留着（正文是空的、状态是失败，哪儿都不显示），不删库里的东西
    static func discard(_ letter: Letter, context: ModelContext) throws {
        letter.relatedEntries = []
        letter.updatedAt = .now
        try context.save()
        forget(letter.id)
    }

    // MARK: - 寄

    /// 把本机负责、到了该试的时候的信一封封寄出去。随便叫，不会重复寄
    static func process(context: ModelContext, ai: AIService, session: UserSession,
                        isMember: Bool, errors: ErrorPresenter) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        // 一封寄完再找下一封：跑的过程中刚投进来的信也能接上
        var tried: Set<UUID> = []
        while let letter = nextDue(context: context, excluding: tried) {
            tried.insert(letter.id)
            await send(letter, context: context, ai: ai, session: session, isMember: isMember, errors: errors)
        }
    }

    private static func nextDue(context: ModelContext, excluding: Set<UUID>) -> Letter? {
        let state = loadState()
        guard !state.isEmpty else { return nil }
        let generating = LetterStatus.generating.rawValue
        let descriptor = FetchDescriptor<Letter>(
            predicate: #Predicate { $0.status == generating },
            sortBy: [SortDescriptor(\.generatedAt)]
        )
        let letters: [Letter]
        do {
            letters = try context.fetch(descriptor)
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [LetterOutbox] 读信失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            return nil
        }
        let now = Date.now
        return letters.first { letter in
            guard isQueued(letter), !excluding.contains(letter.id),
                  let item = state[letter.id.uuidString] else { return false }
            return (item.nextAttemptAt ?? .distantPast) <= now
        }
    }

    private static func send(_ letter: Letter, context: ModelContext, ai: AIService, session: UserSession,
                             isMember: Bool, errors: ErrorPresenter) async {
        let id = letter.id
        let item = loadState()[id.uuidString] ?? Item()

        // 之前发过请求：服务端可能已经写好了，先补领，领到了就不再写第二封
        if item.attempts > 0 {
            await reconcile(context: context, ai: ai, session: session, isMember: isMember, errors: errors)
            guard isQueued(letter) else { return }
        }

        guard session.isLoggedIn else {
            giveBack(letter, reason: AIServiceError.notLoggedIn.errorDescription, context: context, errors: errors)
            return
        }

        // 日记删了的话关系里会留下悬空的引用（见 `Letter.relatedEntries` 的注释），先滤掉
        let entries = (letter.relatedEntries ?? [])
            .filter { !$0.isDeleted && $0.modelContext != nil }
            .sorted { $0.date > $1.date }
        guard !entries.isEmpty else {
            giveBack(letter, reason: NSLocalizedString("要寄的日记都删掉了", bundle: .appLanguage, comment: "退信原因：信里的日记都被删了"),
                     context: context, errors: errors)
            return
        }

        // 主导情绪 = 这几篇里出现最多的那一档（九档的英文名，后端只拿它写提示词）；都没记心情就不给
        let levels = entries.compactMap(\.moodLevel)
        let dominantMood = Dictionary(grouping: levels, by: { $0 }).mapValues(\.count)
            .max(by: { $0.value < $1.value })?.key.englishName
        // 世界笔友走另一个接口（原文 + 译文 + 手记），见 `sendToWorldPenPal`
        if let penPalID = letter.penPalID {
            await sendToWorldPenPal(letter, penPalID: penPalID, entries: entries, dominantMood: dominantMood,
                                    context: context, ai: ai, session: session, isMember: isMember, errors: errors)
            return
        }

        let request = LetterContext(
            entries: entries.map(\.snapshot),
            triggerKind: .weekly,
            dominantMood: dominantMood,
            // 投信那一刻的笔友名，落库时就写在 fromCharacter 里了
            penPalName: letter.fromCharacter,
            // 同一封信服务端只写一次、只扣一张邮票：重发、补寄都不会多扣
            clientLetterID: letter.id,
            notebook: PenPalNotebook.snapshot(for: PenPalNote.ownID, context: context)
        )

        update(id) { $0.attempts += 1 }
        // 投完信马上切走 App 也来得及：向系统多要一点后台时间把这一封寄完（约 30 秒）
        let background = UIApplication.shared.beginBackgroundTask(withName: "letter-send")
        defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }

        do {
            let draft = try await ai.generateLetter(for: request)
            // 补领可能抢先一步填好了（同一封回信），就不用再填
            guard isQueued(letter) else { return }
            letter.body = draft.body
            letter.fromCharacter = draft.fromCharacter
            letter.status = LetterStatus.pending.rawValue
            letter.errorMessage = nil
            letter.updatedAt = .now
            if let edits = draft.notebook {
                PenPalNotebook.apply(edits, for: PenPalNote.ownID, at: .now, context: context)
            }
            do {
                try context.save()
            } catch {
                errors.present(error, fallback: NSLocalizedString(
                    "没能收下服务器上的回信", bundle: .appLanguage, comment: "回信写库失败"))
                return
            }
            forget(id)
            NSLog("ℹ️ [LetterOutbox] 寄出 id=%@ 第 %ld 次", id.uuidString, item.attempts + 1)
            await notifyArrival(of: letter)
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [LetterOutbox] 寄信失败 id=%@ domain=%@ code=%ld %@", id.uuidString, ns.domain, ns.code, "\(error)")
            await handle(error, letter: letter, context: context, ai: ai, session: session, isMember: isMember, errors: errors)
        }
    }

    /// 寄给一位世界笔友：带上他给你记的手记，回信写好了把原文、译文、危险标记、邮资填进这封信，
    /// 再照回执改手记（危险的那封服务端一条都不给）
    private static func sendToWorldPenPal(_ letter: Letter, penPalID: String, entries: [JournalEntry], dominantMood: String?,
                                          context: ModelContext, ai: AIService, session: UserSession,
                                          isMember: Bool, errors: ErrorPresenter) async {
        let id = letter.id
        let request = PenPalLetterContext(
            clientLetterID: id,
            penPalID: penPalID,
            entries: entries.map(\.snapshot),
            dominantMood: dominantMood,
            notebook: PenPalNotebook.snapshot(for: penPalID, context: context)
        )
        update(id) { $0.attempts += 1 }
        let background = UIApplication.shared.beginBackgroundTask(withName: "penpal-letter-send")
        defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }

        do {
            let draft = try await ai.generatePenPalLetter(request)
            guard isQueued(letter) else { return }
            letter.body = draft.letter
            letter.translatedBody = draft.translation.isEmpty ? nil : draft.translation
            letter.danger = draft.danger
            letter.postage = draft.postage
            letter.status = LetterStatus.pending.rawValue
            letter.errorMessage = nil
            letter.updatedAt = .now
            PenPalNotebook.apply(draft.notebook, for: penPalID, at: draft.generatedAt, context: context)
            do {
                try context.save()
            } catch {
                errors.present(error, fallback: NSLocalizedString(
                    "没能收下服务器上的回信", bundle: .appLanguage, comment: "回信写库失败"))
                return
            }
            forget(id)
            NSLog("ℹ️ [LetterOutbox] 寄给世界笔友 %@ id=%@", penPalID, id.uuidString)
            await notifyArrival(of: letter)
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [LetterOutbox] 寄给世界笔友失败 %@ id=%@ domain=%@ code=%ld %@",
                  penPalID, id.uuidString, ns.domain, ns.code, "\(error)")
            await handle(error, letter: letter, context: context, ai: ai, session: session, isMember: isMember, errors: errors)
        }
    }

    private static func handle(_ error: any Error, letter: Letter, context: ModelContext, ai: AIService,
                               session: UserSession, isMember: Bool, errors: ErrorPresenter) async {
        let reason = (error as? LocalizedError)?.errorDescription
        switch error {
        case AIServiceError.network(let http):
            switch http {
            case .offline, .timeout, .transport, .cancelled:
                // 断网、超时：不算失败，过一会儿接着寄（超时的那次服务端可能已经写好了，下次会先补领）
                update(letter.id) { $0.nextAttemptAt = .now.addingTimeInterval(30) }
            default:
                failedOnce(letter, reason: reason, context: context, errors: errors)
            }
        case AIServiceError.rateLimit:
            // 邮票不够（2026-10-16 起）。带信件 id 的重发服务端会原样给回写好的那封、不会走到这里；
            // 老服务端的节奏拦截则十有八九是**这封信已经写好在服务端了**（上一次的回执没回来）——
            // 都先补领一次；领不到才退回并说明原因
            await reconcile(context: context, ai: ai, session: session, isMember: isMember, errors: errors)
            if isQueued(letter) {
                giveBack(letter, reason: reason, context: context, errors: errors)
            }
        case AIServiceError.contentFiltered, AIServiceError.notLoggedIn, AIServiceError.notImplemented,
             AIServiceError.memberRequired, AIServiceError.penPalUnavailable:
            // 重试也没用
            giveBack(letter, reason: reason, context: context, errors: errors)
        default:
            failedOnce(letter, reason: reason, context: context, errors: errors)
        }
    }

    /// 服务端出错一次：没到次数就隔一阵再试，到了就退回
    private static func failedOnce(_ letter: Letter, reason: String?, context: ModelContext, errors: ErrorPresenter) {
        var failures = 0
        update(letter.id) { item in
            item.failures += 1
            failures = item.failures
            item.nextAttemptAt = .now.addingTimeInterval(failures == 1 ? 60 : 300)
        }
        if failures >= maxFailures {
            giveBack(letter, reason: reason ?? NSLocalizedString(
                "试了几次都没寄出去", bundle: .appLanguage, comment: "退信原因：重试几次都失败"), context: context, errors: errors)
        }
    }

    /// 退回邮筒页
    private static func giveBack(_ letter: Letter, reason: String?, context: ModelContext, errors: ErrorPresenter) {
        letter.status = LetterStatus.failed.rawValue
        letter.errorMessage = reason
        letter.updatedAt = .now
        do {
            try context.save()
        } catch {
            errors.present(error, fallback: NSLocalizedString(
                "没能寄出，稍后再试", bundle: .appLanguage, comment: "寄信失败"))
        }
        update(letter.id) { $0.nextAttemptAt = nil }
    }

    /// 写好了就预约到达通知。没授权就不排（`LetterNotifications` 里说了为什么不在这里弹权限）。
    ///
    /// 重试了很久、写好时已经过了到达时刻的，也提醒一声（马上弹）；
    /// 补领回来的旧信（`onlyIfAhead`）只给还没到的排，免得一下子弹出好几条
    private static func notifyArrival(of letter: Letter, onlyIfAhead: Bool = false) async {
        if onlyIfAhead && LetterDelivery.arrival(of: letter) <= .now { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        await LetterNotifications.scheduleArrival(
            letterID: letter.id,
            arrivesAt: LetterDelivery.arrival(of: letter),
            penPalName: letter.fromCharacter
        )
    }

    // MARK: - 补领

    /// 把服务端有、本机没有的信领回来。
    ///
    /// - 写信时刻在某封「写信中」的信寄出之后的 → 那封的回信，填进去（回执丢了的情况）
    /// - 其余的 → 新落一封（2026-09-17 那种：响应没回来，本机什么都没有）。
    ///   到达时刻按服务端的写信时刻重算：已经过了三天的即刻到达，刚写好的照样在路上
    ///
    /// **按正文去重**：本机没有删除来信的入口，不会把用户删掉的信复活
    static func reconcile(context: ModelContext, ai: AIService, session: UserSession,
                          isMember: Bool, errors: ErrorPresenter) async {
        guard session.isLoggedIn else { return }
        let remote: [LetterSummary]
        do {
            remote = try await ai.fetchLetters(limit: 20)
        } catch {
            // 补领是静默的后台动作，失败了下次再领
            let ns = error as NSError
            NSLog("⚠️ [LetterOutbox] 补领失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            return
        }
        guard !remote.isEmpty else { return }

        let all: [Letter]
        do {
            all = try context.fetch(FetchDescriptor<Letter>())
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [LetterOutbox] 读信失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            return
        }
        let existing = Set(all.map(\.body))
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var waiting = all.filter { isQueued($0) && owns($0.id) }.sorted { $0.generatedAt < $1.generatedAt }
        var arrived: [Letter] = []
        var adopted: Set<UUID> = []

        for item in remote.sorted(by: { $0.generatedAt < $1.generatedAt }) {
            // 2026-10-16 起每封信都带着本机的信件 id：对得上就是那一封的回信，不用猜
            if let clientID = item.clientLetterID, let letter = byID[clientID] {
                guard isQueued(letter) else { continue }
                fill(letter, from: item)
                waiting.removeAll { $0.id == clientID }
                arrived.append(letter)
                adopted.insert(letter.id)
                continue
            }
            guard !existing.contains(item.body) else { continue }
            // 老的信没有 id：写信时刻在某封「写信中」的信寄出之后的，就算那封的（只猜自己起名的那位）
            if item.clientLetterID == nil, item.penPalID == nil,
               let index = waiting.firstIndex(where: { $0.penPalID == nil && $0.generatedAt <= item.generatedAt.addingTimeInterval(clockSkew) }) {
                let letter = waiting.remove(at: index)
                fill(letter, from: item)
                arrived.append(letter)
                adopted.insert(letter.id)
            } else {
                let letter = Letter(
                    status: .pending,
                    body: item.body,
                    fromCharacter: item.fromCharacter,
                    toName: session.user?.displayName,
                    triggerKind: .weekly
                )
                letter.penPalID = item.penPalID
                letter.translatedBody = item.translation.flatMap { $0.isEmpty ? nil : $0 }
                letter.danger = item.penPalID == nil ? nil : item.danger
                // 服务器不记当时用的什么信纸，补领回来的按现在的会员身份算
                letter.stationery = Letter.stationery(isMember: isMember)
                letter.generatedAt = item.generatedAt
                letter.deliveredAt = LetterDelivery.arrivalDate(
                    sentAt: item.generatedAt,
                    timeScale: LetterDelivery.debugTimeScale
                )
                context.insert(letter)
                arrived.append(letter)
            }
        }

        guard !arrived.isEmpty else { return }
        do {
            try context.save()
        } catch {
            errors.present(error, fallback: NSLocalizedString(
                "没能收下服务器上的回信", bundle: .appLanguage, comment: "补领信件写库失败"))
            return
        }
        for letter in arrived {
            forget(letter.id)
            await notifyArrival(of: letter, onlyIfAhead: !adopted.contains(letter.id))
        }
        NSLog("ℹ️ [LetterOutbox] 补领 %ld 封", arrived.count)
    }

    /// 补领到的回信填进那封「写信中」的信
    private static func fill(_ letter: Letter, from item: LetterSummary) {
        letter.body = item.body
        letter.fromCharacter = item.fromCharacter
        if item.penPalID != nil {
            letter.translatedBody = item.translation.flatMap { $0.isEmpty ? nil : $0 }
            letter.danger = item.danger
        }
        letter.status = LetterStatus.pending.rawValue
        letter.errorMessage = nil
        letter.updatedAt = .now
    }
}
