import SwiftUI
import UIKit

/// 核心渲染器：把一组 `ContentBlock` 渲染为图文混排视图。
///
/// > 📌 2026-10 起只剩**翻页阅读器**在用。写日记页、编辑页、详情页改用 `RichTextView`
/// > （文字真正绕着照片排、支持格式），阅读器的分页还按这里的块结构算。
///
/// 算法（两指针扫描）：
/// - 遍历 blocks：
///   - 文本块后紧跟一张照片 → 生成 `.photoWithText`，把当前文本（及后续紧邻的文本块）
///     合并切分为 beside（约 55 字）与 below（剩余），直到遇到下一张照片或用完。
///   - 否则生成 `.fullText`。
///   - 独立的照片块（未被前一个文本块消费）会被跳过，因为规格约定"照片必须跟在文本块后面"。
struct ContentBlockRenderer: View {
    let blocks: [ContentBlock]
    let theme: any AppTheme
    let availableWidth: CGFloat

    // 字体覆盖（用于让主题保留各自 body 字体；默认值匹配 MEMOIR_PHOTO_EMBED 规格）
    var fullTextFont: Font = .custom("Georgia", size: 17)
    var fullLineSpacing: CGFloat = 15
    /// 全宽文字颜色；nil 时使用 `theme.textPrimary`
    var fullTextColor: Color? = nil
    /// 小标题的字体（格式见 `StyledText`）
    var headingFont: Font = .custom("Georgia-Bold", size: 20)
    /// 荧光笔的颜色（按主题，见 `RichTextAppearance`）
    var highlightColor: Color = Color(hex: "#F4D46A").opacity(0.6)
    /// 日记写下的时刻：分辨补记用（见 `Ink`）
    var writtenDate: Date? = nil
    /// 补记的墨色
    var laterInkColor: Color = Color(hex: "#3E5470")

