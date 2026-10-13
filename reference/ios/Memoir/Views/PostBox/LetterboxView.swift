import SwiftUI
import SwiftData

/// 信箱 —— 收信的地方（被动）。
///
/// 只显示**已经到达**的回信。在路上的信（`LetterDelivery.isInTransit`）这里看不见，
/// 到了点才出现 —— 这就是「信箱收信是随机、被动的」。
///
/// 从邮筒页右上角进来，或者点「回信到了」的通知直达。
struct LetterboxView: View {
    @Environment(ThemeManager.self) private var themeManager

    @Query(sort: \Letter.generatedAt, order: .reverse) private var letters: [Letter]

    /// 「此刻」。每隔几秒推进一次：信是按时间到达的，页面开着时也要让新到的信冒出来
    @State private var now = Date.now

    private var arrived: [Letter] {
        letters
            .filter { LetterDelivery.hasArrived($0, now: now) }
            .sorted { LetterDelivery.arrival(of: $0) > LetterDelivery.arrival(of: $1) }
    }

    /// 写好了还没到的，和投进邮筒、回信还在写的（`LetterOutbox`），对用户来说都是「在路上」
    private var hasLettersInTransit: Bool {
        letters.contains { LetterDelivery.isInTransit($0, now: now) || LetterOutbox.isQueued($0) }
    }

    var body: some View {
        let theme = themeManager.current
        ScrollView {
            VStack(spacing: 0) {
                if arrived.isEmpty {
                    emptyState(theme: theme)
                } else {
                    ForEach(Array(arrived.enumerated()), id: \.element.id) { index, letter in
                        if index > 0 {
                            Divider().overlay(theme.border).padding(.leading, 68)
                        }
                        NavigationLink {
                            LetterDetailView(letter: letter)
                        } label: {
                            LetterRow(letter: letter, isUnread: LetterDelivery.isUnread(letter, now: now), theme: theme)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if hasLettersInTransit && !arrived.isEmpty {
                Text("有回信正在路上")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.top, 16)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("信箱")
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                now = .now
            }
        }
    }

    private func emptyState(theme: any AppTheme) -> some View {
        VStack(spacing: 8) {
            Text("信箱还是空的")
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
            if hasLettersInTransit {
                Text("有回信正在路上")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 一行

struct LetterRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let letter: Letter
    let isUnread: Bool
    let theme: any AppTheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leading
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("来自\(letter.fromCharacter)")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    // 信箱里显示的是**收到的日子**（到达时刻），不是寄出的日子
                    Text(LetterDelivery.arrival(of: letter).shortDate)
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                }
                // 火漆信没拆之前看不到里面写了什么 —— 和实物一样，拆开才算读到
                Group {
                    if letter.isSealed && isUnread {
                        Text("火漆封着，还没拆")
                    } else {
                        Text(String(letter.body.prefix(60)))
                    }
                }
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Circle()
                .fill(theme.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .opacity(isUnread ? 1 : 0)
        }
    }

    /// 火漆信是一枚小信封（没拆的封着，拆过的封舌翻开）；普通信是笔友头像（首字 in circle）
    @ViewBuilder
    private var leading: some View {
        if letter.isSealed {
            SealedEnvelope(
                palette: LetterPalette.of(themeID: themeManager.currentThemeID),
                sealMark: WaxSeal.initial(of: letter.fromCharacter),
                progress: isUnread ? 0 : 0.55
            )
            .frame(width: 40)
            // 翻开的封舌会冒出信封上沿，往下挪一点，让整体落在头像那一格里
            .offset(y: isUnread ? 0 : 7)
            .accessibilityHidden(true)
        } else {
            ZStack {
                Circle().fill(theme.accentBackground)
                Text(String(letter.fromCharacter.first ?? "青"))
                    .font(.custom("Georgia", size: 16))
                    .foregroundStyle(theme.accent)
            }
        }
    }
}
