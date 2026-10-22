import SwiftUI
import UIKit

/// 工具栏遥控正文编辑器：加粗、斜体、小标题、插照片。
///
/// 按钮亮不亮（`isBold` 等）跟着光标处的格式走
@Observable
final class RichTextController {
    fileprivate weak var textView: RichTextView?

    private(set) var isBold = false
    private(set) var isItalic = false
    private(set) var isHeading = false
    private(set) var isHighlighted = false

    func toggleBold() { textView?.toggleBold(); refresh() }
    func toggleItalic() { textView?.toggleItalic(); refresh() }
    func toggleHeading() { textView?.toggleHeading(); refresh() }
    func toggleHighlight() { textView?.toggleHighlight(); refresh() }

    /// 在光标处插一张照片
    func insertPhoto(_ photo: ContentBlock) { textView?.insertPhoto(photo) }
    /// 照片换了相纸 / 换了边
    func updatePhoto(_ photo: ContentBlock) { textView?.updatePhoto(photo) }
    /// 在光标下一行插一段录音（`path` 是 "audio/xxx.m4a" 这样的相对路径）
    func insertAudio(path: String) { textView?.insertAudio(ContentBlock(audioFilename: path)) }

    func focus() { textView?.becomeFirstResponder() }

    fileprivate func refresh() {
        isBold = textView?.selectionIsBold ?? false
        isItalic = textView?.selectionIsItalic ?? false
        isHeading = textView?.selectionIsHeading ?? false
        isHighlighted = textView?.selectionIsHighlighted ?? false
    }
}

/// 图文正文（SwiftUI 包装）。可编辑时是写日记的编辑器，不可编辑时是详情页的正文 —— 同一套排版。
///
/// 自己不滚动、高度随内容长，要放在 `ScrollView` 里。
///
/// **高度由编辑器自己报上来**（`measuredHeight`）：SwiftUI 只在布局时问一次 `sizeThatFits`，
/// 之后 UIKit 视图里打字变高了它并不知道 —— 2026-10-10 实测，正文第三行起被下面的「心情」压住。
/// 第一次还没量到时不设高度，用 `sizeThatFits` 的结果
struct RichEntryEditor: View {
    @Binding var blocks: [ContentBlock]
    var controller: RichTextController? = nil
    var isEditable = true
    var appearance: RichTextAppearance
    /// 日记写下的时刻（`JournalEntry.createdAt`）。有它才分得出补记、才有「墨迹会干」（见 `Ink`）；写新日记时不传
    var writtenDate: Date? = nil
    /// 这次编辑开始的时刻（改已有日记时传）。这次写的字都记成这个时刻写的
    var sessionDate: Date? = nil
    var onPhotoTap: ((ContentBlock) -> Void)? = nil
    var onRequestPaperStyle: ((ContentBlock) -> Void)? = nil

    @State private var measuredHeight: CGFloat?
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        RichTextRepresentable(
            themeManager: themeManager,
            blocks: $blocks,
            controller: controller,
            isEditable: isEditable,
            appearance: appearance,
            writtenDate: writtenDate,
            sessionDate: sessionDate,
            onPhotoTap: onPhotoTap,
            onRequestPaperStyle: onRequestPaperStyle,
            onHeightChange: { measuredHeight = $0 }
        )
        .frame(height: measuredHeight)
    }
}

private struct RichTextRepresentable: UIViewRepresentable {
    let themeManager: ThemeManager
    @Binding var blocks: [ContentBlock]
    var controller: RichTextController? = nil
    var isEditable = true
    var appearance: RichTextAppearance
    var writtenDate: Date?
    var sessionDate: Date?
    var onPhotoTap: ((ContentBlock) -> Void)? = nil
    var onRequestPaperStyle: ((ContentBlock) -> Void)? = nil
    var onHeightChange: (CGFloat) -> Void

    /// 外观 + 墨迹的基准时刻
    private var style: RichTextStyle {
        var style = appearance.style
        style.baseDate = writtenDate
        return style
    }

