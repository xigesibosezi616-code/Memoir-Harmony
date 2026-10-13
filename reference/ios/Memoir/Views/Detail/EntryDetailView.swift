import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let entry: JournalEntry
    @State private var showEdit = false
    @State private var showDeleteAlert = false
    // MARK: 已嵌入照片的编辑流程（入口在全屏查看页右上角的「⋯」）
    @State private var editingPhotoBlockId: UUID?
    @State private var showStyleChangePicker = false
    @State private var editingImage: UIImage?

    // MARK: 嵌入照片的全屏查看
    /// 全屏查看的照片块（要整块而非只要文件名，Live Photo 还需要配对的 .mov）
    @State private var fullScreenPhoto: ContentBlock?

    @AppStorage("appLanguage") private var appLanguage: String = ""

    var body: some View {
        let theme = themeManager.current
        // 正文用 `RichEntryEditor`（只读）排，它按 ScrollView 给的宽度排版，不再自己量宽度。
        //
        // 📌 2026-09-05 的教训仍然成立：别在 ScrollView **里面**量宽度再回写给内容 ——
        // 内容撑大 → 量出更宽 → 内容再变大，一圈圈失控（那次是 `PHLivePhotoView` 撑大一次就停不下来）。
        // 以前的 `ContentBlockRenderer` 要一个外面量好的 `contentWidth`，现在不需要了。
        ScrollView {
            if themeManager.currentThemeID == "bamboo" {
                washiLayout(theme: theme)
            } else {
                defaultLayout(theme: theme)
            }
        }
        .background(theme.background)
        .navigationBarTitleDisplayMode(.inline)
        // 🔴 **这一页不放导航栏标题**（2026-09-27）。
        // 原先在 `.principal` 里放了一个「日记详情」，而 iOS 26 长按系统返回键会弹
        // 「返回历史」菜单、把返回键的玻璃容器横向展开 —— 系统只会让**它自己的**标题让位，
        // 管不到我们手动塞进 `.principal` 的自定义视图（UIKit 的 titleView 同理），
        // 于是那句标题被灰条罩住，看起来像坏了（真机实拍）。
        //
        // 页面本身已经有日期和大标题，导航栏那句本来就是冗余的，删掉最干净。
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button { showEdit = true } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(theme.textSecondary)
                    }
                    Button { showDeleteAlert = true } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color(hex: "#C0A080"))
                    }
                }
            }
        }
        // 全屏而非 sheet（2026-10-10 产品定）：改日记和写日记是同一张纸，不该是半截弹出来的卡片。
        // 全屏没有下滑关闭，退出只走左上角的 ✕ / 右上角的 ✓
        .fullScreenCover(isPresented: $showEdit) {
            EditEntryView(entry: entry)
                // 全屏页不继承外层的明暗，皮革主题要自己声明（否则状态栏深色字压在深色页面上）
                .preferredColorScheme(themeManager.current.preferredColorScheme)
        }
        // 嵌入照片全屏查看（双指缩放 + 下拉关闭 + Live Photo 按住播放）
        .fullScreenCover(item: $fullScreenPhoto) { block in
            PhotoFullScreenView(
                photo: block,
                onDismiss: { fullScreenPhoto = nil },
                onTogglePosition: { togglePhotoPosition(blockId: block.id) },
                onChangeStyle: { openStyleChange(blockId: block.id) },
                onDelete: { deletePhoto(blockId: block.id) }
            )
        }
        .alert("删除日记", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                // 照片、Live 视频、录音都是沙盒里的独立文件，不随 SwiftData 一起删
                entry.deleteAssociatedMedia()
                modelContext.delete(entry)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("确定要删除这篇日记吗？此操作不可撤销。")
        }
        // 更换相纸样式 sheet（复用 PaperStylePickerView）
        .sheet(isPresented: $showStyleChangePicker, onDismiss: {
            editingImage = nil
            editingPhotoBlockId = nil
        }) {
            if let img = editingImage {
                PaperStylePickerView(
                    image: img,
                    theme: themeManager.current,
                    onSelect: { style in
                        applyStyleChange(style: style)
                        showStyleChangePicker = false
                    },
                    onCancel: {
                        showStyleChangePicker = false
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - 已嵌入照片的编辑

    private func togglePhotoPosition(blockId: UUID) {
        var blocks = entry.contentBlocks
        guard let idx = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        let current = blocks[idx].position ?? .left
        blocks[idx].position = (current == .left) ? .right : .left
        entry.contentBlocks = blocks
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        editingPhotoBlockId = nil
    }

    private func openStyleChange(blockId: UUID) {
        guard
            let block = entry.contentBlocks.first(where: { $0.id == blockId }),
            let img = PhotoPaperIO.loadImage(block.photoFilename)
        else {
            editingPhotoBlockId = nil
            return
        }
        editingPhotoBlockId = blockId
        editingImage = img
        showStyleChangePicker = true
    }

    private func applyStyleChange(style: PaperStyle) {
        guard let id = editingPhotoBlockId else { return }
        var blocks = entry.contentBlocks
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].paperStyle = style
        entry.contentBlocks = blocks
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func deletePhoto(blockId: UUID) {
        var blocks = entry.contentBlocks
        guard let idx = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        PhotoPaperIO.deleteImage(blocks[idx].photoFilename)
        PhotoPaperIO.deleteImage(blocks[idx].livePhotoVideoFilename)
        PhotoPaperIO.deleteImage(blocks[idx].livePhotoStillFilename)
        blocks.remove(at: idx)
        entry.contentBlocks = blocks
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        editingPhotoBlockId = nil
    }

    // MARK: - 默认布局（皮革 & 北欧主题）

    @ViewBuilder
    private func defaultLayout(theme: any AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Date + mood
            HStack {
                Text(entry.date.dayAndWeekday)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .tracking(theme.letterSpacingWide)
                Spacer()
                if !entry.mood.isEmpty {
                    MoodBadge(name: entry.mood, colorHex: entry.moodColorHex)
                }
            }

            // 此时此地（写作当时的天气与地点）
            WeatherLocationBadge(
                weatherCode: entry.weatherCode,
                weatherInfo: entry.weatherInfo,
                locationInfo: entry.locationInfo,
                font: theme.labelFont,
                color: theme.textTertiary
            )

            addendumNote(font: theme.labelFont, color: theme.textTertiary)

            // Title
            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
            }

            // Tags
            if !entry.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(entry.tags, id: \.self) { tag in
                        TagPill(name: tag)
                    }
                }
            }

            // Divider
            Rectangle()
                .fill(theme.border)
                .frame(height: 0.5)

            // 正文：和写日记页同一套排版（照片浮在文字左右、文字绕着排）。
            // 加照片在编辑页做（右上角铅笔）；点照片看大图，大图页右上角「⋯」能换边、换相纸、删除
            bodyText(theme: theme)

            // Audio
            audioSection()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - 和纸布局

    /// 印章是否应该显示
    private var shouldShowStamp: Bool {
        guard !entry.mood.isEmpty else { return false }
        guard DefaultMoods.isDefaultKey(entry.mood) else { return false }
        let displayName = MoodTag.localizedName(for: entry.mood)
        guard displayName.count <= 2 else { return false }
        let lang: String
        if appLanguage.isEmpty {
            lang = Locale.autoupdatingCurrent.language.languageCode?.identifier ?? ""
        } else {
            lang = appLanguage
        }
        return lang == "zh" || appLanguage.hasPrefix("zh")
    }

    @ViewBuilder
    private func washiLayout(theme: any AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 月份
            Text(entry.date.monthYearUppercased)
                .font(.system(size: 11, weight: .regular))
                .tracking(3)
                .foregroundStyle(Color(hex: "#B8AD9C"))
                .padding(.bottom, 4)

            // 日期大字 + 印章
            HStack(alignment: .bottom) {
                // 前小后大的日期数字
                HStack(alignment: .top, spacing: 0) {
                    Text(entry.date.dayTens)
                        .font(.system(size: 28, weight: .light, design: .serif))
                        .foregroundStyle(Color(hex: "#3D3428"))
                    Text(entry.date.dayOnes)
                        .font(.system(size: 64, weight: .light, design: .serif))
                        .foregroundStyle(Color(hex: "#3D3428"))
                }

                Spacer()

                // 印章（条件显示）
                if shouldShowStamp {
                    StampView(moodName: MoodTag.localizedName(for: entry.mood))
                        .padding(.bottom, 4)
                }
            }
            .padding(.bottom, 2)

            // 星期 + 此时此地（和纸布局用自己的色板，不走 theme token）
            HStack(spacing: 8) {
                Text(entry.date.weekdayString)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#8B7E6A"))

                if WeatherLocationBadge.hasContent(entry.weatherCode, entry.weatherInfo, entry.locationInfo) {
                    Text("|")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "#D4C9B8"))
                    WeatherLocationBadge(
                        weatherCode: entry.weatherCode,
                        weatherInfo: entry.weatherInfo,
                        locationInfo: entry.locationInfo,
                        font: .system(size: 12),
                        color: Color(hex: "#8B7E6A"),
                        iconSize: 10
                    )
                }
            }
            .padding(.bottom, 16)

            // 补记过的话，日期下面一行小字
            addendumNote(font: .system(size: 12), color: Color(hex: "#8B7E6A"))
                .padding(.top, -10)
                .padding(.bottom, 14)

            // 短分割线
            Rectangle()
                .fill(Color(hex: "#D4C9B8"))
                .frame(width: 32, height: 1)
                .padding(.bottom, 20)

            // 标题（Georgia 20px）
            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(.custom("Georgia", size: 22))
                    .fontWeight(.medium)
                    .foregroundStyle(Color(hex: "#3D3428"))
                    .lineSpacing(4)
                    .padding(.bottom, 10)
            }

            // 标签药丸
            if !entry.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(entry.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#8B7E6A"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color(hex: "#F0EBE1"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: "#E0D9CC"), lineWidth: 0.5)
                            )
                            .cornerRadius(12)
                    }
                }
                .padding(.bottom, 16)
            }

            // 心情标签（印章不显示时才用药丸）
            if !entry.mood.isEmpty && !shouldShowStamp {
                MoodBadge(name: entry.mood, colorHex: entry.moodColorHex)
                    .padding(.bottom, 16)
            }

            // 全宽分割线（正文区起点）
            Rectangle()
                .fill(Color(hex: "#D4C9B8").opacity(0.5))
                .frame(height: 0.5)

            // 正文 + 和纸横线（紧接全宽分割线）
            washiContent(theme: theme)

            // 录音
            audioSection()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - 正文

    @ViewBuilder
    private func washiContent(theme: any AppTheme) -> some View {
        bodyText(theme: theme)
            .padding(.top, 6)
    }

    /// 正文（只读）。字号、行距按主题来，和写日记页一模一样（见 `RichTextAppearance`）
    private func bodyText(theme: any AppTheme) -> some View {
        RichEntryEditor(
            blocks: .constant(entry.contentBlocks),
            isEditable: false,
            appearance: RichTextAppearance.forTheme(id: themeManager.currentThemeID, theme: theme),
            writtenDate: entry.createdAt,
            onPhotoTap: { fullScreenPhoto = $0 }
        )
    }

    /// 「补记 2 次 · 最近 10月12日」：这篇日记之后又添过字（见 `Ink`）。没补记过就不显示
    @ViewBuilder
    private func addendumNote(font: Font, color: Color) -> some View {
        let days = entry.addendumDays
        if let last = days.last {
            Text(verbatim: String(format: NSLocalizedString("补记 %1$lld 次 · 最近 %2$@", bundle: .appLanguage,
                                                            comment: "详情页：这篇日记之后补写过几次、最近一次的日期"),
                                  days.count, InkText.day(last)))
                .font(font)
                .foregroundStyle(color)
        }
    }

    // MARK: - 共享组件

    @ViewBuilder
    private func audioSection() -> some View {
        // 正文里有位置的录音在正文里播；这里只列没有位置的（2026-10-10 之前的老日记）
        if !entry.looseAudioURLs.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(entry.looseAudioURLs.enumerated()), id: \.offset) { _, url in
                    AudioPlayerCard(audioURL: url)
                }
            }
        }
    }

}
