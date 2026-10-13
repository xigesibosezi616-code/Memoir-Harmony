import SwiftUI
import UIKit   // 打开系统设置（定位被拒时引导用户）
import SwiftData

struct ComposeView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var initialTags: [String] = []

    // MARK: 草稿
    /// 按返回键时的「保存草稿 / 不保存」弹窗
    @State private var showExitDialog = false
    /// 本次是从草稿恢复进来的（顶部给一条提示，让用户知道这不是空白页）
    @State private var didRestoreDraft = false
    /// 进页面时草稿已经引用的媒体文件名。
    ///
    /// 点「不保存」时用它区分哪些照片是**本次新加的**（该删）、哪些是**原草稿的**（该留）——
    /// 「不保存」是不写入本次修改，不是把原来那份草稿也一起毁掉。
    @State private var restoredMediaNames: Set<String> = []
    /// 草稿里原有的照片文件。这次在正文里删掉的，存的时候要清掉
    @State private var restoredPhotoNames: Set<String> = []

    @State private var title = ""
    /// 正文：文本块 + 照片块（存盘格式）。编辑在 `RichEntryEditor` 里是一整篇连续的图文
    @State private var blocks: [ContentBlock] = [ContentBlock(text: "")]
    /// 工具栏遥控编辑器（加粗 / 斜体 / 小标题 / 插照片）
    @State private var editor = RichTextController()

    @State private var moodName = ""
    @State private var moodColorHex: String?
    @State private var selectedTags: [String]
    /// 这次录的音（相对路径）。录音放在正文里（`.audio` 块），存盘时由正文生成 `audioURLs`；
    /// 这里记着是为了：录了又删掉、或者最后没保存的，把文件清掉
    @State private var recordedAudio: Set<String> = []
    /// 草稿里原有的录音。这次在正文里删掉的，存的时候清掉
    @State private var restoredAudio: Set<String> = []
    @State private var showVoiceRecording = false
    @State private var weatherManager = WeatherManager()
    /// 这篇日记记哪个地点：自动 / 不记 / 手动挑的
    @State private var placeChoice: PlaceChoice = .auto
    @State private var showLocationPicker = false

    /// 最终写进日记的地名
    private var effectivePlaceName: String? {
        switch placeChoice {
        case .auto:              return weatherManager.currentPlaceName
        case .none:              return nil
        case .manual(let name):  return name
        }
    }
    @AppStorage("stampMode") private var stampMode: String = StampMode.weather.rawValue

    // MARK: 照片
    /// 正在走的加照片流程（相机 / 相册），见 `PhotoInsertFlow`
    @State private var insertSource: PhotoInsertSource?
    /// 正在换相纸的照片
    @State private var restylingPhoto: ContentBlock?
    /// 这次进来新落盘的照片文件。正文里删掉的、或者最后没要的，存的时候清掉，不留孤儿文件
    @State private var insertedMediaNames: Set<String> = []

    init(initialTags: [String] = []) {
        self.initialTags = initialTags
        _selectedTags = State(initialValue: initialTags)
    }

    /// 是否还能插入照片（上限 5 张）
    private var photoCount: Int {
        blocks.filter { $0.type == .photo }.count
    }
    private var canInsertPaperPhoto: Bool { photoCount < 5 }

    /// 正文是否为空（只有一个空文本块）
    private var isContentEmpty: Bool {
        blocks.count == 1 && blocks[0].type == .text && (blocks[0].text ?? "").isEmpty
    }
    private var hasContent: Bool {
        blocks.contains { block in
            if block.type != .text { return true }
            return !(block.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    private var totalCharCount: Int {
        blocks.compactMap { $0.type == .text ? $0.text?.count : nil }.reduce(0, +)
    }

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Date + 字数（字数从底部工具栏移上来，让工具栏只留图标）
                        HStack(alignment: .firstTextBaseline) {
                            Text(Date.now.dayAndWeekday)
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                                .tracking(theme.letterSpacingWide)
                            Spacer()
                            Text("\(totalCharCount) 字")
                                .font(theme.labelFont)
                                .foregroundStyle(theme.textTertiary)
                                .opacity(totalCharCount > 0 ? 1 : 0)
                                .animation(.easeOut(duration: 0.2), value: totalCharCount > 0)
                        }

                        // 从草稿恢复时说一声，否则用户会以为自己上次的东西还在别处
                        if didRestoreDraft {
                            HStack(spacing: 5) {
                                Image(systemName: "pencil.line")
                                    .font(.system(size: 10))
                                Text("接着上次没写完的")
                                    .font(theme.labelFont)
                            }
                            .foregroundStyle(theme.textTertiary)
                        }

                        // 此时此地：天气 + 地点，可一键取消记录
                        weatherLocationRow(theme: theme)

                        // Title
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

                        // 正文（图文连续编辑）
                        bodyEditor(theme: theme)

                        // Mood
                        VStack(alignment: .leading, spacing: 8) {
                            Text("心情")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                            MoodSelector(selectedMoodName: $moodName, selectedMoodColorHex: $moodColorHex)
                        }

                        // 收进日记本（不选 = 只在「全部日记」里）
                        VStack(alignment: .leading, spacing: 8) {
                            Text("收进日记本")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                            TagSelector(selectedTags: $selectedTags)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }

                // Bottom toolbar：只留图标，均匀排布，紧贴键盘上沿
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(theme.textTertiary.opacity(0.18))
                        .frame(height: 0.5)

                    HStack(spacing: 0) {
                        RichFormatButtons(controller: editor, theme: theme)
                        Rectangle()
                            .fill(theme.textTertiary.opacity(0.25))
                            .frame(width: 0.5, height: 20)
                            .padding(.horizontal, 10)
                        toolbarIcon("camera", enabled: canInsertPaperPhoto, theme: theme) {
                            insertSource = .camera
                        }
                        .accessibilityLabel(Text("拍照"))
                        toolbarIcon("photo", enabled: canInsertPaperPhoto, theme: theme) {
                            insertSource = .library
                        }
                        .accessibilityLabel(Text("从相册选照片"))
                        toolbarIcon("mic", enabled: blocks.audioPaths.count < 3, theme: theme) {
                            showVoiceRecording = true
                        }
                        .accessibilityLabel(Text("录音"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .background(theme.background)
            }
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 返回箭头而非叉叉：这里退出**不等于丢弃**，可以存成草稿下次接着写
                    CircleIconButton(systemName: "chevron.left", prominence: .glass, theme: theme, size: 14) {
                        attemptExit()
                    }
                }
                // 完成上移到导航栏，底部工具栏得以只放图标
                ToolbarItem(placement: .confirmationAction) {
                    // 与返回键同一种分量（半透明玻璃）。**不用实心** —— 实心是页面主行动的分量，
                    // 这一页的主行动是「写」，不是「完成」。能不能点由 disabled 表达
                    CircleIconButton(systemName: "checkmark", prominence: .glass, theme: theme, size: 14) {
                        save()
                        dismiss()
                    }
                    .disabled(!hasContent)
                    .animation(.easeOut(duration: 0.2), value: hasContent)
                }
            }
            .task {
                restoreDraftIfNeeded()
                // 草稿里存了「此时此地」就用草稿那一份 —— 它可能是昨天在别的城市写的，
                // 重新定位会把地点改成今天这里，可这篇日记记的是昨天那件事。
                // 草稿里没有（上次也没取到）才重新取。
                if stampMode == StampMode.weather.rawValue && !weatherManager.hasContent {
                    weatherManager.requestLocationAndWeather()
                }
            }
            .sheet(isPresented: $showVoiceRecording) {
                VoiceRecordingSheet { audioPath in
                    // 录音放在光标的下一行（产品定），不再列在正文外面
                    recordedAudio.insert(audioPath)
                    editor.insertAudio(path: audioPath)
                }
            }
            // 相机 / 相册 → 选相纸 → 插到光标处；也负责给已插的照片换相纸
            .photoInsertFlow(
                source: $insertSource,
                restyling: $restylingPhoto,
                theme: theme,
                onInsert: { editor.insertPhoto($0) },
                onRestyle: { editor.updatePhoto($0) },
                onFilesCreated: { insertedMediaNames.formUnion($0) }
            )
            // 选择地点（微信式：不显示 / 当前位置 / 附近地点，可搜）
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView(
                    coordinate: weatherManager.currentCoordinate,
                    autoName: weatherManager.currentPlaceName,
                    current: placeChoice
                ) { choice in
                    withAnimation(.easeOut(duration: 0.2)) { placeChoice = choice }
                }
            }
        }
        // 返回确认。挂在 NavigationStack 外层，让遮罩连导航栏一起盖住
        .overlay {
            if showExitDialog {
                DraftExitDialog(
                    theme: theme,
                    onDiscard: {
                        showExitDialog = false
                        discardChanges()
                        dismiss()
                    },
                    onSave: {
                        showExitDialog = false
                        saveDraft()
                        dismiss()
                        // 先 dismiss 再提示：toast 挂在 ContentView 上，
                        // 这个全屏页还盖着的时候弹出来是看不见的。
                        // 走 NSLocalizedString 而非字面量：present 收的是 String，
                        // ErrorToastView 里是 `Text(toast.message)` —— Text(String) 不会本地化。
                        env.errors.present(
                            NSLocalizedString("草稿已保存", bundle: .appLanguage, comment: "草稿保存成功提示"),
                            kind: .success,
                            duration: 2
                        )
                    },
                    onCancel: { showExitDialog = false }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showExitDialog)
    }

    /// 「此时此地」行：拿到天气/地点后显示，点击打开地点选择器（可换成附近的店名、或不记）。
    /// 没授权或没拿到时显示一个轻量入口，不打扰写作。
    @ViewBuilder
    private func weatherLocationRow(theme: any AppTheme) -> some View {
        if weatherManager.hasContent {
            let hasPlace = effectivePlaceName != nil
            // spacing 8：失败提示原来贴着地点胶囊底边（spacing 2），像是从胶囊里漏出来的一行
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showLocationPicker = true
                } label: {
                    HStack(spacing: 6) {
                        WeatherLocationBadge(
                            weatherCode: weatherManager.currentWeatherCode,
                            weatherInfo: weatherManager.currentTemperature,
                            locationInfo: effectivePlaceName,
                            font: theme.labelFont,
                            color: theme.textSecondary
                        )
                        // 有地点时给个「可改」的暗示；不记位置时显示斜杠图标
                        Image(systemName: hasPlace ? "chevron.down" : "location.slash")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.cardBackground, in: Capsule())
                }

                // 天气单独失败时给个重试入口。
                // 以前这里什么都不显示 —— 用户只看到地点旁边空着一块，
                // 分不清是「还没取到」「这地方没天气」还是「坏了」，只能当成功能没做。
                if weatherManager.weatherFailed {
                    Button {
                        weatherManager.requestLocationAndWeather()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("天气没取到，点这里重试")
                                    .font(theme.labelFont)
                            }
                            // 🔴 **把错误码摆在用户眼前**：域 + 码，截图就能报给我们。
                            // 以前只进系统日志，排查必须让用户接电脑抓 log ——
                            // 天气这个问题拖了两个多月，卡的就是这一步。
                            // 用 verbatim：这是技术标识，不该被翻译；
                            // 单独一行 + 中间省略，避免这串长域名把整行排版挤乱
                            if let code = weatherManager.lastWeatherError {
                                Text(verbatim: code)
                                    .font(theme.labelFont)
                                    .opacity(0.6)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.leading, 2)
                }
            }
        } else if weatherManager.isResolving {
            Text("正在获取此时此地…")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
        } else if weatherManager.locationDenied {
            // 定位被拒：iOS 不会再弹第二次权限，只能去系统设置。
            // 以前这里和「还没取过」长一个样，点了毫无反应
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 10))
                    Text("定位已关闭，去设置里开启")
                        .font(theme.labelFont)
                }
                .foregroundStyle(theme.textTertiary)
            }
        } else {
            Button {
                weatherManager.requestLocationAndWeather()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: LocationPrecision.isRecordingEnabled ? "location" : "thermometer.medium")
                        .font(.system(size: 10))
                    Text(LocationPrecision.isRecordingEnabled ? "记录天气与位置" : "记录天气")
                        .font(theme.labelFont)
                }
                .foregroundStyle(theme.textTertiary)
            }
        }
    }

    /// 底部工具栏图标：统一尺寸与触控区，禁用态只降透明度不换色系
    private func toolbarIcon(
        _ systemName: String,
        enabled: Bool,
        theme: any AppTheme,
        action: @escaping () -> Void
    ) -> some View {
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

    /// 一整篇连续的图文：照片浮在文字左右、文字绕着排；加粗 / 斜体 / 小标题在底部工具栏
    @ViewBuilder
    private func bodyEditor(theme: any AppTheme) -> some View {
        let appearance = RichTextAppearance.forTheme(id: themeManager.currentThemeID, theme: theme)
        ZStack(alignment: .topLeading) {
            // 占位符（整篇为空时）。和正文同一个字号，正好落在光标的位置
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
                onRequestPaperStyle: { restylingPhoto = $0 }
            )
        }
    }

    /// 存盘（日记或草稿）时清掉没被用上的照片、录音文件：这次新加后来删掉的，和草稿里原有、这次删掉的。
    /// 正文里删照片、录音只是删锚点，文件留到这里统一处理 —— 删了又撤销（摇一摇）时文件还在
    private func removeUnusedMedia(keeping kept: [ContentBlock]) {
        let referenced = Set(kept.flatMap { [$0.photoFilename, $0.livePhotoVideoFilename, $0.livePhotoStillFilename] }
            .compactMap { $0 })
        for name in insertedMediaNames.union(restoredPhotoNames) where !referenced.contains(name) {
            PhotoPaperIO.deleteImage(name)
        }
        insertedMediaNames.removeAll()

        let keptAudio = Set(kept.audioPaths)
        for relative in recordedAudio.union(restoredAudio) where !keptAudio.contains(relative) {
            try? FileManager.default.removeItem(at: URL.documentsDirectory.appending(path: relative))
        }
        recordedAudio.removeAll()
    }

    // MARK: - 保存

    /// 去掉纯空白文本块（保留照片块）；若全空则保底一个空文本块
    private func cleanedBlocks() -> [ContentBlock] {
        let cleaned = blocks.filter { block in
            // 照片、录音都留着，只去掉空白的文字段
            if block.type != .text { return true }
            return !(block.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return cleaned.isEmpty ? [ContentBlock(text: "")] : cleaned
    }

    /// 点对勾 = **完成了一篇书写**，这一刻才产生正式日记。
    private func save() {
        let entry = JournalEntry(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: "",
            mood: moodName,
            moodColorHex: moodColorHex,
            tags: selectedTags
        )
        let finalBlocks = cleanedBlocks()
        entry.contentBlocks = finalBlocks   // setter 同步 content / wordCount / contentBlocksData
        // 录音清单由正文里的录音生成（同步、备份、删日记时清文件都认这份清单）
        entry.audioURLs = finalBlocks.audioPaths
        // 天气照常记；地点按用户在选择器里的决定（自动 / 手选 / 不记）
        entry.weatherCode = weatherManager.currentWeatherCode
        entry.weatherInfo = weatherManager.currentTemperature
        entry.locationInfo = effectivePlaceName
        modelContext.insert(entry)

        // 草稿转正：**只删记录，绝不调 deleteAssociatedMedia** ——
        // 草稿引用的那些照片和录音正要被这篇日记接着用，删了就成了有字没图。
        if let draft = DraftEntry.current(in: modelContext) {
            modelContext.delete(draft)
        }
        try? modelContext.save()
        removeUnusedMedia(keeping: finalBlocks)
    }

    // MARK: - 草稿

    /// 按返回键。空白页直接走，不拿弹窗打扰。
    private func attemptExit() {
        guard hasContent else {
            dismiss()
            return
        }
        showExitDialog = true
    }

    /// 进页面时把上次没写完的接回来（全局只有一份草稿，见 `DraftEntry` 注释）。
    private func restoreDraftIfNeeded() {
        guard let draft = DraftEntry.current(in: modelContext) else { return }

        title = draft.title
        let restored = draft.contentBlocks
        blocks = restored.isEmpty ? [ContentBlock(text: "")] : restored
        moodName = draft.mood
        moodColorHex = draft.moodColorHex
        // 老草稿的录音在正文外面，接回来时补到正文末尾
        blocks = blocks.withLooseAudio(draft.audioURLs)
        restoredAudio = Set(draft.audioURLs)
        // 一篇日记只放一本：草稿里选过的优先（那是用户亲手选的），没选过才用入口带进来的那本。
        // 草稿里存着多本的（单本规则之前存的）视同没选
        let drafted = JournalEntry.singleNotebook(draft.tags)
        selectedTags = drafted.isEmpty ? JournalEntry.singleNotebook(initialTags) : drafted

        // 「此时此地」原样还原，不重新定位（理由见 `DraftEntry.weatherCode` 注释）
        weatherManager.currentWeatherCode = draft.weatherCode
        weatherManager.currentTemperature = draft.weatherInfo
        weatherManager.currentPlaceName = draft.locationInfo
        switch DraftEntry.PlaceMode(rawValue: draft.placeMode) ?? .auto {
        case .auto:   placeChoice = .auto
        case .none:   placeChoice = .none
        case .manual: placeChoice = draft.manualPlaceName.map { .manual($0) } ?? .auto
        }

        restoredMediaNames = Set(draft.referencedMediaNames)
        restoredPhotoNames = Set(restored.flatMap {
            [$0.photoFilename, $0.livePhotoVideoFilename, $0.livePhotoStillFilename]
        }.compactMap { $0 })
        didRestoreDraft = true
    }

    /// 存草稿。已有草稿就地更新，没有才新建 —— 保证全局只有一份。
    private func saveDraft() {
        let draft: DraftEntry
        if let existing = DraftEntry.current(in: modelContext) {
            draft = existing
        } else {
            let fresh = DraftEntry()
            modelContext.insert(fresh)
            draft = fresh
        }

        draft.title = title
        let finalBlocks = cleanedBlocks()
        draft.contentBlocks = finalBlocks   // setter 顺带刷新 updatedAt
        draft.mood = moodName
        draft.moodColorHex = moodColorHex
        draft.tags = selectedTags
        draft.audioURLs = finalBlocks.audioPaths
        draft.weatherCode = weatherManager.currentWeatherCode
        draft.weatherInfo = weatherManager.currentTemperature
        draft.locationInfo = effectivePlaceName
        switch placeChoice {
        case .auto:
            draft.placeMode = DraftEntry.PlaceMode.auto.rawValue
            draft.manualPlaceName = nil
        case .none:
            draft.placeMode = DraftEntry.PlaceMode.none.rawValue
            draft.manualPlaceName = nil
        case .manual(let name):
            draft.placeMode = DraftEntry.PlaceMode.manual.rawValue
            draft.manualPlaceName = name
        }
        try? modelContext.save()
        removeUnusedMedia(keeping: finalBlocks)
    }

    /// 点「不保存」：**这篇就此作废** —— 连同已存在的草稿一起丢弃。
    ///
    /// 弹窗上写的就是「保存这篇草稿？」+「不保存」，用户按下它表达的是
    /// **"这篇我不要了"**，不是"这次的改动不算"。留着旧草稿的话，
    /// 下次进来内容还在，用户会以为不保存没生效。
    ///
    /// 误触的出口是**点遮罩取消**（回到编辑），不是让「不保存」变得半吊子。
    private func discardChanges() {
        // 本次会话新落盘、还没进任何草稿的照片 —— 包括正文里加了又删掉的（草稿自己那份由 discardCurrent 删）
        for name in insertedMediaNames where !restoredMediaNames.contains(name) {
            PhotoPaperIO.deleteImage(name)
        }
        for relative in recordedAudio where !restoredMediaNames.contains(relative) {
            try? FileManager.default.removeItem(at: URL.documentsDirectory.appending(path: relative))
        }
        // 已存在的草稿连记录带媒体一并清掉
        DraftEntry.discardCurrent(in: modelContext)
    }
}
