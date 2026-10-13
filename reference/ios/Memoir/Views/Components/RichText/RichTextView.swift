import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// 图文正文：一整篇连续的文字，照片浮在文字的左边或右边，文字**真正绕开照片**排。
///
/// - 写日记页、编辑页用它编辑；详情页用它只读显示 —— 同一套排版，写的时候看到的就是最后的样子
/// - 照片在文字里是一个看不见的锚点（`PhotoAnchorAttachment`），照片从锚点那一行开始，
///   按 `ContentBlock.position` 靠左或靠右，保留相纸和倾斜；文字用 TextKit 的排除区域绕开
/// - 自己不滚动，高度随内容长，放在外层的滚动视图里（光标跑到键盘后面时由 `scrollCaretIntoView` 把它带出来）
///
/// 用 TextKit 1：要逐行量锚点的位置、设排除区域，TextKit 1 的 `NSLayoutManager` 最直接
final class RichTextView: UITextView {

    // MARK: 内容

    /// 照片块本体，按 id 找。**锚点删掉时这里不删** —— 摇一摇撤销会把锚点放回来，照片得还找得到；
    /// 拆回内容块时只认还在正文里的锚点，多留的不会进存盘
    private(set) var photos: [UUID: ContentBlock] = [:]
    /// 录音块本体，按 id 找（同照片，锚点删了这里也不删）
    private(set) var audios: [UUID: ContentBlock] = [:]
    /// 痕迹块（墨迹干了以后取下的照片 / 删去的录音，见 `Ink`）
    private(set) var traces: [UUID: ContentBlock] = [:]
    /// 这次编辑开始的时刻。改已有的日记时才有：这次写下的字都记成这个时刻写的（补记、墨迹干没干都看它）。
    /// 写新日记、只读显示时为 nil
    var sessionDate: Date?
    var style = RichTextStyle()
    /// 录音卡片（`AudioPlayerCard`）要读主题，浮在 UIKit 里的 SwiftUI 视图拿不到外面的环境，得递进来
    var themeManager: ThemeManager?

    /// 照片占正文宽度的比例
    static let photoWidthRatio: CGFloat = 0.46
    /// 照片和文字之间留的空
    static let photoGap: CGFloat = 12

    // MARK: 回调

    /// 正文变了（打字、删字、改格式、挪照片）
    var onChange: (() -> Void)?
    /// 只读模式下点了照片
    var onPhotoTap: ((ContentBlock) -> Void)?
    /// 编辑模式下要给某张照片换相纸
    var onRequestPaperStyle: ((ContentBlock) -> Void)?
    /// 选区或输入格式变了（工具栏的加粗 / 斜体 / 小标题按钮跟着亮）
    var onTypingStyleChange: (() -> Void)?
    /// 需要的高度变了。SwiftUI 不会因为 UIKit 视图内容变高就重新问尺寸，得主动报上去（见 `RichEntryEditor`）
    var onHeightChange: ((CGFloat) -> Void)?
    private var reportedHeight: CGFloat = 0

    // MARK: 照片视图

    private var photoViews: [UUID: PhotoOverlayView] = [:]
    private var audioViews: [UUID: AudioOverlayView] = [:]
    private var traceViews: [UUID: TraceOverlayView] = [:]
    /// 输入法拼字时跳过了「补记」标签的刷新，拼完要补
    private var labelsPending = false
    private var photoFrames: [UUID: CGRect] = [:]
    private var isLayingOutPhotos = false
    private var lastLayoutWidth: CGFloat = 0
    private var lastLayoutHeight: CGFloat = 0
    /// 退格碰到照片 / 录音时先选中它，再按一次才删 —— 防止删字时手一滑把照片、录音也删了
    private var armedPhotoID: UUID? {
        didSet {
            photoViews.values.forEach { $0.isArmed = $0.blockID == armedPhotoID }
            audioViews.values.forEach { $0.isArmed = $0.blockID == armedPhotoID }
        }
    }

    // MARK: - 初始化

    init() {
        let storage = NSTextStorage()
        // 荧光笔要自己画（像记号笔那样只压住字的中下部），见 `HighlighterLayoutManager`
        let layout = HighlighterLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        super.init(frame: .zero, textContainer: container)

        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        delegate = self
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 装入 / 取出

    func load(blocks: [ContentBlock]) {
        photos = Dictionary(uniqueKeysWithValues: blocks.filter { $0.type == .photo }.map { ($0.id, $0) })
        audios = Dictionary(uniqueKeysWithValues: blocks.filter { $0.type == .audio }.map { ($0.id, $0) })
        traces = Dictionary(uniqueKeysWithValues: blocks.filter { $0.type == .trace }.map { ($0.id, $0) })
        attributedText = RichDocument.attributedString(from: blocks, style: style, width: textContainer.size.width)
        typingAttributes = freshAttributes
        refreshAddendumLabels()
        syncPhotoViews()
        layoutPhotos(force: true)
        reportHeight()
    }

    var blocks: [ContentBlock] {
        RichDocument.blocks(from: textStorage,
                            anchored: photos.merging(audios) { a, _ in a }.merging(traces) { a, _ in a })
    }

    // MARK: - 尺寸

    /// 排版区域不限高。
    ///
    /// UITextView 关掉滚动后会把文字容器的高度跟到自己当前的高度上 —— 新加的一行（比如在文末插照片）
    /// 超出旧高度就**排不进去**，位置算出来是 (0, 0)，照片和光标一起跳到最上面（2026-10-10 实测）。
    /// 我们的高度是自己量好报给外面的，容器要一直按不限高排
    private func unclampContainerHeight() {
        if textContainer.size.height < 1_000_000 {
            textContainer.size = CGSize(width: textContainer.size.width, height: .greatestFiniteMagnitude)
        }
    }

    /// 给定宽度下需要多高：文字和照片哪个更靠下取哪个
    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        unclampContainerHeight()
        if abs(textContainer.size.width - width) > 0.5 {
            textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
            updateAudioWidths()
            layoutPhotos(force: true)
        }
        layoutManager.ensureLayout(for: textContainer)
        var height = layoutManager.usedRect(for: textContainer).maxY
        // 最后一个换行之后那一行（空行）也要算上，不然光标在末尾空行时被裁掉
        let extra = layoutManager.extraLineFragmentRect
        if !extra.isEmpty { height = max(height, extra.maxY) }
        for frame in photoFrames.values { height = max(height, frame.maxY + 4) }
        return ceil(max(height, style.bodyFont.lineHeight + style.lineSpacing))
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : textContainer.size.width
        return CGSize(width: UIView.noIntrinsicMetric, height: fittingHeight(forWidth: width))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 外面按报上去的高度把框拉高之后，再把光标带出来一次 ——
        // 在 `contentDidChange` 里滚的那一下早了一拍：那时外层还没变长，滚不到新的那一行（粘贴一大段时实测）
        if abs(bounds.height - lastLayoutHeight) > 0.5 {
            lastLayoutHeight = bounds.height
            scrollCaretIntoView()
        }
        if abs(bounds.width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = bounds.width
            textContainer.size = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
            updateAudioWidths()
            layoutPhotos(force: true)
            invalidateIntrinsicContentSize()
            reportHeight()
        }
    }

