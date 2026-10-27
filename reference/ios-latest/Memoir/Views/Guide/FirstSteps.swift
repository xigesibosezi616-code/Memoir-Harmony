import SwiftData
import SwiftUI

/// 新手指引（2026-10-27 用户定的流程）：首启完（同意协议 → 给笔友起名 → 选主题）进主界面后，一步步带着走
///
///   ① 记录页：点 + 写第一篇        ② 选日记本页：先给自己做一本日记本（新建页里起名、挑封面、创建）
///   ③ 选好那本 → 写日记页：写几句 / 拍一张，写好点 ✓（存好后选心情）
///   ④ 写好了 → 去「邮筒」         ⑤ 邮筒页：把那叠信往上推（没登录：先登录）
///   ⑥ 寄出去了：笔友读完会回信     ⑦ 等着（不出任何提示）
///   ⑧ 第一封回信到了 → 去邮筒、点开信箱、点开这封回信      ⑨ 读着       ⑩ 读完：结束语
///
/// - Sinara 的欢迎信**不引导**（用户 10-27 改）：首启时以没拆的样子放进信箱，用户自己去拆
/// - **进度存在本机**（`UserDefaults`），中途退出、杀掉程序，下次从退出的那一步接着走
/// - 只往前走：每一步只在「现在正处在某几步」时才往下推，不会倒退，也不会被别的页面意外跳过
/// - 老用户没有这个值（= `.off`），一律不出指引
/// - 🔴 文案是草稿，只有简体中文（用户 10-27 定：正式的信和七种语言等用户写好再一起做）
enum FirstStep: Int {
    /// 没有指引：老用户，或者走完了
    case off = 0
    case writeFirst = 1
    case createNotebook = 2
    case compose = 3
    case sendFirst = 4
    case pushPile = 5
    case sent = 6
    case waitReply = 7
    case replyArrived = 8
    case readReply = 9
    case finale = 10

    static let storageKey = "firstStep"
    /// 第一封回信是哪一封（`Letter.id`）、谁写的 —— 回信到的那一刻记下，后面几步指的都是它
    static let replyIDKey = "firstStepReplyID"
    static let replyFromKey = "firstStepReplyFrom"

    static var current: FirstStep {
        FirstStep(rawValue: UserDefaults.standard.integer(forKey: storageKey)) ?? .off
    }

    /// 现在处在 `from` 里的某一步，才走到 `step`
    static func advance(to step: FirstStep, from: Set<FirstStep>) {
        guard from.contains(current) else { return }
        UserDefaults.standard.set(step.rawValue, forKey: storageKey)
    }

    /// 写好第一篇之前的那些步（跳着做时一并认）
    static let beforeSending: Set<FirstStep> = [.writeFirst, .createNotebook, .compose]

    /// 从头开始：首启走完、或者测试包里「重新走一遍」。欢迎信同时放进信箱（已经有了就恢复成没拆过）
    @MainActor
    static func begin(in context: ModelContext, toName: String?) {
        UserDefaults.standard.set(FirstStep.writeFirst.rawValue, forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: replyIDKey)
        UserDefaults.standard.removeObject(forKey: replyFromKey)
        // 捏合彩蛋也从头来（测试包重走一遍时能再看到；新用户本来就没有这个值）
        UserDefaults.standard.removeObject(forKey: PinchTip.doneKey)
        WelcomeLetter.deliver(in: context, toName: toName)
    }

