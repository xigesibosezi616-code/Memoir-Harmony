import SwiftUI

/// 设置页 - 选择插入照片时的默认相纸样式
struct DefaultPaperStylePickerView: View {
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("defaultPaperStyle") private var defaultPaperStyleRaw: String = PaperStyle.polaroid.rawValue
    @Environment(StoreKitManager.self) private var store
    @State private var showPaywall = false

    var body: some View {
        let theme = themeManager.current
        List {
            Section {
                ForEach(PaperStyle.allCases, id: \.self) { style in
                    let locked = style.isMemberOnly && !store.isMember
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        // 会员款：问要不要开通，不改默认（尺素会员）
                        if locked { showPaywall = true } else { defaultPaperStyleRaw = style.rawValue }
                    } label: {
                        HStack(spacing: 12) {
                            Text(style.displayName)
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.textPrimary)
                            if locked { MemberBadge(size: 16) }
                            Spacer()
                            // 按实际生效的那个打勾：会员到期后，存着的会员款其实已退回宝丽来
                            if PaperStyle.defaultStyle(raw: defaultPaperStyleRaw, isMember: store.isMember) == style {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(theme.accent)
                            }
                        }
                    }
                    .listRowBackground(themeManager.settingsCard)
                }
            } header: {
                Text("默认样式")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            } footer: {
                Text("插入新照片时会预先选中该样式；在插入流程里仍可临时更改。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .paywallCover(isPresented: $showPaywall)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(themeManager.settingsPage)
        .tint(theme.accent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("照片相纸样式")
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}