    /// 按现在的宽度算一遍要多高，变了就报给外面
    private func reportHeight() {
        guard bounds.width > 1 else { return }
        let height = fittingHeight(forWidth: bounds.width)
        guard abs(height - reportedHeight) > 0.5 else { return }
        reportedHeight = height
        onHeightChange?(height)
    }

    // MARK: - 照片排版

    /// 照片的位置：从锚点那一行的顶上开始，靠左或靠右；和上一张照片重叠时往下挪。
    ///
    /// 排除区域一改，文字重排，锚点那一行的位置也可能变 —— 所以反复算几遍，直到不再变
    /// （锚点总在段首，上面的照片先定，一般两遍就稳了）
    private func layoutPhotos(force: Bool = false) {
        guard !isLayingOutPhotos else { return }
        let width = textContainer.size.width
        guard width > 1 else { return }
        isLayingOutPhotos = true
        defer { isLayingOutPhotos = false }
        unclampContainerHeight()

        var frames = force ? [:] : photoFrames
        for _ in 0..<4 {
            textContainer.exclusionPaths = exclusionPaths(for: frames, width: width)
            layoutManager.ensureLayout(for: textContainer)
            let next = computeFrames(width: width)
            if next == frames { break }
            frames = next
        }
        textContainer.exclusionPaths = exclusionPaths(for: frames, width: width)
        photoFrames = frames
        for (id, view) in photoViews {
            guard let frame = frames[id] else { view.isHidden = true; continue }
            view.isHidden = false
            view.frame = frame.offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
        }
        layoutManager.ensureLayout(for: textContainer)
        layoutAudios()
    }

    // MARK: - 录音排版

    /// 录音卡片盖在它的锚点上。锚点自己占一整行（见 `AudioAnchorAttachment`），文字天然在它上下排
    private func layoutAudios() {
        let string = textStorage.string as NSString
        var placed = Set<UUID>()
        for index in 0..<string.length where string.character(at: index) == RichDocument.anchorCharacter {
            let attachment = textStorage.attribute(.attachment, at: index, effectiveRange: nil)
            let view: UIView
            let id: UUID
            let bounds: CGRect
            if let anchor = attachment as? AudioAnchorAttachment, let audioView = audioViews[anchor.blockID] {
                view = audioView; id = anchor.blockID; bounds = anchor.bounds
            } else if let anchor = attachment as? TraceAnchorAttachment, let traceView = traceViews[anchor.blockID] {
                view = traceView; id = anchor.blockID; bounds = anchor.bounds
            } else {
                continue
            }
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            // 卡片底边落在这一行的基线上（附件的 bounds 从基线往上量）
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = line.minY + layoutManager.location(forGlyphAt: glyph).y
            let frame = CGRect(x: line.minX, y: baseline - bounds.maxY, width: bounds.width, height: bounds.height)
            view.frame = frame.offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
            view.isHidden = false
            placed.insert(id)
        }
        for (id, view) in audioViews where !placed.contains(id) { view.isHidden = true }
        for (id, view) in traceViews where !placed.contains(id) { view.isHidden = true }
    }

