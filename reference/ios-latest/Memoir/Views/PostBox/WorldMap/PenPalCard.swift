import SwiftUI
import CoreLocation

/// 地图下面的一张名片：一位笔友是谁、住哪儿、他那里此刻几点、回信要多久，以及「寄给他」。
///
/// 纸是「纸」，不跟主题明暗走（同 `LetterPalette`）—— 皮革主题的深色桌面上也是一张米白的名片
struct PenPalCard: View {
    enum Subject {
        case world(PenPal)
        /// 自己起名的那一位：没有住址
        case own(name: String)
    }

    let subject: Subject
    let userLocation: CLLocationCoordinate2D?
    let isRecipient: Bool
    let isMember: Bool
    /// 这位世界笔友现在能不能寄（总开关开着、且服务端备好了他的人设）
    let canSend: Bool
    let palette: LetterPalette
    let postInk: Color
    let onToggle: () -> Void
    let onBecomeMember: () -> Void

    static let height: CGFloat = 196

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.locale) private var locale

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // 自己起名的那位没有地区码：贴尺素自己的 m. 邮票（和领邮票卡片上同一张，2026-10-27 用户定）
                if case .own = subject {
                    MarkStamp(ink: postInk, paper: palette.paper)
                } else {
                    StampPlaceholder(code: stampCode, ink: postInk, paper: palette.paper)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title)
                        .font(theme.headingFont)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    subtitle
                        .font(theme.captionFont)
                        .foregroundStyle(palette.ink.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            line
                .font(theme.bodyFont)
                .foregroundStyle(palette.ink.opacity(0.85))
                .lineSpacing(3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                if case .world(let penPal) = subject {
                    TimelineView(.everyMinute) { context in
                        localNow(penPal, at: context.date)
                    }
                }
                Spacer(minLength: 0)
                Label {
                    Text(replyTime.label)
                } icon: {
                    Image(systemName: "envelope")
                }
                .labelStyle(TightLabelStyle())
            }
            .font(theme.captionFont)
            .foregroundStyle(palette.ink.opacity(0.6))

            action
        }
        .padding(16)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(palette.paper)
                .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 1)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - 内容

    private var title: String {
        switch subject {
        case .world(let penPal): return "\(penPal.place.resolved(for: locale)) · \(penPal.surname.resolved(for: locale))"
        case .own(let name): return name
        }
    }

    private var shortName: String {
        switch subject {
        case .world(let penPal): return penPal.surname.resolved(for: locale)
        case .own(let name): return name
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch subject {
        case .world(let penPal):
            let country = locale.localizedString(forRegionCode: penPal.region) ?? penPal.region
            let place = penPal.place.resolved(for: locale)
            // 新加坡、南极：地名就是国名，不重复写
            let where_ = (penPal.isAntarctic || country == place) ? nil : country
            if let distance = distanceText(to: penPal) {
                if let where_ {
                    Text("\(where_) · 离你 \(distance)")
                } else {
                    Text("离你 \(distance)")
                }
            } else {
                Text(verbatim: where_ ?? place)
            }
        case .own:
            Text("没有住址 · 就在你身边")
        }
    }

    private var line: Text {
        switch subject {
        case .world(let penPal): return Text(verbatim: penPal.card.resolved(for: locale))
        case .own: return Text("你自己起名的笔友，用你的语言写信。")
        }
    }

    private var stampCode: String {
        switch subject {
        case .world(let penPal): return penPal.region
        case .own: return ""  // 不用：自己那位贴的是 MarkStamp
        }
    }

    private var replyTime: PenPalTravel.ReplyTime {
        switch subject {
        case .world(let penPal): return PenPalTravel.replyTime(to: penPal, from: userLocation)
        case .own: return .ownPenPal
        }
    }

    private func distanceText(to penPal: PenPal) -> String? {
        guard let userLocation else { return nil }
        let kilometers = PenPalTravel.distanceKilometers(userLocation, penPal.location)
        // 取整到十公里：精确到一公里是假精确
        let rounded = (kilometers / 10).rounded() * 10
        return Measurement(value: rounded, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale))
    }

    private func localNow(_ penPal: PenPal, at date: Date) -> some View {
        let clock = PenPalLocalTime.clock(of: penPal, at: date, locale: locale)
        let season = PenPalLocalTime.season(of: penPal, at: date)
        return Label {
            if let season {
                Text("当地 \(clock) · \(Text(season.label))")
            } else {
                Text("当地 \(clock)")
            }
        } icon: {
            Image(systemName: PenPalLocalTime.isDaytime(of: penPal, at: date) ? "sun.max" : "moon")
        }
        .labelStyle(TightLabelStyle())
    }

    // MARK: - 寄给他

    @ViewBuilder
    private var action: some View {
        if case .world = subject, !canSend {
            Text("即将开放")
                .frame(maxWidth: .infinity)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.ink.opacity(0.4))
                .padding(.vertical, 9)
                .overlay(Capsule().strokeBorder(palette.ink.opacity(0.2), lineWidth: 1))
                .accessibilityLabel(Text("即将开放"))
        } else if case .world = subject, !isMember {
            Button(action: onBecomeMember) {
                Text("成为会员，给\(shortName)写信")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CardActionStyle(ink: postInk, paper: palette.paper, filled: false))
        } else {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    if isRecipient {
                        Image(systemName: "checkmark")
                        Text("在收件人里")
                    } else {
                        Text("寄给\(shortName)")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CardActionStyle(ink: postInk, paper: palette.paper, filled: isRecipient))
            .accessibilityAddTraits(isRecipient ? .isSelected : [])
        }
    }
}

/// 名片上的按钮：没选是描边，选上了是实心（像在表格上打了勾）
private struct CardActionStyle: ButtonStyle {
    let ink: Color
    let paper: Color
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(filled ? paper : ink)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(filled ? ink : Color.clear)
            )
            .overlay(Capsule().strokeBorder(ink.opacity(filled ? 0 : 0.8), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// 图标和字挨得近一点
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// 邮票占位：齿孔边框 + 地区码。第 3 步换成每位笔友的邮票图
struct StampPlaceholder: View {
    let code: String
    let ink: Color
    let paper: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(paper)
            Rectangle()
                .strokeBorder(ink.opacity(0.55), style: StrokeStyle(lineWidth: 2.2, dash: [0.1, 4.2]))
                .padding(1)
            Rectangle()
                .strokeBorder(ink.opacity(0.4), lineWidth: 0.8)
                .padding(6)
            Text(verbatim: code)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(ink.opacity(0.8))
        }
        .frame(width: 44, height: 52)
        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0.5)
        .accessibilityHidden(true)
    }
}
