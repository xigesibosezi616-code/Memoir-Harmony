import SwiftUI
import SwiftData

struct EditEntryView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var entry: JournalEntry
    @State private var title: String
    /// 正文按**块结构**编辑，不能只编辑扁平的 `entry.content`。
    ///
    /// 曾经这里是一个 `TextEditor(text: $content)`，保存时写 `entry.content` ——
    /// 但 `contentBlocks` 的 getter 只要 `contentBlocksData` 有值就**完全无视 `content`**，
    /// 于是用户改完正文、退出来一看还是老样子，**改动被静默丢弃**。
    /// 示例数据（`contentBlocksData` 为 nil）反而是好的，所以一直没被发现。
    @State private var blocks: [ContentBlock]
    /// 工具栏遥控编辑器（加粗 / 斜体 / 小标题 / 插照片）
    @State private var editor = RichTextController()
    /// 正在走的加照片流程（相机 / 相册），见 `PhotoInsertFlow`
    @State private var insertSource: PhotoInsertSource?
    /// 正在换相纸的照片
    @State private var restylingPhoto: ContentBlock?
    /// 这次新落盘的照片文件。点 ✕ 放弃时清掉；保存时没被用上的也清掉
    @State private var insertedMediaNames: Set<String> = []
    /// 进来时这篇已有的照片文件。在正文里删掉、并且保存了，才真的删文件
    private let originalPhotoNames: Set<String>
    @State private var didSave = false
    /// 这次编辑开始的时刻：这次写的字、放进来的照片录音都记成这时写的（补记、墨迹会干，见 `Ink`）
    @State private var sessionDate = Date.now
    @State private var selectedTags: [String]
    /// 进来时这篇的录音清单。正文里删掉、并且保存了，才真的删文件
    private let originalAudio: Set<String>
    /// 这次录的音。没保存就离开、或录了又删掉的，清掉文件
    @State private var recordedAudio: Set<String> = []
    @State private var showDeleteAlert = false
    @State private var showVoiceRecording = false

    init(entry: JournalEntry) {
        self.entry = entry
        _title = State(initialValue: entry.title)
        // getter 会替我们处理老数据：没有块结构时降级成单一文本块
        let existing = entry.contentBlocks
        // 2026-10-10 之前的录音在正文外面，打开编辑时补到正文末尾（之后就跟着正文走）
        let withAudio = (existing.isEmpty ? [ContentBlock(text: "")] : existing).withLooseAudio(entry.audioURLs)
        _blocks = State(initialValue: withAudio)
        originalAudio = Set(entry.audioURLs)
        originalPhotoNames = Self.photoFileNames(in: existing)
        // 单本规则（见 `JournalEntry.singleNotebook`）：老数据里多于一本的，这里显示为没选
        _selectedTags = State(initialValue: JournalEntry.singleNotebook(entry.tags))
    }

    private var totalCharCount: Int {
        blocks.compactMap { $0.type == .text ? $0.text?.count : nil }.reduce(0, +)
    }

    private var isContentEmpty: Bool {
        blocks.allSatisfy { $0.type != .photo && ($0.text ?? "").isEmpty }
    }

    private var photoCount: Int { blocks.filter { $0.type == .photo }.count }

    private static func photoFileNames(in blocks: [ContentBlock]) -> Set<String> {
        Set(blocks.flatMap { [$0.photoFilename, $0.livePhotoVideoFilename, $0.livePhotoStillFilename] }
            .compactMap { $0 })
    }

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(entry.date.dayAndWeekday)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textTertiary)
                            .tracking(theme.letterSpacingWide)

                        // 可换行（最多三行）—— 与详情页、书封面的实际呈现一致；
                        // 单行 TextField 会横向滚动，长标题在写的时候看不全
                        TextField("标题（可选）", text: $title, axis: .vertical)
                            .font(theme.titleFont)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1...3)
                            .onChange(of: title) { _, newValue in
                                let clean = JournalEntry.sanitizedTitle(newValue)
                                if clean != newValue { title = clean }
                            }

                        contentBlocksSection(theme: theme)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("收进日记本")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                            TagSelector(selectedTags: $selectedTags)
                        }

                        // Delete button
                        Button {
                            showDeleteAlert = true
                        } label: {
                            Text("删除这篇日记")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.destructive)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .padding(.top, 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }

                // 底部工具栏：格式 | 相机 / 相册 / 录音 —— 与写日记页一致
                HStack(spacing: 0) {
                    RichFormatButtons(controller: editor, theme: theme)
                    Rectangle()
                        .fill(theme.textTertiary.opacity(0.25))
                        .frame(width: 0.5, height: 20)
                        .padding(.horizontal, 10)
                    toolbarIcon("camera", enabled: photoCount < 5, theme: theme) { insertSource = .camera }
                        .accessibilityLabel(Text("拍照"))
                    toolbarIcon("photo", enabled: photoCount < 5, theme: theme) { insertSource = .library }
                        .accessibilityLabel(Text("从相册选照片"))
                    toolbarIcon("mic", enabled: blocks.audioPaths.count < 3, theme: theme) { showVoiceRecording = true }
                        .accessibilityLabel(Text("录音"))
                    Spacer(minLength: 8)
                    Text("\(totalCharCount) 字")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial)
            }
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 🔴 这里用 ✕ 而不是写日记页的 ‹ —— 行为不一样：
                    // 写日记页退出会存草稿，**这一页退出是丢弃这次编辑**，glyph 要诚实
                    CircleIconButton(systemName: "xmark", prominence: .glass, theme: theme, size: 13) {
                        dismiss()
                    }
                }
                // 「完成」从底部栏挪到这里，与写日记页同一个位置、同一种分量
                ToolbarItem(placement: .confirmationAction) {
                    CircleIconButton(systemName: "checkmark", prominence: .glass, theme: theme, size: 14) {
                        save()
                        dismiss()
                    }
                }
            }
            .alert("删除日记", isPresented: $showDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    // 照片和录音是沙盒里的独立文件，不随 SwiftData 一起删
                    entry.deleteAssociatedMedia()
                    modelContext.delete(entry)
                    try? modelContext.save()
                    dismiss()
                }
            } message: {
                Text("确定要删除这篇日记吗？此操作不可撤销。")
            }
            .sheet(isPresented: $showVoiceRecording) {
                VoiceRecordingSheet { audioPath in
                    // 录音放在光标的下一行（同写日记页）
                    recordedAudio.insert(audioPath)
                    editor.insertAudio(path: audioPath)
                }
            }
            .photoInsertFlow(
                source: $insertSource,
                restyling: $restylingPhoto,
                theme: theme,
                onInsert: { editor.insertPhoto($0) },
                onRestyle: { editor.updatePhoto($0) },
                onFilesCreated: { insertedMediaNames.formUnion($0) }
            )
        }
        // 没保存就离开（点 ✕）：这次新加的照片、录音文件不留
        .onDisappear {
            guard !didSave else { return }
            for name in insertedMediaNames { PhotoPaperIO.deleteImage(name) }
            for relative in recordedAudio {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appending(path: relative))
            }
        }
    }

    /// 底部工具栏图标：统一尺寸与触控区，禁用态只降透明度不换色系（同写日记页）
    private func toolbarIcon(_ systemName: String, enabled: Bool, theme: any AppTheme,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(theme.textSecondary)
                .opacity(enabled ? 1 : 0.35)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
    }

    // MARK: - 正文

    /// 与写日记页同一个编辑器：一整篇连续的图文，照片可以在这里加、挪、换相纸、删
    @ViewBuilder
    private func contentBlocksSection(theme: any AppTheme) -> some View {
        let appearance = RichTextAppearance.forTheme(id: themeManager.currentThemeID, theme: theme)
        ZStack(alignment: .topLeading) {
            if isContentEmpty {
                Text("今天，我想说...")
                    .font(appearance.bodyFont)
                    .foregroundStyle(theme.textTertiary)
                    .allowsHitTesting(false)
            }
            RichEntryEditor(
                blocks: $blocks,
                controller: editor,
                appearance: appearance,
                writtenDate: entry.createdAt,
                sessionDate: sessionDate,
                onRequestPaperStyle: { restylingPhoto = $0 }
            )
        }
    }

    // MARK: - 保存

    private func save() {
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.tags = selectedTags

        // 去掉纯空白文本块（保留照片、录音）；若全空则保底一个空文本块 —— 与 ComposeView.save 一致
        let cleaned = blocks.filter { block in
            if block.type != .text { return true }
            return !(block.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        // ⚠️ 必须走 contentBlocks 的 setter：它同步 contentBlocksData / content / wordCount / updatedAt。
        // 直接写 entry.content 是无效的（getter 优先读 contentBlocksData），那正是本页原来的 bug。
        let finalBlocks = cleaned.isEmpty ? [ContentBlock(text: "")] : cleaned
        entry.contentBlocks = finalBlocks
        // 录音清单由正文里的录音生成（同步、备份、删日记时清文件都认这份清单）
        entry.audioURLs = finalBlocks.audioPaths

        try? modelContext.save()
        didSave = true

        // 正文里删掉的照片（原有的、这次新加又删的）这时才真删文件
        let referenced = Self.photoFileNames(in: finalBlocks)
        for name in originalPhotoNames.union(insertedMediaNames) where !referenced.contains(name) {
            PhotoPaperIO.deleteImage(name)
        }
        let keptAudio = Set(finalBlocks.audioPaths)
        for relative in originalAudio.union(recordedAudio) where !keptAudio.contains(relative) {
            try? FileManager.default.removeItem(at: URL.documentsDirectory.appending(path: relative))
        }
    }
}
