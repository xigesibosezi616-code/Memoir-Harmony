import Foundation

/// 假信生成器 —— 让 Letter UI 能在中转服务器就绪前先跑起来。
///
/// **特性**：
/// - 按 `dominantMood` 选模板（6 类心情各 3 个模板）
/// - `triggerKind` 决定信的长度（daily 短 / weekly 中 / monthly 长 / perEntry 视情）
/// - 开头 / 结尾各 3 个变体，组合产生多样性
/// - 模拟 1.5–3 秒随机延迟（仿真"AI 正在生成"loading 体验）
/// - 可配置 `failureRate`（0..1），方便测试 ErrorPresenter 链路
///
/// 默认仅在 DEBUG 编译生效（`MemoirApp` 选实现），release 由 Proxy 接管。
final class MockAIService: AIService {

    /// 随机延迟范围（秒）；默认 1.5–3.0
    var simulatedDelay: ClosedRange<Double> = 1.5...3.0
    /// 模拟失败率（0..1），默认 0；测试错误 UI 时调高
    var failureRate: Double = 0.0

    init(simulatedDelay: ClosedRange<Double> = 1.5...3.0,
         failureRate: Double = 0.0) {
        self.simulatedDelay = simulatedDelay
        self.failureRate = failureRate
    }

    /// Mock 不连服务端，没有可补领的信
    func fetchLetters(limit: Int) async throws -> [LetterSummary] { [] }

    /// Mock 的邮票夹永远是满的
    func fetchStamps() async throws -> StampWallet {
        StampWallet(balance: 40, cap: 40, nextPackAt: .now.addingTimeInterval(7 * 86_400), packReady: false, isMember: true)
    }

    func claimStamps() async throws -> StampWallet { try await fetchStamps() }

    /// Mock 下所有世界笔友都能寄
    func fetchAvailablePenPals() async throws -> Set<String> { Set(PenPalRoster.all.map(\.id)) }

    /// 假的世界笔友回信：原文和译文是同一段假信（够让界面跑起来），记一条事
    func generatePenPalLetter(_ context: PenPalLetterContext) async throws -> PenPalLetterDraft {
        let name = PenPalRoster.penPal(id: context.penPalID)?.surname.resolved(for: appLocale) ?? context.penPalID
        let draft = try await generateLetter(for: LetterContext(
            entries: context.entries, triggerKind: .perEntry, dominantMood: context.dominantMood, penPalName: name))
        return PenPalLetterDraft(letter: draft.body, translation: draft.body,
                                 remember: context.entries.first.map { [String($0.title.prefix(20))] } ?? [],
                                 danger: false, postage: PenPalRoster.penPal(id: context.penPalID)?.postage ?? 1,
                                 generatedAt: .now, balance: 39)
    }

    func generateLetter(for context: LetterContext) async throws -> LetterDraft {
        // 1. 模拟延迟
        let delay = Double.random(in: simulatedDelay)
        try await Task.sleep(for: .seconds(delay))

        // 2. 模拟失败
        if failureRate > 0, Double.random(in: 0...1) < failureRate {
            throw AIServiceError.generationFailed("假信生成器随机失败（测试用）")
        }

        // 3. 拼出一封信
        let opening = Self.openings.randomElement() ?? "你好，"
        let middle = Self.middle(for: context.dominantMood)
        let closing = Self.closings.randomElement() ?? "保重。"

        // triggerKind 影响段数
        let extraCount: Int
        switch context.triggerKind {
        case .daily:    extraCount = 0
        case .weekly:   extraCount = 1
        case .monthly:  extraCount = 2
        case .perEntry: extraCount = 1
        }
        var extras: [String] = []
        for _ in 0..<extraCount {
            extras.append(Self.extraParagraphs.randomElement() ?? "")
        }

        // 末尾拼当前笔友名签名（从模板剥离后统一在这里生成）
        let signature = "   —— \(context.penPalName)"
        let body = ([opening, middle] + extras + [closing, signature])
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return LetterDraft(body: body, fromCharacter: context.penPalName)
    }

    // MARK: - 模板库

    private static let openings: [String] = [
        "见字如面。",
        "好久不见。",
        "今天突然想给你写几行。",
        "夜里想到你，便写下这些。",
        "窗外的风刚好，趁这片刻给你写信。"
    ]

    /// 结尾句（不含署名 —— 署名由 `generateLetter` 在拼装时统一附加，
    /// 这样模板里不写死任何名字，支持用户改名）
    private static let closings: [String] = [
        "愿你今夜睡得安稳。",
        "走慢一点，没关系的。",
        "下次再写。",
        "替我看看你窗外的天色。",
        "不必回信，知道你在就好。"
    ]

