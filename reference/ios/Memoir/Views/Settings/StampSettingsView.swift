import SwiftUI

struct StampSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("stampMode") private var stampMode: String = StampMode.weather.rawValue

    var body: some View {
        let theme = themeManager.current
        List {
            // 预览
            Section {
                HStack {
                    Spacer()
                    previewCircle(theme: theme)
                    Spacer()
                }
                .listRowBackground(theme.cardBackground)
            }

            // 模式选择
            Section {
                ForEach(StampMode.allCases, id: \.rawValue) { mode in
                    Button {
                        withAnimation { stampMode = mode.rawValue }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(modeName(mode))
                                    .font(theme.bodyFont)
                                    .foregroundStyle(theme.textPrimary)
                                Text(modeDescription(mode))
                                    .font(theme.labelFont)
                                    .foregroundStyle(theme.textTertiary)
                            }
                            Spacer()
                            if stampMode == mode.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(theme.accent)
                            }
                        }
                    }
                    .listRowBackground(theme.cardBackground)
                }
            } header: {
                Text("印章模式")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("日记印章")
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func previewCircle(theme: any AppTheme) -> some View {
        let mode = StampMode(rawValue: stampMode) ?? .weather
        ZStack {
            switch mode {
            case .weather:
                Image(systemName: "sun.max")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.textSecondary)
            case .mood:
                Image(systemName: "leaf")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.textSecondary)
            case .emoji:
                Text("😊")
                    .font(.system(size: 22))
            case .none:
                EmptyView()
            }
        }
        .frame(width: 44, height: 44)
        .overlay(
            Circle()
                .stroke(theme.border, lineWidth: 1)
                .opacity(mode == .none ? 0.3 : 1)
        )
    }

    private func modeName(_ mode: StampMode) -> LocalizedStringKey {
        switch mode {
        case .weather: return "天气"
        case .mood: return "心情图标"
        case .emoji: return "自选表情"
        case .none: return "不显示"
        }
    }

    private func modeDescription(_ mode: StampMode) -> LocalizedStringKey {
        switch mode {
        case .weather: return "自动显示写日记时的天气"
        case .mood: return "显示当前心情对应的图标"
        case .emoji: return "显示自选的表情符号"
        case .none: return "隐藏右上角印章圆圈"
        }
    }
}