    /// 停在「回信到了 / 读着」、可那封回信其实已经读过了（读完没退出就被杀掉）：直接到结束语
    @MainActor
    static func reconcile(in context: ModelContext) {
        guard [.replyArrived, .readReply].contains(current),
              let raw = UserDefaults.standard.string(forKey: replyIDKey), let id = UUID(uuidString: raw) else { return }
        do {
            let found = try context.fetch(FetchDescriptor<Letter>(predicate: #Predicate { $0.id == id })).first
            if found?.status == LetterStatus.read.rawValue {
                advance(to: .finale, from: [.replyArrived, .readReply])
            }
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [FirstStep] 查第一封回信失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        }
    }

    static func finish() {
        UserDefaults.standard.set(FirstStep.off.rawValue, forKey: storageKey)
    }
}

/// 寄出第一封之后盯着：回信一到（到了、没读、不是欢迎信）就记下是哪一封，走到「回信到了」。
/// 在路上的信到点了要自己发现，每 10 秒看一次；只在 ⑥⑦ 两步挂着
struct FirstReplyWatcher: View {
    @Query private var letters: [Letter]

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .task {
                while !Task.isCancelled {
                    check()
                    try? await Task.sleep(for: .seconds(10))
                }
            }
    }

    private func check() {
        guard [.sent, .waitReply].contains(FirstStep.current) else { return }
        let now = Date.now
        guard let reply = letters
            .filter({ !$0.isWelcome && LetterDelivery.isUnread($0, now: now) })
            .min(by: { LetterDelivery.arrival(of: $0) < LetterDelivery.arrival(of: $1) }) else { return }
        UserDefaults.standard.set(reply.id.uuidString, forKey: FirstStep.replyIDKey)
        UserDefaults.standard.set(reply.fromCharacter, forKey: FirstStep.replyFromKey)
        withAnimation(.easeOut(duration: 0.3)) {
            FirstStep.advance(to: .replyArrived, from: [.sent, .waitReply])
        }
    }
}

/// Sinara 的欢迎信：首启进主界面时放进信箱，火漆封口、没拆过（用户定：每个人第一封信就体验一次拆火漆；
/// 10-27 改成不引导，用户自己去拆 —— 拆的时候拆信组件的提示照样显眼、带手势示意，见 `LetterDetailView`）。
///
/// - 用现有的 `Letter`，不改数据模型：`penPalID = "sinara"` 认出它（信箱按笔友归类时单独一组；读信页按火漆信纸显示，
///   不当成世界笔友的信、信末也不写「虚构的 AI 笔友」）。**这个值会跟着备份包走**，鸿蒙要认（见 U13）
/// - 固定的 id：同一个人在两台设备上各收一封时，至少能认出是同一封
/// - 正文是草稿，只有简体中文（正式的信用户在写）
enum WelcomeLetter {
    static let penPalID = "sinara"
    static let sender = "Sinara"
    static let id = UUID(uuidString: "5A1A0000-0000-4000-8000-000000000001")!

    static let body = """
    见字如面。

    谢谢你来到尺素。

    尺素是只属于你的本子：你写下的字、拍的照片、录的声音，都只放在这台手机和你自己的 iCloud 里。只有你把日记寄给笔友时，那几篇的文字才会送去写回信，写完不留。

    写好一篇，就可以把它投进邮筒寄给笔友。笔友会认真读，过几个小时给你回一封信，就放在这个信箱里。一张邮票寄一封，每周都会送来新的邮票，没用完的一直攒着。

    这封信用火漆封着——尺素会员的每一封回信，都会这样封好送来。

    不用每天都写，想写的时候来就好。

    祝好，
    Sinara
    """

    @MainActor
    static func deliver(in context: ModelContext, toName: String?) {
        let id = Self.id
        let existing: [Letter]
        do {
            existing = try context.fetch(FetchDescriptor<Letter>(predicate: #Predicate { $0.id == id }))
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [WelcomeLetter] 查欢迎信失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            return
        }
        let letter: Letter
        if let found = existing.first {
            letter = found
        } else {
            letter = Letter(status: .delivered, body: body, fromCharacter: sender, toName: toName, triggerKind: .weekly)
            letter.id = id
            context.insert(letter)
        }
        letter.status = LetterStatus.delivered.rawValue
        letter.readAt = nil
        letter.penPalID = penPalID
        letter.stationery = LetterStationeryKind.sealed.rawValue
        letter.generatedAt = .now
        letter.deliveredAt = .now
        letter.updatedAt = .now
        do {
            try context.save()
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [WelcomeLetter] 放欢迎信失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        }
    }
}

extension Letter {
    /// Sinara 的欢迎信（不是哪位笔友的回信）
    var isWelcome: Bool { penPalID == WelcomeLetter.penPalID }
}

// MARK: - 提示的样子

/// 一句话 + 一根细虚线弯到要点的地方，那里一圈轻轻呼吸的细环。
///
/// **整层不接点按**：只是指个方向，不挡任何操作 —— 用户点对了地方，指引自己往下走。
/// `target` 是要指的那块在**全局坐标**里的位置（`onGeometryChange` 量 `.global`），这里换算成本层坐标
struct GuideHint: View {
    let text: LocalizedStringKey
    let target: CGRect
    /// 话放在目标的下方还是上方
    var below = true
    let theme: any AppTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let size = proxy.size
            let t = CGRect(x: target.minX - origin.x, y: target.minY - origin.y, width: target.width, height: target.height)
            let width = min(size.width - 48, 250)
            let x = min(max(t.midX, 24 + width / 2), size.width - 24 - width / 2)
            let y = below ? t.maxY + 64 : t.minY - 64
            let tip = CGPoint(x: t.midX, y: below ? t.maxY + 6 : t.minY - 6)

            ZStack {
                Path { p in
                    let start = CGPoint(x: x + (t.midX - x) * 0.4, y: below ? y - 20 : y + 20)
                    p.move(to: start)
                    p.addQuadCurve(to: tip, control: CGPoint(x: tip.x, y: start.y))
                }
                .stroke(theme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 4]))

                // 小按钮套一圈圆环；长条的（信箱里的一行、那叠信）贴着它描一个圆角框，不然圆会圈住半个屏幕
                if t.width > t.height * 1.6 {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.accent.opacity(breathe ? 0.15 : 0.55), lineWidth: 1.2)
                        .frame(width: t.width + 8, height: t.height + 8)
                        .scaleEffect(breathe ? 1.02 : 1)
                        .position(x: t.midX, y: t.midY)
                } else {
                    Circle()
                        .stroke(theme.accent.opacity(breathe ? 0.15 : 0.55), lineWidth: 1.2)
                        .frame(width: max(t.width, t.height) + 14, height: max(t.width, t.height) + 14)
                        .scaleEffect(breathe ? 1.12 : 1)
                        .position(x: t.midX, y: t.midY)
                }

