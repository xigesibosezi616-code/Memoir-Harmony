import SwiftUI
import SwiftData

/// 信箱 —— 收信的地方（被动）。
///
/// 只显示**已经到达**的回信。在路上的信（`LetterDelivery.isInTransit`）这里看不见，
/// 到了点才出现 —— 这就是「信箱收信是随机、被动的」。
///
/// 从邮筒页右上角进来，或者点「回信到了」的通知直达。
///
/// ## 归类（2026-10-20 产品定）
///
/// 信越收越多，顶上可以切三种看法（记住上次选的）：
/// - **全部来信**：按到达时间一列（原来的样子）
/// - **按笔友**：一位笔友一组，最近来过信的那位在最上面。世界笔友按 id 归（换了 App 语言、姓的写法变了也是同一组）；
///   自己起名的那位（没有 id 的信，包括改名之前的）归成一组，组名用现在的名字
/// - **按日期**：按到达的月份一月一组，最近的在上面
///
/// 分组点一下展开、再点收起；没动过的时候只展开最上面那一组
struct LetterboxView: View {
    @Environment(ThemeManager.self) private var themeManager

    @Query(sort: \Letter.generatedAt, order: .reverse) private var letters: [Letter]

    /// 「此刻」。每隔几秒推进一次：信是按时间到达的，页面开着时也要让新到的信冒出来
    @State private var now = Date.now
    @AppStorage("letterboxGrouping") private var groupingRaw = LetterboxGrouping.all.rawValue
    /// 自己起名的那位笔友现在叫什么（这一组的组名）
    @AppStorage(PenPalName.storageKey) private var penPalName: String = ""
    @State private var expansion = GroupExpansion()
    /// 新手指引 ⑧：指着第一封回信那一行（全局坐标）
    @AppStorage(FirstStep.storageKey) private var firstStepRaw = 0
    @AppStorage(FirstStep.replyIDKey) private var firstReplyID = ""
    @State private var replyRowFrame: CGRect = .zero
    @Namespace private var pickerNamespace

    private var grouping: LetterboxGrouping { LetterboxGrouping(rawValue: groupingRaw) ?? .all }

    private var arrived: [Letter] {
        letters
            .filter { LetterDelivery.hasArrived($0, now: now) }
            .sorted { LetterDelivery.arrival(of: $0) > LetterDelivery.arrival(of: $1) }
    }

    /// 写好了还没到的，和投进邮筒、回信还在写的（`LetterOutbox`），对用户来说都是「在路上」
    private var hasLettersInTransit: Bool {
        letters.contains { LetterDelivery.isInTransit($0, now: now) || LetterOutbox.isQueued($0) }
    }