    /// 正文宽度变了：录音锚点跟着改宽，重新排
    private func updateAudioWidths() {
        let width = textContainer.size.width
        guard width > 1 else { return }
        var changed = false
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, _, _ in
            if let anchor = value as? AudioAnchorAttachment, abs(anchor.bounds.width - (width - 1)) > 0.5 {
                anchor.setWidth(width)
                changed = true
            } else if let anchor = value as? TraceAnchorAttachment, abs(anchor.bounds.width - (width - 1)) > 0.5 {
                anchor.setWidth(width)
                changed = true
            }
        }
        if changed {
            let all = NSRange(location: 0, length: textStorage.length)
            layoutManager.invalidateLayout(forCharacterRange: all, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: all)
        }
    }

    private func computeFrames(width: CGFloat) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        var previousBottom: CGFloat = -.greatestFiniteMagnitude
        let string = textStorage.string as NSString
        for index in 0..<string.length where string.character(at: index) == RichDocument.anchorCharacter {
            guard let anchor = textStorage.attribute(.attachment, at: index, effectiveRange: nil) as? PhotoAnchorAttachment,
                  let photo = photos[anchor.blockID],
                  let view = photoViews[anchor.blockID] else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let size = view.fittingSize(width: (width * Self.photoWidthRatio).rounded())
            let y = max(line.minY + 4, previousBottom + Self.photoGap)
            let x = photo.position == .left ? 0 : width - size.width
            let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            frames[anchor.blockID] = frame
            previousBottom = frame.maxY
        }
        return frames
    }

    /// 文字要让开的地方：照片本身 + 朝文字那一侧留一道空（倾斜的角会超出一点，空也替它兜着）
    private func exclusionPaths(for frames: [UUID: CGRect], width: CGFloat) -> [UIBezierPath] {
        frames.values.map { frame in
            let gap = Self.photoGap
            let rect: CGRect
            if frame.minX < 1 {
                rect = CGRect(x: 0, y: frame.minY - 4, width: frame.maxX + gap, height: frame.height + 8)
            } else {
                rect = CGRect(x: frame.minX - gap, y: frame.minY - 4, width: width - frame.minX + gap, height: frame.height + 8)
            }
            return UIBezierPath(rect: rect)
        }
    }

    /// 照片视图跟着锚点增删
    private func syncPhotoViews() {
        let present = Set(anchorIDs())
        for (id, view) in photoViews where !present.contains(id) {
            view.removeFromSuperview()
            photoViews[id] = nil
        }
        for id in present where photoViews[id] == nil {
            guard let photo = photos[id] else { continue }
            let view = PhotoOverlayView(photo: photo)
            view.onTap = { [weak self] in self?.photoTapped(id) }
            view.onDragChanged = { [weak self] recognizer in self?.photoDragChanged(id, recognizer) }
            addSubview(view)
            photoViews[id] = view
        }
        // 录音卡片
        var presentAudio = Set<UUID>()
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, _, _ in
            if let anchor = value as? AudioAnchorAttachment { presentAudio.insert(anchor.blockID) }
        }
        for (id, view) in audioViews where !presentAudio.contains(id) {
            view.removeFromSuperview()
            audioViews[id] = nil
        }
        for id in presentAudio where audioViews[id] == nil {
            guard let audio = audios[id], let path = audio.audioFilename else { continue }
            let view = AudioOverlayView(blockID: id, path: path, themeManager: themeManager,
                                        onDelete: isEditable ? { [weak self] in self?.removeAudio(id: id) } : nil)
            addSubview(view)
            audioViews[id] = view
        }
        // 痕迹行
        var presentTraces = Set<UUID>()
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, _, _ in
            if let anchor = value as? TraceAnchorAttachment { presentTraces.insert(anchor.blockID) }
        }
        for (id, view) in traceViews where !presentTraces.contains(id) {
            view.removeFromSuperview()
            traceViews[id] = nil
        }
        for id in presentTraces where traceViews[id] == nil {
            guard let trace = traces[id] else { continue }
            let view = TraceOverlayView(text: InkText.traceLine(trace), color: style.labelColor)
            addSubview(view)
            traceViews[id] = view
        }
        if let armed = armedPhotoID, !present.contains(armed), !presentAudio.contains(armed) { armedPhotoID = nil }
    }

    private func anchorIDs() -> [UUID] {
        var ids: [UUID] = []
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, _, _ in
            if let anchor = value as? PhotoAnchorAttachment { ids.append(anchor.blockID) }
        }
        return ids
    }

    private func anchorIndex(of id: UUID) -> Int? {
        var found: Int?
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, range, stop in
            if (value as? PhotoAnchorAttachment)?.blockID == id || (value as? AudioAnchorAttachment)?.blockID == id
                || (value as? TraceAnchorAttachment)?.blockID == id {
                found = range.location
                stop.pointee = true
            }
        }
        return found
    }

    // MARK: - 插入 / 改 / 删照片

    /// 在光标处插一张照片。照片总是挂在某一段的开头：
    /// - 光标在段尾：挂到下一段开头，光标不动 —— 不会凭空多出一个空行
    /// - 光标在段首：就挂在这一段开头，光标落到照片后面接着写
    /// - 光标在段中间（或全文末尾）：先断成两段，照片挂在后一段开头 —— 和以前「在光标处插入」一样
    func insertPhoto(_ photo: ContentBlock) {
        var photo = photo
        photo.addedAt = sessionDate?.timeIntervalSince1970
        photos[photo.id] = photo
        let caret = selectedRange.location
        let string = textStorage.string as NSString
        var attributes = freshAttributes
        attributes[.attachment] = PhotoAnchorAttachment(blockID: photo.id)
        let anchor = NSAttributedString(string: String(utf16CodeUnits: [RichDocument.anchorCharacter], count: 1),
                                        attributes: attributes)

        if caret < string.length, string.character(at: caret) == 0x0A {
            textStorage.insert(anchor, at: caret + 1)
            selectedRange = NSRange(location: caret, length: 0)
        } else if caret == 0 || string.character(at: caret - 1) == 0x0A {
            textStorage.insert(anchor, at: caret)
            selectedRange = NSRange(location: caret + 1, length: 0)
        } else {
            let insertion = NSMutableAttributedString(string: "\n", attributes: freshAttributes)
            insertion.append(anchor)
            textStorage.insert(insertion, at: caret)
            selectedRange = NSRange(location: caret + insertion.length, length: 0)
        }
        contentDidChange()
    }

    /// 在光标**下一行**插一段录音（产品定：不把光标所在的这段话拆开）。
    /// 录音自成一段，后面跟一个换行；插在全文末尾时，光标挪到录音下面那一行，接着写
    func insertAudio(_ audio: ContentBlock) {
        var audio = audio
        audio.addedAt = sessionDate?.timeIntervalSince1970
        audios[audio.id] = audio
        let string = textStorage.string as NSString
        let caret = min(selectedRange.location, string.length)
        let paragraph = string.paragraphRange(for: NSRange(location: caret, length: 0))
        let paragraphEnd = NSMaxRange(paragraph)
        var attributes = freshAttributes
        attributes[.attachment] = AudioAnchorAttachment(blockID: audio.id, width: textContainer.size.width)
        let anchor = NSAttributedString(string: String(utf16CodeUnits: [RichDocument.anchorCharacter], count: 1),
                                        attributes: attributes)
        let newline = NSAttributedString(string: "\n", attributes: freshAttributes)

        let insertion = NSMutableAttributedString()
        let atEnd = paragraphEnd >= string.length
        // 这段末尾有换行：录音插在换行后面（下一段的开头）；最后一段没有换行，先补一个
        if atEnd, string.length > 0, string.character(at: string.length - 1) != 0x0A {
            insertion.append(newline)
        }
        insertion.append(anchor)
        insertion.append(newline)
        textStorage.insert(insertion, at: atEnd ? string.length : paragraphEnd)
        selectedRange = NSRange(location: atEnd ? textStorage.length : caret, length: 0)
        contentDidChange()
    }

    /// 删一段录音：锚点连同它后面补的那个换行一起删。墨迹干了的录音不删，换成一行痕迹
    func removeAudio(id: UUID) {
        if let audio = audios[id], isDry(audio) { return retire(id: id, kind: .audio) }
        guard let index = anchorIndex(of: id) else { return }
        let string = textStorage.string as NSString
        let hasNewline = index + 1 < string.length && string.character(at: index + 1) == 0x0A
        textStorage.replaceCharacters(in: NSRange(location: index, length: hasNewline ? 2 : 1), with: "")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        contentDidChange()
    }

    func updatePhoto(_ photo: ContentBlock) {
        guard photos[photo.id] != nil else { return }
        photos[photo.id] = photo
        photoViews[photo.id]?.update(photo: photo)
        layoutPhotos(force: true)
        contentDidChange()
    }

    /// 删一张照片。墨迹干了的照片不删，换成一行痕迹（「取下了一张照片 · 某月某日」）
    func removePhoto(id: UUID) {
        if let photo = photos[id], isDry(photo) { return retire(id: id, kind: .photo) }
        guard let index = anchorIndex(of: id) else { return }
        textStorage.replaceCharacters(in: NSRange(location: index, length: 1), with: "")
        contentDidChange()
    }

    // MARK: - 墨迹（见 `Ink`）

    /// 新写的字该带的属性：照光标处的格式，记上这次编辑的时刻，不带「划掉」
    var freshAttributes: [NSAttributedString.Key: Any] {
        var flags = TextFlags(attributes: typingAttributes)
        flags.writtenAt = sessionDate?.timeIntervalSince1970
        flags.struckAt = nil
        return style.attributes(flags)
    }

    private func isDry(_ block: ContentBlock) -> Bool {
        Ink.isDry(writtenAt: block.addedAt, base: style.baseDate)
    }

    private func isDryText(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        Ink.isDry(writtenAt: (attributes[.memoirWrittenAt] as? NSNumber)?.doubleValue, base: style.baseDate)
    }

    /// 这段范围里有没有干了的字（照片、录音锚点另算）
    private func containsDryText(_ range: NSRange) -> Bool {
        guard style.baseDate != nil, range.length > 0 else { return false }
        var dry = false
        textStorage.enumerateAttributes(in: range) { attributes, _, stop in
            guard attributes[.attachment] == nil else { return }
            if isDryText(attributes) { dry = true; stop.pointee = true }
        }
        return dry
    }

    /// 删 / 改的范围里有干了的字：干的**划掉**（换行、照片、录音不动），没干的照常删；
    /// 要打的字接在划掉的字后面。删除（退格）后光标停在划掉的字前面，再退格就接着往前划
    private func replaceRespectingInk(_ range: NSRange, with text: String) {
        let now = NSNumber(value: Date().timeIntervalSince1970)
        let ns = textStorage.string as NSString
        var pieces: [(range: NSRange, keep: Bool)] = []
        textStorage.enumerateAttributes(in: range) { attributes, subrange, _ in
            pieces.append((subrange, attributes[.attachment] != nil || isDryText(attributes)))
        }
        let insertAttributes = freshAttributes
        textStorage.beginEditing()
        var kept = 0
        for piece in pieces.reversed() {
            guard piece.keep else {
                textStorage.deleteCharacters(in: piece.range)
                continue
            }
            kept += piece.range.length
            // 只划字：换行、锚点、已经划过的跳过
            var index = piece.range.location
            while index < NSMaxRange(piece.range) {
                let character = ns.character(at: index)
                let attributes = textStorage.attributes(at: index, effectiveRange: nil)
                if character != 0x0A, attributes[.attachment] == nil, attributes[.memoirStruckAt] == nil {
                    var flags = TextFlags(attributes: attributes)
                    flags.struckAt = now.doubleValue
                    textStorage.setAttributes(style.attributes(flags), range: NSRange(location: index, length: 1))
                }
                index += 1
            }
        }
        var caret = range.location
        if !text.isEmpty {
            let insertAt = range.location + kept
            textStorage.insert(NSAttributedString(string: text, attributes: insertAttributes), at: insertAt)
            caret = insertAt + (text as NSString).length
        }
        textStorage.endEditing()
        selectedRange = NSRange(location: caret, length: 0)
        manualEditFinished()
    }

    /// 取消划掉：只有划掉不到 24 小时的能取消（划掉这个动作本身也会干）
    private func unstrike(_ range: NSRange) {
        textStorage.beginEditing()
        textStorage.enumerateAttributes(in: range) { attributes, subrange, _ in
            guard let struck = (attributes[.memoirStruckAt] as? NSNumber)?.doubleValue,
                  !Ink.isDry(writtenAt: struck, base: nil) else { return }
            var flags = TextFlags(attributes: attributes)
            flags.struckAt = nil
            var updated = style.attributes(flags)
            if let attachment = attributes[.attachment] { updated[.attachment] = attachment }
            textStorage.setAttributes(updated, range: subrange)
        }
        textStorage.endEditing()
        manualEditFinished()
    }

    /// 选区里有没有还能取消的划线
    private func hasWetStrike(_ range: NSRange) -> Bool {
        var found = false
        textStorage.enumerateAttribute(.memoirStruckAt, in: range) { value, _, stop in
            if let struck = (value as? NSNumber)?.doubleValue, !Ink.isDry(writtenAt: struck, base: nil) {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// 干了的照片 / 录音：从正文里取下，原处留一行痕迹。文件在保存时清掉（页面那一层负责）
    private func retire(id: UUID, kind: ContentBlockType) {
        guard let index = anchorIndex(of: id) else { return }
        let trace = ContentBlock(traceOf: kind, removedAt: .now)
        traces[trace.id] = trace
        var attributes = freshAttributes
        attributes[.attachment] = TraceAnchorAttachment(blockID: trace.id, width: textContainer.size.width)
        let replacement = NSMutableAttributedString(
            string: String(utf16CodeUnits: [RichDocument.anchorCharacter], count: 1), attributes: attributes)
        // 照片锚点和后面的字同一段；痕迹要自成一行，后面补个换行
        let ns = textStorage.string as NSString
        if kind == .photo, index + 1 < ns.length, ns.character(at: index + 1) != 0x0A {
            replacement.append(NSAttributedString(string: "\n", attributes: freshAttributes))
        }
        textStorage.replaceCharacters(in: NSRange(location: index, length: 1), with: replacement)
        armedPhotoID = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        manualEditFinished()
    }

    /// 自己直接改了 textStorage 之后：系统的撤销栈对不上了（它没记这些改动），清掉免得摇一摇撤销出错
    private func manualEditFinished() {
        undoManager?.removeAllActions()
        contentDidChange()
    }

    /// 整段都是同一天补的，段前标「补记 · 某月某日」（连着几段同一天补的只标第一段）。
    /// 标签不在正文里，是 `HighlighterLayoutManager` 画在段前距里的，所以这里顺带把段前距撑开。
    /// 输入法还在拼字（有 marked text）时不动属性，免得把拼到一半的字打断
    private func refreshAddendumLabels() {
        // 输入法还在拼字：先记着，拼完（选区变化时）再补
        guard markedTextRange == nil else { labelsPending = true; return }
        labelsPending = false
        guard let base = style.baseDate, textStorage.length > 0 else { return }
        let ns = textStorage.string as NSString
        var location = 0
        var previousDay: Date?
        var edits: [(range: NSRange, label: String?, spacing: CGFloat)] = []
        while location < ns.length {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            var content = paragraph
            if content.length > 0, ns.character(at: NSMaxRange(content) - 1) == 0x0A { content.length -= 1 }
            var day: Date?
            var whole = content.length > 0
            var sawText = false
            if whole {
                textStorage.enumerateAttributes(in: content) { attributes, _, stop in
                    guard attributes[.attachment] == nil else { return }
                    sawText = true
                    guard let written = (attributes[.memoirWrittenAt] as? NSNumber)?.doubleValue,
                          Ink.isAddendum(writtenAt: written, base: base) else {
                        whole = false; stop.pointee = true; return
                    }
                    let thisDay = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: written))
                    if let day, day != thisDay { whole = false; stop.pointee = true; return }
                    day = thisDay
                }
            }
            whole = whole && sawText
            let label: String? = (whole && day != previousDay) ? day.map(InkText.addendumLabel) : nil
            if paragraph.length > 0 {
                let attributes = textStorage.attributes(at: paragraph.location, effectiveRange: nil)
                let heading = attributes[.memoirHeading] as? Bool == true
                let spacing = (heading ? 8 : 0) + (label != nil ? HighlighterLayoutManager.labelSpace : 0)
                let currentLabel = attributes[.memoirAddendumLabel] as? String
                let currentSpacing = (attributes[.paragraphStyle] as? NSParagraphStyle)?.paragraphSpacingBefore ?? 0
                if currentLabel != label || abs(currentSpacing - spacing) > 0.1 {
                    edits.append((paragraph, label, spacing))
                }
            }
            previousDay = whole ? day : nil
            location = NSMaxRange(paragraph)
        }
        guard !edits.isEmpty else { return }
        textStorage.beginEditing()
        for edit in edits {
            textStorage.removeAttribute(.memoirAddendumLabel, range: edit.range)
            textStorage.removeAttribute(.memoirAddendumLabelColor, range: edit.range)
            if let label = edit.label {
                let first = NSRange(location: edit.range.location, length: 1)
                textStorage.addAttribute(.memoirAddendumLabel, value: label, range: first)
                textStorage.addAttribute(.memoirAddendumLabelColor, value: style.labelColor, range: first)
            }
            textStorage.enumerateAttribute(.paragraphStyle, in: edit.range) { value, subrange, _ in
                let paragraphStyle = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                    ?? NSMutableParagraphStyle()
                paragraphStyle.paragraphSpacingBefore = edit.spacing
                textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: subrange)
            }
        }
        textStorage.endEditing()
    }

    /// 打字、删字、改格式之后统一走这里
    private func contentDidChange() {
        refreshAddendumLabels()
        syncPhotoViews()
        layoutPhotos()
        invalidateIntrinsicContentSize()
        reportHeight()
        onChange?()
        scrollCaretIntoView()
    }

    // MARK: - 点照片 / 拖照片

    private func photoTapped(_ id: UUID) {
        guard let photo = photos[id] else { return }
        if !isEditable {
            onPhotoTap?(photo)
            return
        }
        armedPhotoID = id
        let view = photoViews[id]
        let interaction = editMenuInteraction
        let point = view.map { CGPoint(x: $0.frame.midX, y: $0.frame.minY) } ?? .zero
        interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: id.uuidString as NSString, sourcePoint: point))
    }

    private lazy var editMenuInteraction: UIEditMenuInteraction = {
        let interaction = UIEditMenuInteraction(delegate: self)
        addInteraction(interaction)
        return interaction
    }()

    private var dragStartFrame: CGRect = .zero

    /// 长按照片拖动：松手的位置决定它浮在哪一段、靠哪一边
    private func photoDragChanged(_ id: UUID, _ recognizer: UILongPressGestureRecognizer) {
        guard isEditable, let view = photoViews[id] else { return }
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            armedPhotoID = nil
            dragStartFrame = view.frame
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            bringSubviewToFront(view)
            UIView.animate(withDuration: 0.2) {
                view.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
                view.alpha = 0.9
            }
        case .changed:
            view.center = point
        case .ended:
            UIView.animate(withDuration: 0.2) {
                view.transform = .identity
                view.alpha = 1
            }
            movePhoto(id, droppedAt: point)
        default:
            UIView.animate(withDuration: 0.25) {
                view.transform = .identity
                view.alpha = 1
                view.frame = self.dragStartFrame
            }
        }
    }

    /// 把照片的锚点挪到松手处那一段的开头，按松手在左半边还是右半边定靠哪边
    private func movePhoto(_ id: UUID, droppedAt point: CGPoint) {
        guard var photo = photos[id], let from = anchorIndex(of: id) else { return }
        photo.position = point.x < bounds.midX ? .left : .right
        photos[id] = photo
        photoViews[id]?.update(photo: photo)

        // 松手那一行所在段的开头
        let containerPoint = CGPoint(x: 8, y: point.y - textContainerInset.top)
        var target = layoutManager.characterIndex(for: containerPoint, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        let string = textStorage.string as NSString
        target = string.paragraphRange(for: NSRange(location: min(target, max(0, string.length - 1)), length: 0)).location

        if target != from && target != from + 1 {
            let anchor = textStorage.attributedSubstring(from: NSRange(location: from, length: 1))
            textStorage.beginEditing()
            textStorage.replaceCharacters(in: NSRange(location: from, length: 1), with: "")
            let adjusted = target > from ? target - 1 : target
            textStorage.insert(anchor, at: adjusted)
            textStorage.endEditing()
        }
        layoutPhotos(force: true)
        contentDidChange()
    }

    // MARK: - 格式

    var selectionIsBold: Bool { currentFlag(.memoirBold) }
    var selectionIsItalic: Bool { currentFlag(.memoirItalic) }
    var selectionIsHeading: Bool { currentFlag(.memoirHeading) }
    var selectionIsHighlighted: Bool { currentFlag(.memoirHighlight) }

    private func currentFlag(_ key: NSAttributedString.Key) -> Bool {
        if selectedRange.length == 0 { return typingAttributes[key] as? Bool == true }
        var all = true
        textStorage.enumerateAttribute(key, in: selectedRange) { value, _, stop in
            if value as? Bool != true { all = false; stop.pointee = true }
        }
        return all
    }

    func toggleBold() { toggle(.memoirBold) }
    func toggleItalic() { toggle(.memoirItalic) }
    /// 荧光笔：选中一段字划一下；没选中时，接下来打的字带着荧光笔
    func toggleHighlight() { toggle(.memoirHighlight) }

    /// 加粗 / 斜体 / 荧光笔：有选区就改选区，没有就改接下来要打的字
    private func toggle(_ key: NSAttributedString.Key) {
        let turnOn = !currentFlag(key)
        func apply(_ flags: inout TextFlags) {
            switch key {
            case .memoirBold: flags.bold = turnOn
            case .memoirItalic: flags.italic = turnOn
            case .memoirHighlight: flags.highlight = turnOn
            default: break
            }
        }
        if selectedRange.length == 0 {
            var flags = TextFlags(attributes: typingAttributes)
            apply(&flags)
            typingAttributes = style.attributes(flags)
            onTypingStyleChange?()
            return
        }
        restyle(selectedRange, change: apply)
    }

    /// 小标题是整段的：光标所在段（或选区涉及的所有段）一起变
    func toggleHeading() {
        let turnOn = !selectionIsHeading
        let string = textStorage.string as NSString
        let paragraphs = string.paragraphRange(for: selectedRange)
        if paragraphs.length == 0 {
            typingAttributes = style.attributes(TextFlags(heading: turnOn))
            onTypingStyleChange?()
            return
        }
        restyle(paragraphs) { flags in flags.heading = turnOn }
        var typing = TextFlags(attributes: typingAttributes)
        typing.heading = turnOn
        typingAttributes = style.attributes(typing)
    }

    /// 按语义改一段文字的格式，字体等属性重新推出来；照片锚点的附件属性保留
    private func restyle(_ range: NSRange, change: (inout TextFlags) -> Void) {
        let selection = selectedRange
        textStorage.beginEditing()
        textStorage.enumerateAttributes(in: range) { attributes, subrange, _ in
            var flags = TextFlags(attributes: attributes)
            change(&flags)
            let attachment = attributes[.attachment]
            var updated = style.attributes(flags)
            if let attachment { updated[.attachment] = attachment }
            textStorage.setAttributes(updated, range: subrange)
        }
        textStorage.endEditing()
        selectedRange = selection
        contentDidChange()
        onTypingStyleChange?()
    }

    // MARK: - 粘贴只要文字

    /// 粘贴只取纯文字：别处带来的字体、颜色、附件不进日记（附件还可能是别的照片的锚点）
    override func paste(_ sender: Any?) {
        guard let text = Self.pastedText(), !text.isEmpty else { return }
        let clean = text.replacingOccurrences(of: String(utf16CodeUnits: [RichDocument.anchorCharacter], count: 1), with: "")
        let range = selectedRange
        // 选中的是干了的字：干的划掉，粘贴的接在后面（见 `replaceRespectingInk`）
        if containsDryText(range) {
            replaceRespectingInk(range, with: clean)
            return
        }
        let attributed = NSAttributedString(string: clean, attributes: freshAttributes)
        textStorage.replaceCharacters(in: range, with: attributed)
        selectedRange = NSRange(location: range.location + attributed.length, length: 0)
        manualEditFinished()
    }

    /// 剪贴板里的文字。先按 UTF-8 读原始数据，再退回 `.string` ——
    /// 有的来源只标了「纯文本」却装着 UTF-8，`.string` 会按别的编码解成乱码（模拟器从 Mac 粘贴时实测）
    private static func pastedText() -> String? {
        let board = UIPasteboard.general
        for type in [UTType.utf8PlainText.identifier, UTType.plainText.identifier] {
            if let data = board.data(forPasteboardType: type), let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        return board.string
    }

    // MARK: - 光标别躲到键盘后面

    /// 自己不滚动，所以光标走到屏幕外时要让外层的滚动视图跟过去
    func scrollCaretIntoView() {
        guard isFirstResponder, let range = selectedTextRange else { return }
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scrollView = ancestor as? UIScrollView else { return }
        let caret = caretRect(for: range.end).insetBy(dx: 0, dy: -24)
        DispatchQueue.main.async {
            scrollView.scrollRectToVisible(self.convert(caret, to: scrollView), animated: true)
        }
    }
}

// MARK: - 编辑行为

extension RichTextView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let string = textStorage.string as NSString

        // 新打的字记上这次编辑的时刻、不带划线（光标停在划掉的字后面时，系统会照着前一个字的样子打）
        if !text.isEmpty, sessionDate != nil {
            typingAttributes = freshAttributes
        }

        // 退格正好碰到照片：第一次只选中照片，再按一次才删
        if text.isEmpty, range.length == 1, string.character(at: range.location) == RichDocument.anchorCharacter,
           let anchor = textStorage.attribute(.attachment, at: range.location, effectiveRange: nil) as? PhotoAnchorAttachment {
            if armedPhotoID == anchor.blockID {
                armedPhotoID = nil
                // 墨迹干了的照片不删，换成痕迹
                if let photo = photos[anchor.blockID], isDry(photo) {
                    retire(id: anchor.blockID, kind: .photo)
                    return false
                }
                return true
            }
            armedPhotoID = anchor.blockID
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return false
        }
        // 退格碰到录音（光标紧跟在录音后面，或在录音下一行的行首）：同样先选中，再按一次连同换行一起删
        if text.isEmpty, range.length == 1 {
            var audioIndex: Int?
            if string.character(at: range.location) == RichDocument.anchorCharacter {
                audioIndex = range.location
            } else if string.character(at: range.location) == 0x0A, range.location > 0,
                      string.character(at: range.location - 1) == RichDocument.anchorCharacter {
                audioIndex = range.location - 1
            }
            if let audioIndex,
               let anchor = textStorage.attribute(.attachment, at: audioIndex, effectiveRange: nil) as? AudioAnchorAttachment {
                if armedPhotoID == anchor.blockID {
                    armedPhotoID = nil
                    removeAudio(id: anchor.blockID)
                } else {
                    armedPhotoID = anchor.blockID
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                return false
            }
        }
        armedPhotoID = nil

        // 删 / 改的范围里有干了的字：不能悄悄删，改成划掉
        if containsDryText(range) {
            replaceRespectingInk(range, with: text)
            return false
        }

        // 在段首的照片锚点**前面**打字：改成打在锚点后面，照片还是从这一段的开头起
        if !text.isEmpty, range.length == 0, range.location < string.length,
           textStorage.attribute(.attachment, at: range.location, effectiveRange: nil) is PhotoAnchorAttachment,
           range.location == 0 || string.character(at: range.location - 1) == 0x0A {
            let attributed = NSAttributedString(string: text, attributes: typingAttributes)
            textStorage.insert(attributed, at: range.location + 1)
            selectedRange = NSRange(location: range.location + 1 + attributed.length, length: 0)
            contentDidChange()
            return false
        }

        // 小标题那段末尾回车：新的一段回到正文
        if text == "\n", typingAttributes[.memoirHeading] as? Bool == true {
            var plain = TextFlags(attributes: freshAttributes)
            plain.heading = false
            textStorage.replaceCharacters(in: range, with: NSAttributedString(string: "\n", attributes: style.attributes(plain)))
            selectedRange = NSRange(location: range.location + 1, length: 0)
            typingAttributes = style.attributes(plain)
            contentDidChange()
            onTypingStyleChange?()
            return false
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        contentDidChange()
    }

    /// 选中文字时，系统菜单最前面加一项「荧光笔」（已经划过的显示「擦掉荧光笔」）
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                  suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard isEditable, range.length > 0 else { return nil }
        let on = selectionIsHighlighted
        let title = on
            ? NSLocalizedString("擦掉荧光笔", bundle: .appLanguage, comment: "正文选中文字的菜单：去掉荧光笔")
            : NSLocalizedString("荧光笔", bundle: .appLanguage, comment: "正文选中文字的菜单：用荧光笔标记")
        var actions: [UIMenuElement] = [UIAction(title: title, image: UIImage(systemName: "highlighter")) { [weak self] _ in
            self?.toggleHighlight()
        }]
        // 刚划掉（不到 24 小时）的，可以取消划掉
        if hasWetStrike(range) {
            actions.append(UIAction(title: NSLocalizedString("取消划掉", bundle: .appLanguage, comment: "正文选中文字的菜单：去掉刚划的删除线"),
                                    image: UIImage(systemName: "strikethrough")) { [weak self] _ in
                self?.unstrike(range)
            })
        }
        return UIMenu(children: actions + suggestedActions)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        // 拼字时没刷的「补记」标签，拼完补上（选候选词上屏时，系统不一定再调一次 textViewDidChange）
        if labelsPending, markedTextRange == nil {
            refreshAddendumLabels()
            invalidateIntrinsicContentSize()
            reportHeight()
        }
        // 光标停在照片锚点上（落在段首）时，打字属性跟着前后的字走，不跟锚点
        onTypingStyleChange?()
        scrollCaretIntoView()
    }
}