                Text(text)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: width)
                    .guideFrame(theme: theme, shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .position(x: x, y: y)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathe = true }
        }
        .transition(.opacity)
    }
}

extension View {
    /// 指引的框（2026-10-27 用户定：不用实心的）：半透明的毛玻璃底 + 一圈主题色的细线，不加投影
    func guideFrame<S: Shape>(theme: any AppTheme, shape: S) -> some View {
        background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(theme.accent.opacity(0.55), lineWidth: 1))
    }
}

/// 带按钮的小卡片（「先登录」「好」）：要用户点一下的那几步。放在页面下方
struct GuideCard: View {
    let text: LocalizedStringKey
    let button: LocalizedStringKey
    let theme: any AppTheme
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(text)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Text(button)
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(theme.background)
                    .padding(.horizontal, 28)
                    .frame(height: 40)
                    .background(theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: 300)
        .guideFrame(theme: theme, shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .transition(.opacity.combined(with: .offset(y: 12)))
    }
}

/// 指向底栏某个 tab 的提示（底栏是系统画的，量不到每一格的位置，按几格平均分估一个）。
/// 话里写明 tab 的名字，细线差一点也不会认错
struct GuideTabHint: View {
    let text: LocalizedStringKey
    /// 第几格（0 起）
    let tab: Int
    /// 底栏一共几格（开了搜索那颗圆时，四格的胶囊会变窄，见 `ContentView`）
    let showsSearch: Bool
    let theme: any AppTheme

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let x = w * TabBarLayout.centers(showsSearch: showsSearch)[min(max(tab, 0), 3)]
            let frame = CGRect(x: x - 22, y: h - TabBarLayout.iconFromBottom - 17, width: 44, height: 44)
            GuideHint(text: text, target: frame.offsetBy(dx: proxy.frame(in: .global).minX, dy: proxy.frame(in: .global).minY),
                      below: false, theme: theme)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - 小彩蛋：大屏模式双指捏合

/// 大屏模式下的双指捏合小彩蛋（2026-10-27 用户定）：日记攒到 8 篇，记录页一屏一篇时提示
/// 「双指捏一捏，一屏看更多日记」，两个指尖往里捏的动画。
/// 用户真的捏了一下（换了一级）就永久不再出；没捏之前每次进来都提示。新手指引走完之前不出（见 `HomeView`）
enum PinchTip {
    static let doneKey = "pinchTipDone"
    /// 攒到几篇才提示（用户 10-27 先说 12，又改成 8）
    static let minEntries = 8
}

/// 捏合提示的样子：两个指尖沿对角线往里捏（1.8 秒一轮，前七成在捏、淡入淡出，后面停一下），下面一句话。不接点按，捏的手势照常落在卡片上
struct PinchTipView: View {
    let theme: any AppTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            TimelineView(.animation(paused: reduceMotion)) { context in
                let p = (context.date.timeIntervalSinceReferenceDate / 1.8).truncatingRemainder(dividingBy: 1)
                let move = min(p / 0.7, 1)
                let eased = move * move * (3 - 2 * move)
                // 两个指尖离中心多远：44 → 14
                let gap = 44 - 30 * eased
                ZStack {
                    fingertip.offset(x: -gap, y: gap)
                    fingertip.offset(x: gap, y: -gap)
                }
                .opacity(reduceMotion ? 0.8 : (p < 0.7 ? 0.3 + 0.6 * sin(move * .pi) : 0))
                .frame(width: 130, height: 130)
            }
            Text("双指捏一捏，一屏看更多日记")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .guideFrame(theme: theme, shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    /// 一个指尖：白色半透明的圆，细边，一点点影子（卡片是彩色的，压在什么颜色上都看得见）
    private var fingertip: some View {
        Circle()
            .fill(.white.opacity(0.85))
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(theme.textPrimary.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
    }
}
