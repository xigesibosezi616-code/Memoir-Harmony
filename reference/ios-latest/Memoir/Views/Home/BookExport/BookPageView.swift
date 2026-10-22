import SwiftUI

/// 书的一页，A5 大小，画进 PDF（也拿来做导出前的预览）。
///
/// 页面一律白底（印的时候白就是纸，不费墨）；封面、封底是满版的布面 / 照片 / 纸。
/// 右页（书翻开右边那页）订口在左、页码在右下；左页反过来 —— `index` 是这一页在整本书里的下标，第 0 页（封面）是右页
struct BookPageView: View {
    let page: BookPage
    let index: Int
    let info: BookInfo
    /// 这一页上的照片（按 `BookFigure.source`），画之前解好；没解到的用同比例的浅灰块占着
    var images: [String: UIImage] = [:]

    private var isRecto: Bool { index % 2 == 0 }
    private var size: CGSize { BookLayout.pageSize }
    /// 版心左边：右页订口在左
    private var textLeft: CGFloat { isRecto ? BookLayout.inner : BookLayout.outer }

    /// 封皮色取照片主色：满版编辑封面时不显示颜色，这本书在书架上的书脊也是照片主色
    private var usesPhotoTint: Bool {
        info.coverPhoto != nil && !info.coverLayout.showsCoverColor && info.photoTint != nil
    }
    /// 封皮色：布面、贴照片是布面色，杂志是纸色（都是这本选的颜色），满版是照片主色。封底、点缀都跟着它
    private var bindingColor: Color {
        if usesPhotoTint, let tint = info.photoTint { return tint }
        return Color(hex: info.color.hex)
    }
    private var bindingIsLight: Bool {
        usesPhotoTint ? UIColor(bindingColor).isLightColor : info.color.isLight
    }
    /// 点缀色：封皮色（太浅的换成墨色）
    private var accent: Color {
        bindingIsLight ? BookLayout.inkSecondary : bindingColor
    }
    /// 布面上烫的字的颜色（同日记本主页的大图）
    private var foil: Color {
        info.color.isLight ? Color(hex: "#6B5A3E") : Color(hex: "#D9C08A")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            switch page {
            case .cover: cover
            case .titlePage: titlePage
            case .contents(let lines, let first): contents(lines, first: first)
            case .body(let body): bodyPage(body)
            case .colophon: colophon
            case .backCover: backCover
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .environment(\.locale, appLocale)
    }

    // MARK: - 封面、封底

    /// 封面按这个宽度排：编辑封面时那张大预览的宽度（`BookCustomizerView`）
    private static let coverDesignWidth: CGFloat = 150

    /// 封面就是这本日记本自己的封面（`BookCoverView`：书架上、编辑封面时看到的那张）。
    /// 先按编辑页大预览的宽度、A5 的比例排好，再整张放大到一页 —— 书名、篇数和封面的比例与 App 里一样，
    /// 字放大了照样是矢量
    private var cover: some View {
        let width = Self.coverDesignWidth
        return BookCoverView(
            name: info.title,
            entryCount: info.entryCount,
            color: info.color,
            photo: info.coverPhoto.map(CoverPhotoSource.image),
            layout: info.coverLayout,
            aspect: size.width / size.height,
            elevated: false
        )
        .frame(width: width, height: width * size.height / size.width)
        .scaleEffect(size.width / width, anchor: .topLeading)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// 布面：日记本封面的亚麻放大铺满（同日记本主页的大图：四周的压边、书脊阴影、烫标都裁在外面）
    private var cloth: some View {
        Image("Cover_\(info.color.rawValue)_\(BookTexture.linen.rawValue)")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .scaleEffect(1.25, anchor: UnitPoint(x: 0.5, y: 0.42))
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    /// 一种颜色铺满，压一层纸纹
    private func papered(_ color: Color) -> some View {
        ZStack {
            color
            Image("Texture_Paper")
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .opacity(0.22)
                .blendMode(.multiply)
                .clipped()
        }
        .frame(width: size.width, height: size.height)
    }

    /// 封底跟着封面的材料：布面、贴照片是同一块布；杂志是同一张纸；满版是照片主色的纸。下方一行小字
    private var backCover: some View {
        ZStack {
            if info.coverPhoto != nil && info.coverLayout == .framed {
                let paper = MagazinePaper(color: info.color)
                paper.gradient
                backMark(paper.ink.opacity(0.55))
            } else if usesPhotoTint {
                papered(bindingColor)
                backMark(bindingIsLight ? BookLayout.inkSecondary : Color.white.opacity(0.7))
            } else {
                cloth
                backMark(foil.opacity(0.7))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func backMark(_ color: Color) -> some View {
        VStack {
            Spacer()
            Text("MEMOIR · 尺素")
                .font(.system(size: 8, weight: .regular, design: .serif))
                .tracking(2.4)
                .foregroundStyle(color)
                .padding(.bottom, 46)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - 扉页、版权页

    private var titlePage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: size.height * 0.30)
            Text(verbatim: info.title)
                .font(BookFonts.font(24))
                .foregroundStyle(BookLayout.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
            Rectangle().fill(accent).frame(width: 28, height: 0.8)
                .padding(.top, 22)
            Text(verbatim: info.subtitle ?? info.dateRange)
                .font(BookFonts.font(10))
                .tracking(1.2)
                .foregroundStyle(BookLayout.inkSecondary)
                .padding(.top, 18)
            if info.subtitle != nil {
                Text(verbatim: info.dateRange)
                    .font(BookFonts.font(8.5))
                    .tracking(1)
                    .foregroundStyle(BookLayout.inkTertiary)
                    .padding(.top, 6)
            }
            if let author = info.author {
                Text(verbatim: author)
                    .font(BookFonts.font(11))
                    .tracking(2)
                    .foregroundStyle(BookLayout.ink)
                    .padding(.top, 48)
            }
            Spacer()
            Text("MEMOIR · 尺素")
                .font(.system(size: 7.5, design: .serif))
                .tracking(2.4)
                .foregroundStyle(BookLayout.inkTertiary)
                .padding(.bottom, 52)
        }
        .padding(.horizontal, 60)
        .frame(width: size.width, height: size.height)
    }

    /// 版权页：靠下，一小段说明这本书
    private var colophon: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer()
            Text(verbatim: info.title)
                .font(BookFonts.font(10, bold: true))
                .foregroundStyle(BookLayout.ink)
            Text(verbatim: info.dateRange)
                .font(BookFonts.font(8.5))
                .foregroundStyle(BookLayout.inkSecondary)
            Text("共 \(info.entryCount) 篇 · \(info.photoCount) 张照片")
                .font(BookFonts.font(8.5))
                .foregroundStyle(BookLayout.inkSecondary)
            Rectangle().fill(BookLayout.hairline).frame(width: 120, height: 0.5)
                .padding(.vertical, 8)
            Text("\(info.exportedAt.formatted(Date.FormatStyle(locale: appLocale).year().month(.wide).day()))由尺素排版")
                .font(BookFonts.font(8))
                .foregroundStyle(BookLayout.inkTertiary)
            HStack(spacing: 6) {
                Image("SinaraMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 10, height: 10)
                    .opacity(0.55)
                Text("MEMOIR · 尺素")
                    .font(.system(size: 7.5, design: .serif))
                    .tracking(2)
                    .foregroundStyle(BookLayout.inkTertiary)
            }
            .padding(.top, 4)
        }
        .frame(width: BookLayout.textWidth, alignment: .leading)
        .padding(.leading, textLeft)
        .padding(.bottom, BookLayout.bottom + 40)
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
    }

    // MARK: - 目录

    private func contents(_ lines: [BookContentsLine], first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if first {
                Text("目录")
                    .font(BookFonts.font(15, bold: true))
                    .tracking(4)
                    .foregroundStyle(BookLayout.ink)
                    .frame(height: BookContents.headingHeight - 18, alignment: .top)
                Rectangle().fill(accent).frame(width: 28, height: 0.8)
                    .frame(height: 18, alignment: .top)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .month(let month):
                    Text(verbatim: month)
                        .font(BookFonts.font(9))
                        .tracking(1.5)
                        .foregroundStyle(accent)
                        .frame(height: BookContents.monthLineHeight, alignment: .bottomLeading)
                        .padding(.bottom, 0)
                case .entry(let day, let title, let folio):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: day)
                            .font(BookFonts.font(8.5))
                            .foregroundStyle(BookLayout.inkTertiary)
                            .frame(width: 30, alignment: .leading)
                        (title.map { Text(verbatim: $0) } ?? Text("无题"))
                            .font(BookFonts.font(9.5))
                            .foregroundStyle(BookLayout.ink)
                            .lineLimit(1)
                        DottedLeader()
                            .frame(height: 1)
                            .layoutPriority(-1)
                        Text(verbatim: "\(folio)")
                            .font(BookFonts.font(8.5))
                            .foregroundStyle(BookLayout.inkSecondary)
                    }
                    .frame(height: BookContents.entryLineHeight)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: BookLayout.textWidth, height: BookLayout.textHeight, alignment: .topLeading)
        .offset(x: textLeft, y: BookLayout.top)
    }

    // MARK: - 正文

    private func bodyPage(_ page: BookBodyPage) -> some View {
        ZStack(alignment: .topLeading) {
            // 页眉：左页书名，右页这一页是哪个月
            Text(verbatim: isRecto ? page.month : info.title)
                .font(BookFonts.font(BookLayout.runningHeadSize))
                .tracking(1.6)
                .foregroundStyle(BookLayout.inkTertiary)
                .lineLimit(1)
                .frame(width: BookLayout.textWidth)
                .position(x: textLeft + BookLayout.textWidth / 2, y: BookLayout.runningHeadY)

            VStack(alignment: .leading, spacing: BookLayout.blockGap) {
                ForEach(Array(page.items.enumerated()), id: \.offset) { _, item in
                    itemView(item)
                }
            }
            .frame(width: BookLayout.textWidth, alignment: .leading)
            .offset(x: textLeft, y: BookLayout.top)

            // 页码：在切口那边的下角
            Text(verbatim: "\(page.folio)")
                .font(BookFonts.font(BookLayout.folioSize))
                .foregroundStyle(BookLayout.inkSecondary)
                .position(x: isRecto ? size.width - BookLayout.outer : BookLayout.outer,
                          y: size.height - BookLayout.folioY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func itemView(_ item: BookItem) -> some View {
        switch item {
        case .header(let header):
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: header.date)
                    .font(BookFonts.font(BookLayout.dateSize))
                    .tracking(1.4)
                    .foregroundStyle(accent)
                if let title = header.title {
                    Text(verbatim: title)
                        .font(BookFonts.font(BookLayout.titleSize, bold: true))
                        .lineSpacing(BookPaginator.titleLineSpacing)
                        .foregroundStyle(BookLayout.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, BookPaginator.titleSpacing)
                }
                if let mood = header.mood {
                    Text(mood.title)
                        .font(BookFonts.font(BookLayout.moodSize))
                        .foregroundStyle(BookLayout.inkTertiary)
                        .padding(.top, BookPaginator.moodSpacing)
                }
                Rectangle().fill(accent)
                    .frame(width: BookLayout.ruleWidth, height: BookPaginator.ruleHeight)
                    .padding(.top, BookPaginator.ruleSpacing)
                    .padding(.bottom, BookLayout.headerBottomGap)
            }
            .padding(.top, header.topGap)

        case .text(let block, let writtenAt):
            Text(StyledText.applyingHeading(
                StyledText.attributed(block, highlight: Color(hex: "#F4D46A").opacity(0.55),
                                      laterInk: Color(hex: "#3E5470"), base: writtenAt, textColor: BookLayout.ink),
                font: BookFonts.font(BookLayout.headingSize, bold: true)
            ))
            .font(BookFonts.font(BookLayout.bodySize))
            .lineSpacing(BookLayout.bodyLineSpacing)
            .foregroundStyle(BookLayout.ink)
            .frame(width: BookLayout.textWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

        case .figures(let row):
            // 一排一张（居中）或两张（并排、相纸一样高）；页底塞不下时整排等比缩小（`row.scale`），从不拉伸
            HStack(alignment: .top, spacing: BookLayout.pairGap) {
                ForEach(Array(row.figures.enumerated()), id: \.offset) { i, figure in
                    BookPhotoPaper(block: figure.block,
                                   image: images[figure.source] ?? BookPhotoPaper.placeholder(aspect: figure.aspect))
                        .frame(width: row.widths[i])
                }
            }
            .frame(width: row.width, height: row.height, alignment: .top)
            .scaleEffect(row.scale, anchor: .top)
            .frame(width: BookLayout.textWidth, height: row.scaledHeight, alignment: .top)

        case .audio:
            Label("一段录音", systemImage: "waveform")
                .font(BookFonts.font(8.5))
                .foregroundStyle(BookLayout.inkTertiary)

        case .place(let place):
            Text(verbatim: place)
                .font(BookFonts.font(8))
                .foregroundStyle(BookLayout.inkTertiary)
                .padding(.top, 4)
        }
    }
}

/// 目录里标题和页码之间那一串小点
private struct DottedLeader: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(BookLayout.inkTertiary.opacity(0.7), style: StrokeStyle(lineWidth: 0.6, dash: [0.6, 3]))
        }
    }
}

/// 书里的一张照片：和正文里一样的相纸、一样的微微歪，只是图换成印刷用的大图。
///
/// 不用 `PhotoPaperView`：它的 Live Photo 是系统的实况照片视图（画不进 PDF），还带着点击、长按
struct BookPhotoPaper: View {
    let block: ContentBlock
    let image: UIImage

    /// 和照片同比例的浅灰块：排版时量相纸多大用它（不用解原图），没解到图时也拿它占位
    static func placeholder(aspect: CGFloat) -> UIImage {
        let size = CGSize(width: 64, height: max(1, (64 / max(aspect, 0.05)).rounded()))
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(white: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    var body: some View {
        paper
            .rotationEffect(.degrees(block.rotationAngle ?? 0))
    }

    @ViewBuilder
    private var paper: some View {
        switch block.paperStyle ?? .polaroid {
        case .original:       OriginalPhotoPaper(uiImage: image)
        case .polaroid:       PolaroidPaper(uiImage: image)
        case .washiSticker:   WashiStickerPaper(uiImage: image)
        case .minimalCard:    MinimalCardPaper(uiImage: image)
        case .filmFrame:      FilmFramePaper(uiImage: image)
        case .letterAttached: LetterAttachedPaper(uiImage: image)
        }
    }
}
