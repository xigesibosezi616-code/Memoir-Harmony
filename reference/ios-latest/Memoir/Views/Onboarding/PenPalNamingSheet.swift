import SwiftUI

/// 老用户补起名：首启时起名还能跳过（2026-10-24 之前），那时没起名的人现在笔友还没有名字 ——
/// 打开 App 时弹这一页请他起一次，起好才能关（`ContentView` 里按 `PenPalName.needsNaming` 弹）。
/// 新用户在首启页（`OnboardingView`）就必须起名，走不到这里
struct PenPalNamingSheet: View {
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage(PenPalName.storageKey) private var penPalName: String = ""
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 18) {
            Text("给笔友起个名字")
                .font(theme.headingFont)
                .foregroundStyle(theme.textPrimary)

            TextField("写一个名字", text: $draft)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 0.5))
                .padding(.horizontal, 40)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(save)
                .onChange(of: draft) { _, new in
                    if new.count > PenPalName.maxLength { draft = String(new.prefix(PenPalName.maxLength)) }
                }

            Text("笔友会用这个名字给你写信，之后在设置里也能改")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: save) {
                Text("好了")
                    .font(theme.headingFont)
                    .foregroundStyle(theme.cardBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(PenPalName.needsNaming(draft) ? 0.4 : 1)
            }
            .disabled(PenPalName.needsNaming(draft))
            .padding(.horizontal, 40)
            .padding(.top, 6)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
        .presentationDetents([.medium])
        // 起好名字才能关
        .interactiveDismissDisabled()
        .onAppear { focused = true }
    }

    private func save() {
        guard !PenPalName.needsNaming(draft) else { return }
        // 存进去以后 `needsNaming` 变成 false，`ContentView` 那边的只读绑定随之把这一页收起
        penPalName = PenPalName.normalized(draft)
    }
}
