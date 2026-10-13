import SwiftUI
import SwiftData

/// 导出备份包。
///
/// 顺序刻意设计过：**先让用户看见"这里面是什么、有多大"，再决定加不加密，最后才是导出**。
/// 免责声明放在最后一步且必须勾选 —— 用户点导出的那一刻，应该完全清楚自己在把什么交出去。
struct BackupExportView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Query private var letters: [Letter]
    @Query private var tags: [Tag]
    @Query private var moods: [MoodTag]

    @State private var includesMedia = true
    @State private var useEncryption = true
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var acknowledged = false
    @State private var isExporting = false
    @State private var exported: BackupExporter.Result?

    /// 超过这个体积就提示别走微信（微信单文件上限约 100MB）
    private static let wechatLimitBytes = 80 * 1024 * 1024

    private var mediaBytes: Int {
        includesMedia ? BackupExporter.estimateMediaBytes(entries: entries, tags: tags) : 0
    }

    private var passwordValid: Bool {
        !useEncryption || (password.count >= 4 && password == passwordConfirm)
    }

    private var canExport: Bool {
        !entries.isEmpty && acknowledged && passwordValid && !isExporting
    }

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            List {
                contentSection(theme: theme)
                encryptionSection(theme: theme)
                disclaimerSection(theme: theme)
                exportSection(theme: theme)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("导出备份")
                        .font(theme.labelFont)
                        .tracking(theme.letterSpacingWide)
                        .foregroundStyle(theme.textSecondary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    // MARK: 包含什么

    private func contentSection(theme: any AppTheme) -> some View {
        Section {
            row("日记", "\(entries.count) 篇", theme: theme)
            if !letters.isEmpty {
                row("来信", "\(letters.count) 封", theme: theme)
            }
            HStack {
                settingsLabel("照片与录音", theme: theme)
                Spacer()
                Toggle("", isOn: $includesMedia)
                    .labelsHidden()
                    .tint(theme.accent)
            }
            .listRowBackground(theme.cardBackground)

            row("预计大小", formatBytes(mediaBytes), theme: theme)

            if includesMedia, mediaBytes > Self.wechatLimitBytes {
                Label(
                    "超过 80 MB，微信可能发不出去。建议用隔空投送，或关掉「照片与录音」只备份文字。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(theme.labelFont)
                .foregroundStyle(theme.textSecondary)
                .listRowBackground(theme.cardBackground)
            }
        } header: {
            Text("包含内容")
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
        } footer: {
            Text(includesMedia
                 ? "完整备份，可在新设备上原样恢复。"
                 : "只导出文字，体积很小；照片和录音不会包含在内。")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: 加密

    private func encryptionSection(theme: any AppTheme) -> some View {
        Section {
            HStack {
                settingsLabel("用密码加密", theme: theme)
                Spacer()
                Toggle("", isOn: $useEncryption)
                    .labelsHidden()
                    .tint(theme.accent)
            }
            .listRowBackground(theme.cardBackground)

            if useEncryption {
                SecureField("设置密码（至少 4 位）", text: $password)
                    .font(theme.captionFont)
                    .listRowBackground(theme.cardBackground)
                SecureField("再输一次", text: $passwordConfirm)
                    .font(theme.captionFont)
                    .listRowBackground(theme.cardBackground)

                if !password.isEmpty, !passwordConfirm.isEmpty, password != passwordConfirm {
                    Text("两次输入不一致")
                        .font(theme.labelFont)
                        .foregroundStyle(.red.opacity(0.8))
                        .listRowBackground(theme.cardBackground)
                }
            }
        } header: {
            Text("加密")
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
        } footer: {
            Text(useEncryption
                 ? "⚠️ 密码请务必记住。备份包只能用这个密码打开，忘记后我们也无法帮你找回。"
                 : "⚠️ 不加密的备份包，任何拿到文件的人都能直接看到你的全部日记。")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: 免责声明

    private func disclaimerSection(theme: any AppTheme) -> some View {
        Section {
            Button {
                acknowledged.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: acknowledged ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18))
                        .foregroundStyle(acknowledged ? theme.accent : theme.textTertiary)
                    Text("我已了解：这个文件包含我全部日记的原文、照片与录音。尺素不会看到它，也不会上传到任何服务器；一旦发送给他人或存到微信、网盘等第三方，它的安全就取决于那个平台。")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(theme.cardBackground)
        }
    }

    // MARK: 导出

    @ViewBuilder
    private func exportSection(theme: any AppTheme) -> some View {
        Section {
            if let exported {
                ShareLink(item: exported.fileURL) {
                    HStack {
                        Spacer()
                        Label("分享备份包（\(formatBytes(exported.byteCount))）", systemImage: "square.and.arrow.up")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.accent)
                        Spacer()
                    }
                }
                .listRowBackground(theme.cardBackground)
            } else {
                Button {
                    Task { await runExport() }
                } label: {
                    HStack {
                        Spacer()
                        if isExporting {
                            ProgressView().tint(theme.accent)
                            Text("正在打包…")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textSecondary)
                                .padding(.leading, 6)
                        } else {
                            Text("生成备份包")
                                .font(theme.captionFont)
                                .foregroundStyle(canExport ? theme.accent : theme.textTertiary)
                        }
                        Spacer()
                    }
                }
                .disabled(!canExport)
                .listRowBackground(theme.cardBackground)
            }
        } footer: {
            if exported != nil {
                Text("已生成。可以发给自己、存进「文件」，或用隔空投送传到另一台设备。")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    // MARK: 动作

    private func runExport() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let result = try BackupExporter.export(
                entries: entries,
                letters: letters,
                tags: tags,
                moods: moods,
                options: .init(
                    includesMedia: includesMedia,
                    password: useEncryption ? password : nil
                )
            )
            exported = result
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            env.errors.present(error, fallback: "导出失败")
        }
    }

    // MARK: 小组件

    private func row(_ title: String, _ value: String, theme: any AppTheme) -> some View {
        HStack {
            settingsLabel(title, theme: theme)
            Spacer()
            Text(value)
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
        }
        .listRowBackground(theme.cardBackground)
    }

    private func settingsLabel(_ title: String, theme: any AppTheme) -> some View {
        Text(title)
            .font(theme.captionFont)
            .foregroundStyle(theme.textPrimary)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}