// MARK: - 照片的菜单（靠左 / 靠右 / 换相纸 / 删除）

extension RichTextView: UIEditMenuInteractionDelegate {
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let idString = configuration.identifier as? String, let id = UUID(uuidString: idString),
              let photo = photos[id] else { return nil }
        let bundle = Bundle.appLanguage
        var actions: [UIAction] = []
        if photo.position == .right {
            actions.append(UIAction(title: NSLocalizedString("放左边", bundle: bundle, comment: "正文照片菜单：挪到左边"),
                                    image: UIImage(systemName: "arrow.left")) { [weak self] _ in
                self?.setPosition(.left, for: id)
            })
        } else {
            actions.append(UIAction(title: NSLocalizedString("放右边", bundle: bundle, comment: "正文照片菜单：挪到右边"),
                                    image: UIImage(systemName: "arrow.right")) { [weak self] _ in
                self?.setPosition(.right, for: id)
            })
        }
        let isCover = photo.isCover == true
        actions.append(UIAction(title: isCover
                                    ? NSLocalizedString("取消封面", bundle: bundle, comment: "正文照片菜单：取消大屏展示封面")
                                    : NSLocalizedString("设为封面", bundle: bundle, comment: "正文照片菜单：设为大屏展示封面"),
                                image: UIImage(systemName: isCover ? "star.slash" : "star")) { [weak self] _ in
            self?.setCover(!isCover, for: id)
        })
        actions.append(UIAction(title: NSLocalizedString("换相纸", bundle: bundle, comment: "正文照片菜单：换相纸样式"),
                                image: UIImage(systemName: "photo.artframe")) { [weak self] _ in
            guard let self, let photo = self.photos[id] else { return }
            self.onRequestPaperStyle?(photo)
        })
        // 墨迹干了的照片是「取下」（留一行痕迹），没干的才是「删除」
        let dry = isDry(photo)
        actions.append(UIAction(title: dry
                                    ? NSLocalizedString("取下", bundle: bundle, comment: "正文照片菜单：取下墨迹已干的照片（原处留痕迹）")
                                    : NSLocalizedString("删除", bundle: bundle, comment: "正文照片菜单：删除照片"),
                                image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.removePhoto(id: id)
        })
        return UIMenu(children: actions)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration,
                             animator: any UIEditMenuInteractionAnimating) {
        animator.addCompletion { [weak self] in self?.armedPhotoID = nil }
    }

    /// 大屏展示封面（设置 → 展示 → 手记页 = 大屏 时生效）。**一篇最多一张**，设新的清掉旧的
    private func setCover(_ on: Bool, for id: UUID) {
        for key in Array(photos.keys) {
            photos[key]?.isCover = key == id ? on : false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        contentDidChange()
    }

    private func setPosition(_ position: PhotoPosition, for id: UUID) {
        guard var photo = photos[id] else { return }
        photo.position = position
        updatePhoto(photo)
    }
}

