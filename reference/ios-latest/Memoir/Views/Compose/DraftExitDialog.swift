import SwiftUI

/// 写日记页按返回时的确认弹窗：不保存 / 保存草稿。
///
/// **为什么不用系统 `.alert` / `.confirmationDialog`**：那两个的按钮颜色由系统 tint 决定，
/// 做不出「浅色的次要动作 + 主题对比色的主要动作」这种分量差别，
/// 也接不上尺素的三套主题（和纸 / 北欧 / 皮革各有自己的配色）。
///
/// **点遮罩 = 取消**，回到编辑。返回键难免误触，不该逼用户在"丢弃"和"保存"之间二选一。
struct DraftExitDialog: View {
    let theme: any AppTheme
    let onDiscard: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Text("保存这篇草稿？")
                        .font(theme.headingFont)
                        .foregroundStyle(theme.textPrimary)
                    Text("保存后，下次写日记可以接着写")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    // 次要动作：浅色，不抢视线
                    Button(action: onDiscard) {
                        Text("不保存")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(theme.surfaceBackground, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(theme.border, lineWidth: 0.5)
                            )
                    }

                    // 主要动作：主题对比色，与右上角对勾按钮同一套配色
                    Button(action: onSave) {
                        Text("保存草稿")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.cardBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 26)
            .frame(maxWidth: 320)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
            .padding(.horizontal, 40)
        }
    }
}
