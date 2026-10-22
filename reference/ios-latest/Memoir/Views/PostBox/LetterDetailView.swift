import SwiftUI
import SwiftData

/// 来信详情。
///
/// - 世界笔友的信（`penPalID`，2026-10-16）：一张两面写字的信纸 —— 正面是他用母语写的原文，
///   翻过来是译文；危险的那封**正面直接是读信人的语言**，信纸下面再附一张求助卡片（`CrisisHelpCard`）。
///   他的母语和你的语言相同时只有一面、不翻。信纸下面一行小字写明他是虚构的 AI 笔友
/// - 普通信：打开即已读（首次显示时把 `delivered` 推进到 `read`）
/// - 火漆信（尺素会员寄出的，见 `Letter.isSealed`）：没拆过的先是一枚封着的信封，
///   一下一下拆开（见 `SealedLetterOpener`），**打碎火漆那一刻算已读**；拆过的直接摊开信纸。
///   只看了一眼信封就退出去，信还封着 —— 和实物一样
struct LetterDetailView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var store
    @State private var showPaywall = false

    let letter: Letter

    /// 这次进来时信还封着、还没拆完。进来那一刻定下，拆完变 false
    @State private var sealed: Bool
    /// 世界笔友的信：现在看的是不是背面
    @State private var showsBack = false
    /// 信纸的宽度（算两面的字各占几行用）
    @State private var paperWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    init(letter: Letter) {
        self.letter = letter
        _sealed = State(initialValue: letter.isSealed && LetterDelivery.isUnread(letter))
    }

    var body: some View {
        let theme = themeManager.current
        Group {
            if letter.isSealed && sealed {
                envelope(theme: theme)
                    .transition(.opacity.combined(with: .offset(y: 30)))
            } else if isWorldLetter {
                worldLetter(theme: theme)
                    .transition(.opacity.combined(with: .offset(y: 16)))
            } else if letter.isSealed {
                stationery(theme: theme)
                    .transition(.opacity.combined(with: .offset(y: 16)))
            } else {
                plainLetter(theme: theme)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("来信")
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .onAppear {
            // 火漆信要等拆开才算读过
            if !sealed { markAsRead() }
        }
        .paywallCover(isPresented: $showPaywall)
    }

    // MARK: - 普通信

    private func plainLetter(theme: any AppTheme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 信头
                VStack(alignment: .leading, spacing: 6) {
                    Text(letter.generatedAt.dayAndWeekday)
                        .font(.custom("Georgia", size: 13))
                        .foregroundStyle(theme.textTertiary)
                        .tracking(theme.letterSpacingWide)
                    salutation
                        .font(.custom("Georgia", size: 28))
                        .foregroundStyle(theme.textPrimary)
                }
                .padding(.top, 8)

                Rectangle()
                    .fill(theme.borderAccent)
                    .frame(height: 0.5)

                // 正文（已含开头 + 中段 + 结尾 + 签名）
                Text(letter.body)
                    .font(.custom("Georgia", size: 17))
                    .lineSpacing(10)
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !store.isMember {
                    memberHint(theme: theme)
                        .padding(.top, 20)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 60)
        }
    }

    // MARK: - 火漆信

    private var palette: LetterPalette {
        LetterPalette.of(themeID: themeManager.currentThemeID)
    }

    /// 封着的信封：一下一下拆开，拆完摊成信纸
    private func envelope(theme: any AppTheme) -> some View {
        SealedLetterOpener(
            palette: palette,
            sealMark: WaxSeal.initial(of: letter.fromCharacter),
            sender: Text("来自\(letter.fromCharacter)"),
            onBroken: { markAsRead() },
            onFinished: {
                withAnimation(.easeInOut(duration: LetterOpeningFeel.unfoldDuration)) { sealed = false }
            }
        )
    }

    private func stationery(theme: any AppTheme) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                LetterStationery(
                    palette: palette,
                    date: letter.generatedAt.dayAndWeekday,
                    salutation: salutation,
                    content: letter.body
                )
                if !store.isMember {
                    memberHint(theme: theme)
                        .padding(.top, 28)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
    }

    // MARK: - 世界笔友的信

    /// 世界笔友写来的（自己起名的那一位 `penPalID` 是 nil）
    private var isWorldLetter: Bool { letter.penPalID != nil }

    /// 有没有译文。他的母语和你的语言相同（如西安的吴写给写中文的你）就只有原文一面
    private var hasTranslation: Bool { !(letter.translatedBody ?? "").isEmpty }

    /// 危险的那封正面是译文（读信人的语言），平常正面是原文
    private var frontIsTranslation: Bool { hasTranslation && letter.danger == true }

    /// 这封信是用哪种语言写给你的：有译文看译文，没有就看原文（和你的语言相同）。
    /// 求助卡片按它选热线 —— 和服务端写进信里的那条一致
    private var readerLanguage: String {
        LetterLanguage.forLetter(texts: [hasTranslation ? (letter.translatedBody ?? "") : letter.body])
    }

    private func worldLetter(theme: any AppTheme) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                if hasTranslation {
                    twoSidedSheet(theme: theme)
                } else {
                    side(content: letter.body, blankLines: 2)
                }

                if letter.danger == true {
                    CrisisHelpCard(language: readerLanguage, palette: palette)
                        .padding(.top, 6)
                }

                // 信末写明：他是虚构的 AI 笔友（产品定：名册、信末、隐私协议都写清）
                Text("\(letter.fromCharacter)是尺素里虚构的 AI 笔友。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
    }

    /// 两面写字的那张纸，下面是翻面的按钮
    @ViewBuilder
    private func twoSidedSheet(theme: any AppTheme) -> some View {
        let translation = letter.translatedBody ?? ""
        let front = frontIsTranslation ? translation : letter.body
        let back = frontIsTranslation ? letter.body : translation
        // 同一张纸两面一样大：字少的那一面多画几格空行（正文区左右各留 28pt）
        let textWidth = paperWidth - 56
        let frontHeight = RuledTextView.textHeight(front, width: textWidth)
        let backHeight = RuledTextView.textHeight(back, width: textWidth)
        let extraLines = { (height: CGFloat) in
            max(0, Int(((max(frontHeight, backHeight) - height) / 34).rounded(.up)))
        }
        FlipSheet(angle: showsBack ? 180 : 0) {
            side(content: front, blankLines: 2 + extraLines(frontHeight))
        } back: {
            side(content: back, blankLines: 2 + extraLines(backHeight))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paperWidth = $0 }
        // 翻面：说清楚背面是什么（原文 / 译文），而不是一个光秃秃的「翻转」
        Button(action: flip) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                if showsBack == frontIsTranslation {
                    Text("看译文")
                } else {
                    Text("看原文")
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(Capsule().strokeBorder(theme.textPrimary.opacity(0.4), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    /// 信纸的一面。信头是寄信人（地名 · 姓）—— 世界笔友的信里自己会称呼你，不再写「致 XXX」
    private func side(content: String, blankLines: Int) -> some View {
        LetterStationery(
            palette: palette,
            date: letter.generatedAt.dayAndWeekday,
            salutation: Text(verbatim: sender),
            content: content,
            blankLines: blankLines
        )
    }

    /// 「斯图尔特岛 · McRae」。名册里找不到这位（比如老版本没有的笔友）就只写信上的署名
    private var sender: String {
        guard let id = letter.penPalID, let penPal = PenPalRoster.penPal(id: id) else { return letter.fromCharacter }
        return "\(penPal.place.resolved(for: locale)) · \(letter.fromCharacter)"
    }

    /// 把信纸翻过来：像拿起一张纸翻面 —— 平滑、不回弹；减弱动态效果时直接换面
    private func flip() {
        if reduceMotion {
            showsBack.toggle()
        } else {
            withAnimation(.easeInOut(duration: 0.6)) { showsBack.toggle() }
        }
    }

    // MARK: - 共用

    /// 抬头「致 XXX」。昵称是**写信当时的快照**，不是实时读当前昵称 ——
    /// 否则用户改一次名字，连去年那封信的抬头都会跟着变。
    ///
    /// ⚠️ 这里必须让插值走 `LocalizedStringKey`（catalog key 是「致%@」），
    /// 不能拼成 String 再塞进 `Text` —— `Text(String)` 不查表。
    /// 各语言的语序不一样（日文是「%@へ」，名字在前），所以只能整句交给译文排。
    private var salutation: Text {
        if let toName = letter.toName, !toName.isEmpty {
            Text("致\(toName)")
        } else {
            // 没登录 / 没设昵称：退回光秃秃的「致」
            Text("致")
        }
    }

    /// 尺素会员：免费用户读完一封信，最下面一行轻提示，点了才打开付费页。
    /// 这是最心动的时刻 —— 刚被回应过；但只是一行小字，不弹窗、不打断读信
    private func memberHint(theme: any AppTheme) -> some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 8) {
                MemberBadge(size: 16)
                Text("想让笔友每篇都回？")
                    .foregroundStyle(theme.textTertiary)
                Text("了解尺素会员")
                    .foregroundStyle(theme.accent)
            }
            .font(theme.captionFont)
        }
        .buttonStyle(.plain)
    }

    /// 标记已读（只第一次有效）。
    ///
    /// 2026-09-14 起到达的信状态是 `pending`（见 `LetterDelivery`），不再经过 `delivered`，
    /// 所以这里判「已到达且还没读」，而不是只认 `delivered`
    private func markAsRead() {
        guard LetterDelivery.isUnread(letter) else { return }
        letter.status = LetterStatus.read.rawValue
        letter.readAt = .now
        letter.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            // 已读状态写库失败 = 用户下次进还会被标已读，不阻断阅读体验；只提示，不重试
            env.errors.present(error, fallback: "标记已读失败")
        }
    }
}

/// 一张两面写字的纸：绕竖轴翻过去，转到 90° 那一刻换成背面（之前看不见背面，之后看不见正面）。
/// 自己做插值（`Animatable`），换面的时刻才准 —— 用透明度淡入淡出的话，翻到一半两面会叠在一起
private struct FlipSheet<Front: View, Back: View>: View, Animatable {
    var angle: Double
    @ViewBuilder let front: Front
    @ViewBuilder let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        ZStack(alignment: .top) {
            front
                .opacity(angle < 90 ? 1 : 0)
                .accessibilityHidden(angle >= 90)
            back
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(angle >= 90 ? 1 : 0)
                .accessibilityHidden(angle < 90)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.3)
    }
}

