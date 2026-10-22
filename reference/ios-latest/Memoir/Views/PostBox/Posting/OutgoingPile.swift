import SwiftUI

/// 这次要寄出的一篇日记（值快照，给邮筒页的那叠纸用）
struct OutgoingItem: Identifiable, Equatable {
    let id: UUID
    let date: Date
    /// 标题；没写标题的用正文第一行，都没有就是空串（显示「无题」）
    let title: String
}

/// 邮筒页下方那一叠「要寄的日记」（2026-10-11 产品定）。
///
/// 一页信纸上按格线列出日期 + 标题，默认全勾；取消勾选的这次不寄（服务器只收到勾上的）。
/// 底下垫两张错开一点的纸，看得出是一叠。纸是「纸」，不跟主题明暗走（同 `LetterPalette`）。
/// 一篇都没有时也摆着：一页空格线，写一篇多一行（2026-10-16 产品定，见 `PostBoxView.bottom`）。
///
/// `interactive == false` 时只是一张画（投信动画收拢那一下用它的样子，见 `LetterPostingFlight`）
struct OutgoingPile: View {
    let palette: LetterPalette
    let items: [OutgoingItem]
    /// 取消勾选的那几篇
    @Binding var excluded: Set<UUID>
    /// 信纸抬头写着寄给谁（「青鸟、McRae」）
    let recipients: String
    var interactive: Bool = true
    /// 点抬头的「寄给」：打开世界笔友地图挑收件人
    var onTapRecipients: (() -> Void)?

    /// 一行的高度。超过 `visibleRows` 行就在纸里滚动
    static let rowHeight: CGFloat = 40
    static let visibleRows: CGFloat = 3.5
    static let headerHeight: CGFloat = 34

    /// 整叠纸占的高度（含垫在下面的两张露出来的边）
    static var height: CGFloat { headerHeight + rowHeight * visibleRows + 14 }

    private var checkedCount: Int { items.filter { !excluded.contains($0.id) }.count }
    private var isScrollable: Bool { Self.scrolls(items.count) }

    /// 这么多篇放不下、要在纸里滚动（邮筒页据此判断：往上划是在翻纸，还是在把信往投信口推）
    static func scrolls(_ count: Int) -> Bool { CGFloat(count) > visibleRows }
    /// 纸上还空着几行（只画到看得见的那几行为止）
    private var blankRows: Int { max(0, Int(Self.visibleRows.rounded(.up)) - items.count) }

    var body: some View {
        ZStack {
            // 垫在下面的两张：错开一点点，不晃
            sheet.rotationEffect(.degrees(-1.6)).offset(x: -3, y: 5).opacity(0.75)
            sheet.rotationEffect(.degrees(1.1)).offset(x: 4, y: 3).opacity(0.9)

            VStack(spacing: 0) {
                header
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                        }
                        // 篇数少时下面接着画空格线：像一页没写满的信纸，而不是一块空白
                        ForEach(0..<blankRows, id: \.self) { _ in
                            Color.clear
                                .frame(height: Self.rowHeight)
                                .overlay(alignment: .bottom) { rule }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(!interactive || !isScrollable)
                // 放不下时最后半行淡下去，看得出底下还有
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .black.opacity(isScrollable ? 0.15 : 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.rowHeight * 0.6)
                    }
                }
            }
            .background(sheet)
        }
        .frame(height: Self.height - 8)
    }

    private var sheet: some View {
        Rectangle()
            .fill(palette.paper)
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
    }

    /// 抬头：「寄给 青鸟 ⊕」—— 像信封上写地址，点它去地图上挑收件人（2026-10-15 产品定）
    private var header: some View {
        HStack(spacing: 8) {
            if let onTapRecipients, interactive {
                Button(action: onTapRecipients) {
                    address.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("寄给\(recipients)"))
                .accessibilityHint(Text("挑选收件人"))
            } else {
                address
            }
            Spacer(minLength: 8)
            // 勾上几篇 / 一共几篇。不写成「N 篇」，免得七种语言各配一套单复数；一篇都没有时不写「0 / 0」
            if !items.isEmpty {
                Text(verbatim: "\(checkedCount) / \(items.count)")
                    .monospacedDigit()
            }
        }
        .font(.custom("Georgia", size: 12).italic())
        .foregroundStyle(palette.ink.opacity(0.55))
        .padding(.horizontal, 18)
        .frame(height: Self.headerHeight)
        .overlay(alignment: .bottom) { rule }
    }

    private var address: some View {
        HStack(spacing: 5) {
            Text("寄给")
            Text(verbatim: recipients.isEmpty ? "—" : recipients)
                .font(.custom("Georgia", size: 13))
                .foregroundStyle(palette.ink.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            if onTapRecipients != nil {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
            }
        }
    }

    private func row(_ item: OutgoingItem) -> some View {
        let checked = !excluded.contains(item.id)
        return Button {
            guard interactive else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                if checked { excluded.insert(item.id) } else { excluded.remove(item.id) }
            }
        } label: {
            HStack(spacing: 12) {
                CheckMark(checked: checked, ink: palette.ink, tick: palette.liner)
                Text(item.date.shortDate)
                    .font(.custom("Georgia", size: 12))
                    .foregroundStyle(palette.ink.opacity(0.55))
                    .frame(minWidth: 52, alignment: .leading)
                Group {
                    if item.title.isEmpty {
                        Text("无题")
                    } else {
                        Text(verbatim: item.title)
                    }
                }
                .font(.custom("Georgia", size: 15))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .opacity(checked ? 1 : 0.38)
            .padding(.horizontal, 18)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { rule }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? [.isButton, .isSelected] : .isButton)
    }

    /// 信纸上的格线
    private var rule: some View {
        Rectangle()
            .fill(palette.rule)
            .frame(height: 0.6)
            .padding(.horizontal, 12)
    }
}

/// 勾选框：一个手画似的小方框，勾上了是一笔红（跟着信封内衬的颜色）
private struct CheckMark: View {
    let checked: Bool
    let ink: Color
    let tick: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .stroke(ink.opacity(0.45), lineWidth: 1)
                .frame(width: 15, height: 15)
            if checked {
                TickShape()
                    .stroke(tick, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 13, height: 11)
                    .offset(x: 1.5, y: -1.5)
                    .transition(.opacity)
            }
        }
        .frame(width: 18, height: 18)
    }
}

private struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.midY))
        return p
    }
}