// MARK: - 浮在正文上的一张照片

/// 用 SwiftUI 的相纸视图画照片，套一层 UIKit 的壳接手势（点一下出菜单、长按拖动）
final class PhotoOverlayView: UIView {
    let blockID: UUID
    var onTap: (() -> Void)?
    var onDragChanged: ((UILongPressGestureRecognizer) -> Void)?

    /// 退格碰到它、或点了它出菜单时，描一圈表示「选中了」
    var isArmed = false {
        didSet {
            layer.borderWidth = isArmed ? 2 : 0
            layer.borderColor = tintColor.withAlphaComponent(0.6).cgColor
            layer.cornerRadius = 6
        }
    }

    private let host: UIHostingController<AnyView>
    private var sizeCache: [CGFloat: CGSize] = [:]

    init(photo: ContentBlock) {
        blockID = photo.id
        host = UIHostingController(rootView: AnyView(EmptyView()))
        super.init(frame: .zero)
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        addSubview(host.view)
        update(photo: photo)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        press.minimumPressDuration = 0.35
        addGestureRecognizer(press)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(photo: ContentBlock) {
        // 相纸视图自己负责倾斜；这里只给它宽度，高度按它要的来
        host.rootView = AnyView(PhotoPaperView(photo: photo).allowsHitTesting(false))
        sizeCache.removeAll()
    }

    func fittingSize(width: CGFloat) -> CGSize {
        if let cached = sizeCache[width] { return cached }
        let size = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        let result = CGSize(width: width, height: ceil(size.height))
        sizeCache[width] = result
        return result
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        host.view.frame = bounds
    }

    @objc private func tapped() { onTap?() }
    @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) { onDragChanged?(recognizer) }
}