    var onPhotoTap: ((ContentBlock) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(renderGroups().enumerated()), id: \.offset) { _, group in
                renderGroup(group)
            }
        }
    }

    // MARK: - 环绕文字容量

    /// 照片旁能容纳的字数 = 照片高度可塞行数 × 每行字数（按真实字体测量）。
    /// 让 beside 文字尽量填满照片高度，与 below 之间不再出现"分行间隔"。
    /// 极端窄宽 / 测量失败时退回 120 字下限（即便如此也不会回到旧的 55 字）。
    private var estimatedCapacity: Int {
        let font = UIFont(name: "Georgia", size: LayoutConstants.wrappedTextFontSize)!
        let lineH = font.lineHeight + LayoutConstants.wrappedLineSpacing
        let photoH = LayoutConstants.photoBlockHeight
        let lines = max(1, Int(photoH / lineH))
        let textW = max(1, availableWidth * (1 - LayoutConstants.photoWidthRatio) - LayoutConstants.photoTextGap)
        let charW = max(1, ("字" as NSString).size(withAttributes: [.font: font]).width)
        let charsPerLine = max(1, Int(textW / charW))
        return max(lines * charsPerLine, 120)
    }

    // MARK: - 分组

    private func renderGroups() -> [RenderGroup] {
        var groups: [RenderGroup] = []
        var i = 0

        while i < blocks.count {
            let block = blocks[i]

            // 录音、痕迹：正文里单独一行
            if block.type == .audio || block.type == .trace {
                groups.append(block.type == .audio ? .audio(block) : .trace(block))
                i += 1
                continue
            }

            // 没有前置文本锚点的照片（相邻照片 / 开头照片）→ 独立渲染，绝不丢弃
            if block.type == .photo {
                groups.append(.standalonePhoto(photo: block))
                i += 1
                continue
            }

            // 当前是文本块：检查下一个是不是照片
            if i + 1 < blocks.count, blocks[i + 1].type == .photo {
                let anchorId = block.id
                let photoBlock = blocks[i + 1]

                // 汇总可用于环绕的文本（从当前文本起，向后累加文本块直到字数够或遇照片）。
                // 带着格式一起拼（加粗、斜体、小标题、荧光笔，见 `StyledText`）
                var merged = styled(block)
                var lastConsumed = i + 1
                var j = i + 2
                while merged.characters.count < estimatedCapacity, j < blocks.count {
                    let nxt = blocks[j]
                    guard nxt.type == .text else { break }  // 遇到下一张照片 / 录音，停止合并
                    // 该文本块紧跟着照片 → 它是下一张照片的锚点，不能被吞并（否则下张照片变孤儿）
                    if j + 1 < blocks.count, blocks[j + 1].type == .photo {
                        break
                    }
                    if !merged.characters.isEmpty { merged += AttributedString("\n") }
                    merged += styled(nxt)
                    lastConsumed = j
                    j += 1
                }

                // 切分 beside / below
                let cap = min(estimatedCapacity, merged.characters.count)
                let splitIndex = merged.characters.index(merged.startIndex, offsetBy: cap)
                let beside = AttributedString(merged[..<splitIndex])
                let belowRaw = AttributedString(merged[splitIndex...])
                let below = belowRaw.characters.isEmpty ? nil : belowRaw

                groups.append(
                    .photoWithText(
                        anchorBlockId: anchorId,
                        photo: photoBlock,
                        besideText: beside,
                        belowText: below
                    )
                )

                i = lastConsumed + 1
            } else {
                // 普通全宽文本块
                groups.append(.fullText(blockId: block.id, text: styled(block)))
                i += 1
            }
        }

        return groups
    }

    // MARK: - 单组渲染

    @ViewBuilder
    private func renderGroup(_ group: RenderGroup) -> some View {
        switch group {
        case .fullText(let blockId, let text):
            fullTextView(text: text, blockId: blockId)

        case .photoWithText(let anchorId, let photo, let beside, let below):
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: LayoutConstants.photoTextGap) {
                    if photo.position == .left {
                        photoView(photo: photo)
                        wrappedTextView(text: beside, blockId: anchorId)
                    } else {
                        wrappedTextView(text: beside, blockId: anchorId)
                        photoView(photo: photo)
                    }
                }

                if let below {
                    fullTextView(text: below, blockId: anchorId)
                }
            }

        case .audio(let block):
            if let path = block.audioFilename {
                AudioPlayerCard(audioURL: path)
            }

        case .trace(let block):
            Label(InkText.traceLine(block), systemImage: "scissors")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
                .frame(height: TraceAnchorAttachment.lineHeight)

        case .standalonePhoto(let photo):
            HStack(spacing: 0) {
                if photo.position == .left {
                    photoView(photo: photo)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    photoView(photo: photo)
                }
            }
        }
    }

    // MARK: - 子视图工厂

    /// 文本块带上格式；荧光笔按主题上色
    private func styled(_ block: ContentBlock) -> AttributedString {
        StyledText.attributed(block, highlight: highlightColor, laterInk: laterInkColor, base: writtenDate,
                              textColor: fullTextColor ?? theme.textPrimary)
    }

    @ViewBuilder
    private func fullTextView(text: AttributedString, blockId: UUID) -> some View {
        let color = fullTextColor ?? theme.textPrimary
        Text(StyledText.applyingHeading(text, font: headingFont))
            .font(fullTextFont)
            .lineSpacing(fullLineSpacing)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private func wrappedTextView(text: AttributedString, blockId: UUID) -> some View {
        let color = fullTextColor ?? theme.textPrimary
        Text(StyledText.applyingHeading(text, font: headingFont))
            .font(.custom("Georgia", size: LayoutConstants.wrappedTextFontSize))
            .lineSpacing(LayoutConstants.wrappedLineSpacing)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
    }

    private func photoView(photo: ContentBlock) -> some View {
        PhotoPaperView(
            photo: photo,
            onTap: onPhotoTap.map { cb in { cb(photo) } }
        )
        .frame(width: availableWidth * LayoutConstants.photoWidthRatio)
    }
}

// MARK: - 常量

private enum LayoutConstants {
    static let photoWidthRatio: CGFloat = 0.45
    static let photoTextGap:    CGFloat = 12
    static let fullTextFontSize:    CGFloat = 16
    static let wrappedTextFontSize: CGFloat = 15
    static let fullLineSpacing:    CGFloat = 8
    static let wrappedLineSpacing: CGFloat = 11
    /// 照片块在页面中的标称高度（与阅读器分页用的 `ReaderLayout.photoBlockHeight` 对齐）
    static let photoBlockHeight: CGFloat = 280
}

// MARK: - 渲染组

private enum RenderGroup {
    case fullText(blockId: UUID, text: AttributedString)
    case photoWithText(
        anchorBlockId: UUID,
        photo: ContentBlock,
        besideText: AttributedString,
        belowText: AttributedString?
    )
    /// 录音（单独一行的播放卡片）
    case audio(ContentBlock)
    /// 痕迹（取下的照片 / 删去的录音）
    case trace(ContentBlock)
    /// 无环绕文字的独立照片（相邻照片 / 开头照片）
    case standalonePhoto(photo: ContentBlock)
}
