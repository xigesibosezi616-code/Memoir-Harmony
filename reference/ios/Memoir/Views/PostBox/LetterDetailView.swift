import SwiftUI
import SwiftData

/// 来信详情。
///
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

    init(letter: Letter) {
        self.letter = letter
        _sealed = State(initialValue: letter.isSealed && LetterDelivery.isUnread(letter))
    }

    var body: some View {
        let theme = themeManager.current
        Group {
            if letter.isSealed {
                if sealed {
                    envelope(theme: theme)
                        .transition(.opacity.combined(with: .offset(y: 30)))
                } else {
                    stationery(theme: theme)
                        .transition(.opacity.combined(with: .offset(y: 16)))
                }
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