// MARK: - 正文里的一段录音

/// 用 SwiftUI 的录音卡片（`AudioPlayerCard`）画，能播放；编辑时右边带删除键
final class AudioOverlayView: UIView {
    let blockID: UUID
    private let host: UIHostingController<AnyView>

    var isArmed = false {
        didSet {
            layer.borderWidth = isArmed ? 2 : 0
            layer.borderColor = tintColor.withAlphaComponent(0.6).cgColor
            layer.cornerRadius = 10
        }
    }

    init(blockID: UUID, path: String, themeManager: ThemeManager?, onDelete: (() -> Void)?) {
        self.blockID = blockID
        let card: AnyView
        if let themeManager {
            card = AnyView(AudioPlayerCard(audioURL: path, onDelete: onDelete).environment(themeManager))
        } else {
            card = AnyView(EmptyView())
        }
        host = UIHostingController(rootView: card)
        super.init(frame: .zero)
        host.view.backgroundColor = .clear
        addSubview(host.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        host.view.frame = bounds
    }
}

// MARK: - 痕迹行

/// 「取下了一张照片 · 10月12日」：正文里一行淡淡的小字，不能点、不能改
final class TraceOverlayView: UIView {
    private let label = UILabel()

    init(text: String, color: UIColor) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        let attributed = NSMutableAttributedString()
        if let icon = UIImage(systemName: "scissors", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10))?
            .withTintColor(color, renderingMode: .alwaysOriginal) {
            attributed.append(NSAttributedString(attachment: NSTextAttachment(image: icon)))
            attributed.append(NSAttributedString(string: "  "))
        }
        attributed.append(NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: color,
            .kern: 0.5,
        ]))
        label.attributedText = attributed
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }
}