    var body: some View {
        let theme = themeManager.current
        let arrived = arrived
        ScrollView {
          VStack(spacing: 0) {
            if arrived.isEmpty {
                card(theme: theme) { emptyState(theme: theme) }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            } else {
                groupingPicker(theme: theme)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                switch grouping {
                case .all:
                    card(theme: theme) { rows(arrived, theme: theme) }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                case .penPal, .month:
                    let groups = groups(of: arrived)
                    VStack(spacing: 10) {
                        ForEach(groups) { group in
                            groupCard(group, expanded: expansion.isExpanded(group.id, in: grouping, first: groups.first?.id),
                                      first: groups.first?.id, theme: theme)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }

            if hasLettersInTransit && !arrived.isEmpty {
                Text("有回信正在路上")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.top, 16)
            }
          }
          .padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("信箱")
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                now = .now
            }
        }
        .overlay {
            if FirstStep(rawValue: firstStepRaw) == .replyArrived, replyRowFrame != .zero {
                GuideHint(text: "点开这封回信", target: replyRowFrame, below: true, theme: theme)
            }
        }
    }

    // MARK: - 一列信

    private func card<Content: View>(theme: any AppTheme, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func rows(_ list: [Letter], theme: any AppTheme) -> some View {
        ForEach(Array(list.enumerated()), id: \.element.id) { index, letter in
            if index > 0 {
                Divider().overlay(theme.border).padding(.leading, 68)
            }
            NavigationLink {
                LetterDetailView(letter: letter)
            } label: {
                LetterRow(letter: letter, isUnread: LetterDelivery.isUnread(letter, now: now), theme: theme)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                if letter.id.uuidString == firstReplyID { replyRowFrame = frame }
            }
        }
    }

    // MARK: - 归类

    /// 顶上的三种看法
    private func groupingPicker(theme: any AppTheme) -> some View {
        HStack(spacing: 4) {
            ForEach(LetterboxGrouping.allCases, id: \.self) { option in
                let selected = option == grouping
                Button {
                    withAnimation(.smooth(duration: 0.25)) { groupingRaw = option.rawValue }
                } label: {
                    Text(option.title)
                        .font(theme.captionFont)
                        .foregroundStyle(selected ? theme.accent : theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(theme.accent.opacity(0.14))
                                    .matchedGeometryEffect(id: "selected", in: pickerNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.cardBackground))
        .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
    }

    private static let ownPenPal = "own"

    /// 按笔友 / 按月份分好的组，最近来信的那组在最上面（组里也是最近的在上面）
    private func groups(of arrived: [Letter]) -> [LetterGroup] {
        switch grouping {
        case .all:
            return []
        case .penPal:
            return Dictionary(grouping: arrived) { $0.penPalID ?? Self.ownPenPal }
                .map { key, list in
                    let name = key == Self.ownPenPal
                        ? PenPalName.display(penPalName)
                        : PenPalRoster.penPal(id: key)?.surname.resolved(for: appLocale) ?? list[0].fromCharacter
                    return LetterGroup(id: "penPal:\(key)", title: name, initial: String(name.first ?? "青"),
                                       letters: list, now: now)
                }
                .sorted { $0.latest > $1.latest }
        case .month:
            let calendar = Calendar.current
            return Dictionary(grouping: arrived) { letter in
                calendar.dateInterval(of: .month, for: LetterDelivery.arrival(of: letter))?.start ?? LetterDelivery.arrival(of: letter)
            }
            .map { month, list in
                LetterGroup(id: "month:\(Int(month.timeIntervalSince1970))",
                            title: month.formatted(.dateTime.year().month(.wide).locale(appLocale)),
                            initial: nil, letters: list, now: now)
            }
            .sorted { $0.latest > $1.latest }
        }
    }

    private func groupCard(_ group: LetterGroup, expanded: Bool, first: String?, theme: any AppTheme) -> some View {
        card(theme: theme) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expansion.toggle(group.id, in: grouping, first: first)
                }
            } label: {
                groupHeader(group, expanded: expanded, theme: theme)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(group.title), \(group.letters.count)"))
            .accessibilityHint(expanded ? Text("收起") : Text("展开"))
            .accessibilityAddTraits(.isButton)

            if expanded {
                Divider().overlay(theme.border)
                rows(group.letters, theme: theme)
            }
        }
    }

    /// 组头：（笔友的首字）名字 / 月份 …… 有没读的 · 几封 · ›
    private func groupHeader(_ group: LetterGroup, expanded: Bool, theme: any AppTheme) -> some View {
        HStack(spacing: 12) {
            if let initial = group.initial {
                ZStack {
                    Circle().fill(theme.accentBackground)
                    Text(verbatim: initial)
                        .font(.custom("Georgia", size: 16))
                        .foregroundStyle(theme.accent)
                }
                .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: group.title)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                // 按笔友时写最近一封哪天到的；按日期时组名就是日子，不重复写
                if group.initial != nil {
                    Text(group.latest.shortDate)
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            Spacer(minLength: 8)
            if group.hasUnread {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 8, height: 8)
            }
            // 几封：只写数字，免得七种语言各配一套单复数
            Text(verbatim: "\(group.letters.count)")
                .font(theme.labelFont.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(theme.surfaceBackground))
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, group.initial == nil ? 16 : 12)
    }

    private func emptyState(theme: any AppTheme) -> some View {
        VStack(spacing: 8) {
            Text("信箱还是空的")
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
            if hasLettersInTransit {
                Text("有回信正在路上")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 归类用的

/// 信箱的三种看法。存进 UserDefaults 的是 rawValue（记住上次选的）
enum LetterboxGrouping: String, CaseIterable {
    case all
    case penPal
    case month

    var title: LocalizedStringKey {
        switch self {
        case .all: return "全部来信"
        case .penPal: return "按笔友"
        case .month: return "按日期"
        }
    }
}

/// 一组信：一位笔友的，或者一个月的
private struct LetterGroup: Identifiable {
    let id: String
    /// 组名：笔友的名字（用户数据）或者「2026年10月」（按 App 语言排好的日期）—— 都原样显示，不查翻译表
    let title: String
    /// 按笔友时头像上的字；按日期时没有
    let initial: String?
    /// 最近到的在前
    let letters: [Letter]
    let latest: Date
    let hasUnread: Bool

    init(id: String, title: String, initial: String?, letters: [Letter], now: Date) {
        self.id = id
        self.title = title
        self.initial = initial
        self.letters = letters
        if let first = letters.first {
            latest = LetterDelivery.arrival(of: first)
        } else {
            latest = .distantPast
        }
        hasUnread = letters.contains { LetterDelivery.isUnread($0, now: now) }
    }
}

/// 哪几组展开着（每种看法各记各的，离开信箱就忘）。没动过的时候只展开最上面那一组
private struct GroupExpansion {
    private var opened: [LetterboxGrouping: Set<String>] = [:]

    func isExpanded(_ id: String, in grouping: LetterboxGrouping, first: String?) -> Bool {
        if let set = opened[grouping] { return set.contains(id) }
        return id == first
    }

    mutating func toggle(_ id: String, in grouping: LetterboxGrouping, first: String?) {
        var set = opened[grouping] ?? Set(first.map { [$0] } ?? [])
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        opened[grouping] = set
    }
}

// MARK: - 一行

struct LetterRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let letter: Letter
    let isUnread: Bool
    let theme: any AppTheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leading
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("来自\(letter.fromCharacter)")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    // 信箱里显示的是**收到的日子**（到达时刻），不是寄出的日子
                    Text(LetterDelivery.arrival(of: letter).shortDate)
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                }
                // 火漆信没拆之前看不到里面写了什么 —— 和实物一样，拆开才算读到
                Group {
                    if letter.isSealed && isUnread {
                        Text("火漆封着，还没拆")
                    } else {
                        Text(String(letter.body.prefix(60)))
                    }
                }
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Circle()
                .fill(theme.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .opacity(isUnread ? 1 : 0)
        }
    }

    /// 火漆信是一枚小信封（没拆的封着，拆过的封舌翻开）；普通信是笔友头像（首字 in circle）
    @ViewBuilder
    private var leading: some View {
        if letter.isSealed {
            SealedEnvelope(
                palette: LetterPalette.of(themeID: themeManager.currentThemeID),
                sealMark: WaxSeal.initial(of: letter.fromCharacter),
                progress: isUnread ? 0 : 0.55
            )
            .frame(width: 40)
            // 翻开的封舌会冒出信封上沿，往下挪一点，让整体落在头像那一格里
            .offset(y: isUnread ? 0 : 7)
            .accessibilityHidden(true)
        } else {
            ZStack {
                Circle().fill(theme.accentBackground)
                Text(String(letter.fromCharacter.first ?? "青"))
                    .font(.custom("Georgia", size: 16))
                    .foregroundStyle(theme.accent)
            }
        }
    }
}