    final class Coordinator {
        /// 编辑器自己最后一次交出去的内容。外面传进来的和它不同，才说明是外面改的（比如恢复草稿），要重新装
        var lastBlocks: [ContentBlock] = []
        /// 编辑器最近交出去的几版内容。
        ///
        /// SwiftUI 回传给 `updateUIView` 的值可能比编辑器里慢一拍（打字时每个键都在交新内容，
        /// SwiftUI 合并更新时手里还是上一版）。拿慢一拍的旧内容去重新装，正在拼的字就被打断，
        /// 后面的字接到别处、还重复一遍（2026-10-11 拼音输入实测）。
        /// 所以：传进来的是自己交出去过的，一律当回声，不重装
        var recentlyEmitted: [[ContentBlock]] = []
        /// 比外观的原始值，不比转出来的 UIFont / UIColor —— 后者每次都是新对象，比了就会每次重装、光标跳走
        var lastAppearance: RichTextAppearance?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RichTextView {
        let view = RichTextView()
        view.themeManager = themeManager
        view.style = style
        view.sessionDate = sessionDate
        view.isEditable = isEditable
        view.load(blocks: blocks)
        context.coordinator.lastBlocks = blocks
        context.coordinator.lastAppearance = appearance
        wire(view, context: context)
        return view
    }

    func updateUIView(_ view: RichTextView, context: Context) {
        view.isEditable = isEditable
        if context.coordinator.lastAppearance != appearance {
            context.coordinator.lastAppearance = appearance
            view.style = style
            view.load(blocks: view.blocks)
        }
        // 只有外面真的换了内容（比如恢复草稿）才重新装；自己交出去的回声、输入法正在拼字时都不动
        let coordinator = context.coordinator
        if blocks != coordinator.lastBlocks, !coordinator.recentlyEmitted.contains(blocks), view.markedTextRange == nil {
            view.load(blocks: blocks)
            coordinator.lastBlocks = blocks
        }
        wire(view, context: context)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RichTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        return CGSize(width: width, height: uiView.fittingHeight(forWidth: width))
    }

    private func wire(_ view: RichTextView, context: Context) {
        let coordinator = context.coordinator
        let binding = $blocks
        view.onChange = { [weak view] in
            guard let view else { return }
            let current = view.blocks
            coordinator.lastBlocks = current
            coordinator.recentlyEmitted.append(current)
            if coordinator.recentlyEmitted.count > 12 { coordinator.recentlyEmitted.removeFirst() }
            binding.wrappedValue = current
        }
        view.onPhotoTap = onPhotoTap
        view.onRequestPaperStyle = onRequestPaperStyle
        let report = onHeightChange
        view.onHeightChange = { height in
            // 在 SwiftUI 的更新周期里直接改 @State 会报「Modifying state during view update」，挪到下一轮
            DispatchQueue.main.async { report(height) }
        }
        if let controller {
            controller.textView = view
            view.onTypingStyleChange = { [weak controller] in controller?.refresh() }
        }
    }
}

/// 工具栏上的加粗 / 斜体 / 小标题。按钮亮不亮跟着光标处的格式走
struct RichFormatButtons: View {
    let controller: RichTextController
    let theme: any AppTheme

    var body: some View {
        HStack(spacing: 0) {
            button("bold", on: controller.isBold, label: "加粗") { controller.toggleBold() }
            button("italic", on: controller.isItalic, label: "斜体") { controller.toggleItalic() }
            button("textformat.size", on: controller.isHeading, label: "小标题") { controller.toggleHeading() }
            button("highlighter", on: controller.isHighlighted, label: "荧光笔") { controller.toggleHighlight() }
        }
    }

    private func button(_ symbol: String, on: Bool, label: LocalizedStringKey,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? theme.textPrimary : theme.textSecondary)
                .frame(width: 36, height: 32)
                .background(on ? theme.textPrimary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .frame(width: 42, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