// MARK: - 墨迹相关的文案

enum InkText {
    /// 「10月12日」；不是今年的带上年份
    static func day(_ date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let style = sameYear
            ? Date.FormatStyle().month(.abbreviated).day().locale(appLocale)
            : Date.FormatStyle().year().month(.abbreviated).day().locale(appLocale)
        return date.formatted(style)
    }

    /// 整段补记上方的小字
    static func addendumLabel(_ day: Date) -> String {
        String(format: NSLocalizedString("补记 · %@", bundle: .appLanguage, comment: "正文：之后补写的段落上方的小字，%@ 是补写的日期"),
               Self.day(day))
    }

    /// 痕迹行
    static func traceLine(_ trace: ContentBlock) -> String {
        let date = trace.removedAt.map(Date.init(timeIntervalSince1970:)) ?? .now
        let format = trace.traceOf == ContentBlockType.audio.rawValue
            ? NSLocalizedString("删去了一段录音 · %@", bundle: .appLanguage, comment: "正文：墨迹已干的录音被删去后留下的痕迹，%@ 是日期")
            : NSLocalizedString("取下了一张照片 · %@", bundle: .appLanguage, comment: "正文：墨迹已干的照片被取下后留下的痕迹，%@ 是日期")
        return String(format: format, Self.day(date))
    }
}
