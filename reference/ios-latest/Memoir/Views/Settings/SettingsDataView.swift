import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 设置 →「数据与备份」二级页。
struct SettingsDataView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext

    /// CloudKit 同步的真实状态（不是「系统登没登 iCloud」）
    private var syncMonitor: CloudSyncMonitor { env.cloudSync }

    @AppStorage("syncLivePhotoVideos") private var syncLivePhotoVideos: Bool = true

    @State private var showBackupExport = false
    @State private var showBackupPicker = false
    @State private var pickedBackup: BackupFileRef?
    /// 媒体占用统计。nil = 还没算完（扫盘要遍历目录，不放在 body 里同步做）
    @State private var mediaUsage: MediaStorage.Usage?
    @State private var showReclaimConfirm = false

    /// Info.plist 里声明的自有 UTI。万一没注册上就退回 `.data`，
    /// 顶多是文件选择器里能选的东西变多，总好过用户根本选不中自己的备份包。
    private static let backupContentType: UTType = UTType("com.sinaratech.memoir.backup") ?? .data

    var body: some View {
        let theme = themeManager.current
        SettingsSubpage(title: "数据与备份") {
            Section {
                // 同步由 CloudKit 托管，没有「开关」可言。
                //
                // 🔴 **这里报的必须是真实同步状态，不能只看系统登没登 iCloud。**
                // 2026-08-12 出过一次数据丢失：当时这行显示「已开启」，
                // 实际判据只是 `ubiquityIdentityToken != nil`（系统有 iCloud 账户），
                // 而用户的数据一次都没成功上传过 —— 卸载重装后全没了。
                // 现在的判据是 `CloudSyncMonitor.hasEverExported`：
                // **同步引擎真的成功导出过至少一次**。
                HStack {
                    SettingsRow(
                        icon: syncMonitor.isProtected ? "checkmark.icloud" : "exclamationmark.icloud",
                        title: "iCloud 同步",
                        theme: theme
                    )
                    Spacer()
                    Text(syncStatusText)
                        .font(theme.captionFont)
                        .foregroundStyle(syncMonitor.isProtected ? theme.accent : theme.destructive)
                }
                .listRowBackground(themeManager.settingsCard)

                Text(syncStatusDetail)
                    .font(theme.labelFont)
                    .foregroundStyle(syncMonitor.isProtected ? theme.textTertiary : theme.destructive)
                    .listRowBackground(themeManager.settingsCard)

                HStack {
                    SettingsRow(icon: "livephoto", title: "同步 Live Photo 视频", theme: theme)
                    Spacer()
                    Toggle("", isOn: $syncLivePhotoVideos)
                        .labelsHidden()
                        .tint(theme.accent)
                }
                .listRowBackground(themeManager.settingsCard)
                if !syncLivePhotoVideos {
                    Text("关闭后，Live Photo 在其他设备只显示静态图。")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                        .listRowBackground(themeManager.settingsCard)
                }

                Button {
                    showBackupExport = true
                } label: {
                    HStack {
                        SettingsRow(icon: "square.and.arrow.up", title: "导出备份", theme: theme)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .listRowBackground(themeManager.settingsCard)

                Button {
                    showBackupPicker = true
                } label: {
                    HStack {
                        SettingsRow(icon: "square.and.arrow.down", title: "导入备份", theme: theme)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .listRowBackground(themeManager.settingsCard)

                // 存储占用：照片 / 录音是磁盘上的独立文件，不在数据库里，
                // 没有这一行的话用户完全不知道尺素占了多少、更没有入口清理
                HStack {
                    SettingsRow(icon: "internaldrive", title: "照片与录音占用", theme: theme)
                    Spacer()
                    Text(mediaUsage.map { formatBytes($0.totalBytes) } ?? "统计中…")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }
                .listRowBackground(themeManager.settingsCard)

                if let usage = mediaUsage, usage.orphanCount > 0 {
                    Button {
                        showReclaimConfirm = true
                    } label: {
                        HStack {
                            SettingsRow(
                                icon: "sparkles",
                                title: "清理 \(usage.orphanCount) 个残留文件",
                                theme: theme
                            )
                            Spacer()
                            Text(formatBytes(usage.orphanBytes))
                                .font(theme.captionFont)
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .listRowBackground(themeManager.settingsCard)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("导入只会新增日记，已经有的会自动跳过。备份包也可以在微信或「文件」里直接点开。")
                    if let usage = mediaUsage, usage.orphanCount > 0 {
                        Text("残留文件是已删日记留下的照片或录音，不再属于任何一篇日记，清理不会影响现有内容。")
                    }
                }
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
            }
        }
        .sheet(isPresented: $showBackupExport) {
            BackupExportView()
        }
        // 也放开 .zip：不加密的备份包本身就是标准 zip，用户为了看一眼里面
        // 把它改名成 .zip 之后，还应该能原样导回来。
        .fileImporter(
            isPresented: $showBackupPicker,
            allowedContentTypes: [Self.backupContentType, .zip]
        ) { result in
            switch result {
            case .success(let url):
                pickedBackup = BackupFileRef(url: url)
            case .failure(let error):
                env.errors.present(error, fallback: "打不开这个文件")
            }
        }
        .sheet(item: $pickedBackup) { picked in
            BackupImportView(fileURL: picked.url)
        }
        .confirmationDialog(
            mediaUsage.map { "清理 \($0.orphanCount) 个残留文件，释放 \(formatBytes($0.orphanBytes))？" } ?? "清理残留文件？",
            isPresented: $showReclaimConfirm,
            titleVisibility: .visible
        ) {
            Button("清理", role: .destructive) {
                MediaStorage.reclaimOrphans(in: modelContext)
                mediaUsage = MediaStorage.usage(in: modelContext)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这些文件不属于任何一篇现存日记，删除不会影响你的内容。")
        }
        .task {
            // 扫盘统计媒体占用。放 task 里而不是 body，避免每次重绘都遍历目录
            mediaUsage = MediaStorage.usage(in: modelContext)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    /// 同步状态一句话。**只有真的成功导出过才敢说「已同步」。**
    private var syncStatusText: LocalizedStringKey {
        switch syncMonitor.account {
        case .checking:               return "检查中"
        case .noAccount:              return "未登录 iCloud"
        case .restricted:             return "iCloud 受限"
        case .temporarilyUnavailable: return "iCloud 暂不可用"
        case .failed:                 return "同步异常"
        case .available:
            return syncMonitor.hasEverExported ? "已同步" : "尚未备份"
        }
    }

    /// 状态详情。**没同步成功时必须说清后果**，别让用户以为数据安全。
    private var syncStatusDetail: LocalizedStringKey {
        switch syncMonitor.account {
        case .checking:
            return "正在检查 iCloud 状态…"
        case .noAccount:
            return "当前未登录 iCloud，日记只保存在这台设备上，卸载 App 就会丢失。在系统「设置 → Apple 账户」登录后会自动开始同步。"
        case .restricted, .temporarilyUnavailable:
            return "系统暂时不允许访问 iCloud，日记目前只在这台设备上。建议先到「导出备份」存一份到本地。"
        case .failed:
            return "iCloud 连接异常，日记目前只在这台设备上。建议先到「导出备份」存一份，再到系统设置检查 iCloud。"
        case .available:
            return syncMonitor.hasEverExported
                ? "日记会自动同步到你的 iCloud，换设备时不会丢。内容存在你自己的账户里，我们看不到。"
                : "⚠️ 还没有成功备份到 iCloud，此刻卸载 App 会丢失全部日记。刚写完的内容需要一点时间上传；若长时间停在这里，请先「导出备份」存一份到本地。"
        }
    }
}
