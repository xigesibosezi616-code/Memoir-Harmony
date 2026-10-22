import SwiftUI
import SwiftData

/// `.sheet(item:)` 要 Identifiable，`URL` 不是。两个导入入口都用它把 URL 包一层。
struct BackupFileRef: Identifiable {
    let id = UUID()
    let url: URL
}

/// 导入备份包。
///
/// 两个入口都走这里：在微信 /「文件」里点开 `.memoir`（`ContentView` 的 `.onOpenURL`），
/// 或设置 → 数据 → 导入备份（文件选择器）。
///
/// 顺序和导出页镜像：**先让用户看清「这个包是什么、什么时候导出的」，再决定导不导**。
/// 但语气不一样 —— 导出是把数据交出去，要警告；导入只增不减，
/// 所以这一步只需说清「已有的会跳过」，不必吓唬人。
struct BackupImportView: View {
    let fileURL: URL

    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case opening
        case askPassword
        case ready
        case importing
        case finished
    }

    @State private var phase: Phase = .opening
    @State private var password = ""
    @State private var passwordFailed = false
    @State private var package: BackupImporter.Package?
    @State private var summary: BackupImporter.Summary?
    /// 包里与本机同名、且两边都有日记的日记本。非空时先问用户合并还是分开，再导入
    @State private var tagConflicts: [String] = []

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            List {
                switch phase {
                case .opening:
                    busySection("正在打开备份包…", theme: theme)
                case .askPassword:
                    passwordSection(theme: theme)
                case .ready:
                    packageSection(theme: theme)
                    confirmSection(theme: theme)
                case .importing:
                    busySection("正在导入…", theme: theme)
                case .finished:
                    resultSection(theme: theme)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(phase == .importing)
            .alert(
                "有同名的日记本",
                isPresented: Binding(
                    get: { !tagConflicts.isEmpty },
                    set: { if !$0 { tagConflicts = [] } }
                )
            ) {
                Button("合并到同名日记本") { Task { await runImport(tagPolicy: .merge) } }
                Button("作为新日记本导入") { Task { await runImport(tagPolicy: .keepSeparate) } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("备份包中这些日记本与这台设备上的重名：\(conflictListText)。若作为新日记本导入，名字后面会加上序号。")
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("导入备份")
                        .font(theme.labelFont)
                        .tracking(theme.letterSpacingWide)
                        .foregroundStyle(theme.textSecondary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .importing {
                        Button(phase == .finished ? "完成" : "取消") { dismiss() }
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
        .task {
            await openPackage(password: nil)
        }
        .onDisappear {
            // 解压出来的临时文件和系统丢进 Inbox 的那份副本都得清掉，
            // 不然用户每导一次就在沙箱里多压几十 MB 死文件。
            if let package { BackupImporter.discard(package) }
            BackupImporter.cleanUpInboxCopy(of: fileURL)
        }
    }

    // MARK: 进行中

    private func busySection(_ title: String, theme: any AppTheme) -> some View {
        Section {
            HStack(spacing: 10) {
                Spacer()
                ProgressView().tint(theme.accent)
                Text(title)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                Spacer()
            }
            .padding(.vertical, 8)
            .listRowBackground(theme.cardBackground)
        } footer: {
            if phase == .importing {
                Text("导入过程中请不要退出尺素。")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    // MARK: 要密码

    private func passwordSection(theme: any AppTheme) -> some View {
        Section {
            SecureField("备份包密码", text: $password)
                .font(theme.captionFont)
                .submitLabel(.go)
                .onSubmit { unlock() }
                .listRowBackground(theme.cardBackground)

            if passwordFailed {
                Text("密码不对，再试一次")
                    .font(theme.labelFont)
                    .foregroundStyle(.red.opacity(0.8))
                    .listRowBackground(theme.cardBackground)
            }

            Button(action: unlock) {
                HStack {
                    Spacer()
                    Text("解锁")
                        .font(theme.captionFont)
                        .foregroundStyle(password.isEmpty ? theme.textTertiary : theme.accent)
                    Spacer()
                }
            }
            .disabled(password.isEmpty)
            .listRowBackground(theme.cardBackground)
        } header: {
            Text("这个备份包加密了")
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
        } footer: {
            Text("请输入导出时设置的密码。密码只在这台设备上用于解开文件，不会上传。")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: 包里有什么

    @ViewBuilder
    private func packageSection(theme: any AppTheme) -> some View {
        if let manifest = package?.manifest {
            Section {
                row("日记", "\(manifest.counts.entries) 篇", theme: theme)
                if manifest.counts.letters > 0 {
                    row("来信", "\(manifest.counts.letters) 封", theme: theme)
                }
                row("照片与录音",
                    manifest.includesMedia ? "\(manifest.counts.media) 个" : "未包含",
                    theme: theme)
                if manifest.exportedAt > .distantPast {
                    row("导出时间", Self.dateFormatter.string(from: manifest.exportedAt), theme: theme)
                }
                row("来自", sourceDescription(manifest), theme: theme)
            } header: {
                Text("备份包内容")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            } footer: {
                if !manifest.includesMedia {
                    Text("这是「仅文字」的备份，导入后日记里不会有照片和录音。")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private func confirmSection(theme: any AppTheme) -> some View {
        Section {
            Button {
                startImport()
            } label: {
                HStack {
                    Spacer()
                    Text("开始导入")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.accent)
                    Spacer()
                }
            }
            .listRowBackground(theme.cardBackground)
        } footer: {
            Text("导入只会新增。已经在这台设备上的日记会自动跳过，不会覆盖，也不会删掉你现在的任何内容。")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: 结果

    @ViewBuilder
    private func resultSection(theme: any AppTheme) -> some View {
        if let summary {
            Section {
                row("新增日记", "\(summary.entriesImported) 篇", theme: theme)
                if summary.entriesSkipped > 0 {
                    row("跳过（已存在）", "\(summary.entriesSkipped) 篇", theme: theme)
                }
                if summary.lettersImported > 0 {
                    row("新增来信", "\(summary.lettersImported) 封", theme: theme)
                }
                if summary.tagsImported > 0 {
                    row("新增日记本", "\(summary.tagsImported) 个", theme: theme)
                }
                if summary.missingMedia > 0 {
                    Label(
                        "有 \(summary.missingMedia) 张照片或录音在备份包里找不到，对应的日记其余内容已照常导入。",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textSecondary)
                    .listRowBackground(theme.cardBackground)
                }
            } header: {
                Text(summary.entriesImported > 0 ? "导入完成" : "没有需要新增的")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            } footer: {
                Text(summary.entriesImported > 0
                     ? "可以回到日记本看看了。"
                     : "这个备份包里的日记，这台设备上都已经有了。")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    // MARK: 动作

    private func unlock() {
        guard !password.isEmpty else { return }
        Task { await openPackage(password: password) }
    }

    /// 解密 + 解压 + 读 manifest。
    /// 放 `Task.detached` 里跑：PBKDF2 二十多万轮加上百 MB 的解压，
    /// 留在主线程上会让整个面板卡住不动。
    private func openPackage(password: String?) async {
        phase = .opening
        do {
            let opened = try await Task.detached(priority: .userInitiated) { [fileURL] in
                try BackupImporter.open(fileURL: fileURL, password: password)
            }.value
            package = opened
            passwordFailed = false
            phase = .ready
        } catch BackupImporter.ImportError.needsPassword {
            phase = .askPassword
        } catch BackupImporter.ImportError.wrongPassword {
            passwordFailed = true
            phase = .askPassword
        } catch {
            env.errors.present(error, fallback: "打开备份包失败")
            dismiss()
        }
    }

    /// 有同名日记本就先弹窗问（弹窗里的按钮再调 `runImport`），没有就直接导
    private func startImport() {
        guard let package else { return }
        let conflicts = BackupImporter.tagConflicts(in: package, context: modelContext)
        if conflicts.isEmpty {
            Task { await runImport(tagPolicy: .merge) }
        } else {
            tagConflicts = conflicts
        }
    }

    private func runImport(tagPolicy: BackupImporter.TagConflictPolicy) async {
        guard let package else { return }
        tagConflicts = []
        phase = .importing
        do {
            summary = try BackupImporter.merge(package, into: modelContext, tagPolicy: tagPolicy)
            phase = .finished
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            env.errors.present(error, fallback: "导入失败")
            phase = .ready
        }
    }

    // MARK: 小组件

    /// 同名日记本的列表，按 App 选的语言连接（中文用「、」，英文用逗号加 and ……）
    private var conflictListText: String {
        let formatter = ListFormatter()
        formatter.locale = appLocale
        return formatter.string(from: tagConflicts) ?? tagConflicts.joined(separator: ", ")
    }

    private func sourceDescription(_ manifest: BackupManifest) -> String {
        // 返回 String 会被 Text(String) 直接渲染，不查本地化表 —— 必须显式 NSLocalizedString。
        // 「iPhone」是产品名不翻；另两个是文案
        let platform: String
        switch manifest.platform {
        case "ios":     platform = "iPhone"
        case "harmony": platform = NSLocalizedString("鸿蒙设备", bundle: .appLanguage, comment: "备份包来源设备")
        default:        platform = NSLocalizedString("其他设备", bundle: .appLanguage, comment: "备份包来源设备")
        }
        return String(
            format: NSLocalizedString("%1$@ · 尺素 %2$@", bundle: .appLanguage, comment: "备份包来源，%1$@ 是设备，%2$@ 是 App 版本号"),
            platform, manifest.appVersion
        )
    }

    private func row(_ title: String, _ value: String, theme: any AppTheme) -> some View {
        HStack {
            Text(title)
                .font(theme.captionFont)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Text(value)
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
        }
        .listRowBackground(theme.cardBackground)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