    /// 按主导情绪选信的中段。覆盖六类，nil 走默认。
    private static func middle(for mood: String?) -> String {
        let pool: [String]
        switch mood {
        case "calm":       pool = calmMiddle
        case "joyful":     pool = joyfulMiddle
        case "low":        pool = lowMiddle
        case "reflective": pool = reflectiveMiddle
        case "anxious":    pool = anxiousMiddle
        case "excited":    pool = excitedMiddle
        default:           pool = defaultMiddle
        }
        return pool.randomElement() ?? ""
    }

    // 各情绪 3 段。语调克制、不强行积极，呼应日记的意象而非复述。
    private static let calmMiddle: [String] = [
        "读到你最近的几行，有种很静的感觉，像是一片湖面被晨光罩住。我想，这样的状态本身就是难得的。日子有时候不需要发生什么，只是让它好好地过去，就已经是一种圆满。",
        "你写下的那些片段里，有一种很温的安稳。不是没有起伏，而是知道起伏来了也无妨。我想这是你这段时间慢慢长出来的东西。",
        "看到你最近的状态平和，我也跟着松了一口气。生活不必每天都激烈，能这样安安静静地过几天，已经很好。"
    ]

    private static let joyfulMiddle: [String] = [
        "你最近写的那些字里，有一种很亮的颜色。我读着读着，自己也笑了。那些让你高兴的瞬间，请尽情记下来 —— 等以后某个不那么好过的日子翻开，会像找到一盏小灯。",
        "为你这段时间的快乐感到由衷的高兴。开心不是理所当然的事，每一次都值得被认真对待。",
        "你的喜悦从字里行间溢出来。我想跟你说，不必担心这种高兴会很快消失 —— 它已经被你写下来了，就一直在了。"
    ]

    private static let lowMiddle: [String] = [
        "读你这几日的字，能感到那种沉。我不会让你「加油」，也不会跟你说「会过去的」那种话。我只想告诉你，难过本身就是真的，不必为它羞愧，也不必急着摆脱。",
        "有些日子像被一层薄雾罩住，看不远，也走不快。这种时候不要硬要自己跑，慢慢踱步就好。我在这儿，无论你想说什么我都在。",
        "你最近写下的那些，我都看见了。没有什么需要修正的，没有什么需要立刻好起来。坐在原地一会儿，是允许的。"
    ]

    private static let reflectiveMiddle: [String] = [
        "你最近写的那些字里，有一种在自己心里反复走一条路的感觉。想清楚一点也好，想不清楚也没关系 —— 答案有时候不是想出来的，是过着过着就出现的。",
        "我注意到你这段时间在跟自己对话。这种状态外人看来安静，内里其实正在做很重要的事。给它一点时间。",
        "你写下的那些问题，我没有现成的答案给你。但你愿意提出来，本身就已经走在路上了。"
    ]

    private static let anxiousMiddle: [String] = [
        "读到你这几日的不安，我想先跟你说一句：你已经在尽力撑住了。焦虑常常是因为想得太远，把还没发生的事都搬到了今天 —— 试着把目光收回来，只看眼前这一步。",
        "你最近的字里，能感到一种紧绷。不必跟自己较劲。深呼吸一次，再呼吸一次。事情可能不会立刻变好，但你可以先让自己缓一会儿。",
        "看到你写下「担心」的那些字，我心里也跟着收紧了一下。让我陪你一会儿。无论结果怎样，今天的你已经走到了这里，这件事本身值得肯定。"
    ]

    private static let excitedMiddle: [String] = [
        "你最近的字像是被什么火花点着了，读起来叫人也跟着心跳加速。这种期待感请好好收着 —— 它会推着你往前走一段。",
        "读你这几天的字，能感到一种刚开始的气息。无论后面会发生什么，这个「刚开始」的时刻本身就很珍贵。",
        "你写的那些事让我也跟着兴奋。记得在它真的发生时，多看一眼天，多听一会儿声音 —— 那些细节以后会比结果更让你记得。"
    ]

    private static let defaultMiddle: [String] = [
        "读着你最近的字，能感到很多层次。有些事说不上是好是坏，就是发生了。这就是日子本身的样子。",
        "谢谢你愿意写下来。无论是什么样的一天，被记下来了，就比飘走了好。",
        "我读完了你这段时间的字。说不出具体哪一句最打动我 —— 是它们合在一起的那种重量。"
    ]

    /// triggerKind = weekly / monthly 时，往中段后再附加 1-2 段。
    private static let extraParagraphs: [String] = [
        "另外，你提到的那些小事 —— 一杯茶、一片天、一次散步 —— 别小看它们。日子的厚度，其实就是这些累出来的。",
        "我有时候在想，所谓「过得好」，可能不是发生了多了不起的事，而是在很普通的一天里，仍然能注意到一些细节。你最近就在做这件事。",
        "如果你最近觉得自己变化不大，不必焦虑。有些东西在慢慢长，你自己看不出来，但翻开半年前的字就能看到。",
        "记得偶尔抬头看看天。哪怕只是几秒。"
    ]
}
