import SwiftUI

/// 寄出去之后：一枚邮戳 + 「在路上」。
///
/// 信写好之前（AI 还在后台写）和写好之后、到达之前，对用户来说都是「在路上」，不分开说
struct InTransitNote: View {
    let sentAt: Date
    let place: String?
    let ink: Color
    /// 除了这封，还有别的信也在路上
    let hasOthers: Bool

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        HStack(spacing: 20) {
            Postmark(date: sentAt, place: place, ink: ink, size: 86)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(sentAt.shortDate) 寄出")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                HStack(spacing: 6) {
                    Text("在路上")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .overlay(Capsule().strokeBorder(ink.opacity(0.7), lineWidth: 0.8))
                    if hasOthers {
                        Text("还有别的信也在路上")
                            .font(theme.labelFont)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                Text("回信会在三天内寄到你的信箱")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 退回来的信：后台重试也寄不出去（或者重试也没用，比如内容审核没过），信就「退回」邮筒页。
/// 可以重新寄，也可以不寄了（不寄了的那几篇日记回到「要寄的日记」里）
struct ReturnedLetterCard: View {
    let palette: LetterPalette
    let ink: Color
    let sentAt: Date
    /// 为什么没寄出去；nil 时只说没寄出去
    let reason: String?
    let onResend: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ReturnStamp(ink: ink)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(sentAt.shortDate) 寄出的信退回来了")
                    .font(.custom("Georgia", size: 15))
                    .foregroundStyle(palette.ink)
                if let reason, !reason.isEmpty {
                    Text(verbatim: reason)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.ink.opacity(0.6))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 22) {
                    Button(action: onResend) {
                        Text("重新寄出")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.liner)
                    }
                    Button(action: onDiscard) {
                        Text("不寄了")
                            .font(.system(size: 14))
                            .foregroundStyle(palette.ink.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            Rectangle()
                .fill(palette.paper)
                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
        )
    }
}

/// 「退回」的长方戳，盖歪一点
private struct ReturnStamp: View {
    let ink: Color

    var body: some View {
        Text("退回")
            .font(.system(size: 13, weight: .heavy))
            .tracking(2)
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(ink, lineWidth: 1.6)
            )
            .rotationEffect(.degrees(-8))
            .opacity(0.85)
            .accessibilityHidden(true)
    }
}
