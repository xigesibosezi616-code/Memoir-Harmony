import SwiftUI

/// 设置 →「位置与天气」二级页。
///
/// 关掉「记录位置」只影响日记里记不记地点，**天气照常获取**。
struct SettingsLocationView: View {
    @Environment(ThemeManager.self) private var themeManager

    /// 是否在日记里记录位置（关掉只影响地点，天气照常）
    @AppStorage(LocationPrecision.enabledKey) private var locationRecordingEnabled: Bool = true
    /// 位置精细程度：市 / 区县 / 街道
    @AppStorage(LocationPrecision.storageKey) private var locationPrecisionRaw: String = LocationPrecision.city.rawValue

    private var currentLocationPrecision: LocationPrecision {
        LocationPrecision(rawValue: locationPrecisionRaw) ?? .city
    }

    var body: some View {
        let theme = themeManager.current
        SettingsSubpage(title: "位置与天气") {
            Section {
                HStack {
                    SettingsRow(icon: "location", title: "记录位置", theme: theme)
                    Spacer()
                    Toggle("", isOn: $locationRecordingEnabled)
                        .labelsHidden()
                        .tint(theme.accent)
                }
                .listRowBackground(theme.cardBackground)

                if locationRecordingEnabled {
                    HStack {
                        SettingsRow(icon: "scope", title: "位置精度", theme: theme)
                        Spacer()
                        Picker("", selection: $locationPrecisionRaw) {
                            ForEach(LocationPrecision.allCases, id: \.rawValue) { level in
                                Text(level.displayName).tag(level.rawValue)
                            }
                        }
                        .labelsHidden()
                        .tint(theme.textTertiary)
                    }
                    .listRowBackground(theme.cardBackground)

                    Text(currentLocationPrecision.detail)
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                        .listRowBackground(theme.cardBackground)
                }
            } footer: {
                Text("位置只记在这台设备的日记里，不会上传。修改只影响之后写的日记。")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}
