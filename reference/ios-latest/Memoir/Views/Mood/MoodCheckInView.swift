import SwiftUI

/// 这一次记下的心情：滑杆的愉悦度（他自己选的那档，**不是**呼吸引导时画面褪到的）+ 选的那个情绪词
nonisolated struct MoodRecord {
    let valence: Double
    let label: MoodLabel
}

/// 写完日记、保存之后弹出来的「此刻的心情」（2026-10-16 产品定）：每篇新日记保存后都要过这一页，点「完成」才回去。
///
/// 两步：① 滑杆选个大概，九档里的哪一档（线团爱心、震动、不愉快时的呼吸引导都在这一步）；
/// ② 点「下一步」，在这一档对应的 3～5 个词里选一个（`MoodLabel.choices(for:)`），点「完成」结束。
/// 点「完成」把 `MoodRecord` 交给调用方存进日记（还不写进「健康」，见 `Docs/HarmonyUpdates/U03_mood_checkin.md`）。
struct MoodCheckInView: View {
    @Environment(ThemeManager.self) private var themeManager
    private let onDone: (MoodRecord) -> Void
    @State private var valence: Double
    @State private var step: Step = .level
    @State private var label: MoodLabel?
    @State private var haptics = MoodHaptics()
    /// 停在不愉快那边，3 秒后换成呼吸引导
    @State private var stillTask: Task<Void, Never>?
    /// 呼吸引导从哪一刻开始；nil = 不在呼吸引导里
    @State private var breathingSince: Date?
    /// 跟着呼吸做完了几轮（`MoodCalm`）：心停在平常，提示换成收尾那句，不再引导呼吸
    @State private var calmed = false

    private enum Step { case level, labels }

    init(initialValence: Double = 0, onDone: @escaping (MoodRecord) -> Void) {
        _valence = State(initialValue: initialValence)
        self.onDone = onDone
    }

    var body: some View {
        let theme = themeManager.current
        let level = MoodLevel(valence: valence)
        let picking = step == .labels

        VStack(spacing: 0) {
            // 标题：第一步问心情，第二步问哪些词；第二步左上角能回去改档位
            Group {
                if picking {
                    Text("哪个词最贴近此刻？")
                } else {
                    Text("写完了，此刻的心情是？")
                }
            }
            .font(theme.headingFont)
            .foregroundStyle(theme.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(alignment: .leading) {
                if picking {
                    CircleIconButton(systemName: "chevron.left", prominence: .glass, theme: theme, size: 14, placement: .floating) {
                        withAnimation(.easeInOut(duration: 0.45)) { step = .level }
                    }
                    .accessibilityLabel(Text("返回"))
                    .transition(.opacity)
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 16)

            // 中间那颗线团爱心：直接画在纸上（彩色细线的质感本身就和尺素搭，不用框）。
            // 弹簧让心慢半拍跟上滑杆，每根线跟得快慢不一，像被拂过一样换样子。选词那一步心缩小、留在上面
            ScribbleHeart(valence: valence, target: valence, breathingSince: breathingSince, calmed: calmed, haptics: haptics)
                .animation(.smooth(duration: 0.7), value: valence)
                .frame(maxWidth: .infinity, maxHeight: picking ? 220 : .infinity)
                .padding(.horizontal, 16)

            Text(level.title)
                .font(.custom("Georgia", size: 28))
                .foregroundStyle(theme.textPrimary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: level)

            if picking {
                labelPicker(theme: theme, level: level)
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    // 提示语要一眼看得见：正文色、标题字号，紧挨在档位下面；固定留两行，换句子时下面不跳
                    hint(theme: theme, level: level)
                        .frame(height: 58)
                        .padding(.horizontal, 32)
                        .padding(.top, 6)

                    MoodSlider(valence: $valence, track: theme.surfaceBackground, tick: theme.textTertiary.opacity(0.5))
                        .padding(.horizontal, 28)
                        .padding(.top, 12)

                    HStack {
                        Text("很不愉快")
                        Spacer()
                        Text("很愉快")
                    }
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }
                .transition(.opacity)
            }

            Button {
                if picking {
                    if let label { onDone(MoodRecord(valence: valence, label: label)) }
                } else {
                    withAnimation(.easeInOut(duration: 0.45)) { step = .labels }
                }
            } label: {
                Group {
                    if picking {
                        Text("完成")
                    } else {
                        Text("下一步")
                    }
                }
                .font(theme.bodyFont.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(picking && label == nil)
            .opacity(picking && label == nil ? 0.4 : 1)
            .animation(.easeOut(duration: 0.2), value: label == nil)
            .padding(.horizontal, 48)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .onAppear {
            haptics.start(valence: valence)
            waitForStillness()
        }
        .onDisappear {
            stillTask?.cancel()
            haptics.stop()
        }
        .onChange(of: valence) { _, newValue in
            // 呼吸引导里（或做完之后）又动了滑杆：回到滑杆那档
            if breathingSince != nil {
                breathingSince = nil
                calmed = false
                haptics.endBreathing(valence: newValue)
            } else {
                haptics.update(valence: newValue)
            }
            // 换了一档：这一档没有的词不再算选中
            if let label, !MoodLabel.choices(for: MoodLevel(valence: newValue)).contains(label) {
                self.label = nil
            }
            waitForStillness()
        }
    }

    /// 第二步：这一档对应的 3～5 个词，选一个
    private func labelPicker(theme: any AppTheme, level: MoodLevel) -> some View {
        VStack(spacing: 18) {
            Text("选一个最贴近的")
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
            FlowLayout(spacing: 10, lineSpacing: 12) {
                ForEach(MoodLabel.choices(for: level)) { item in
                    chip(item, theme: theme, tint: level.tint)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.15), value: label)
    }

    /// 一个情绪词：选中了描一圈这一档的颜色、底上淡淡一层
    private func chip(_ item: MoodLabel, theme: any AppTheme, tint: Color) -> some View {
        let selected = label == item
        return Button {
            label = item
        } label: {
            Text(item.title)
                .font(theme.headingFont.weight(selected ? .semibold : .regular))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(selected ? tint.opacity(0.22) : Color.clear))
                .overlay(Capsule().strokeBorder(selected ? tint : theme.border, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 档位下面那句话：不愉快那头先请他停一停，停够了跟着震动吸气、呼气，做完了说一句收尾的话；
    /// 平常和愉快那头说一句好话（`MoodLevel.hint`）
    @ViewBuilder
    private func hint(theme: any AppTheme, level: MoodLevel) -> some View {
        Group {
            if calmed {
                // 🔴 只说「希望」，不说「好了」「缓解了」
                Text("希望这短短的一会儿，让你好受了一点")
            } else if let breathingSince {
                TimelineView(.periodic(from: breathingSince, by: 0.25)) { timeline in
                    if MoodBreath.isInhaling(since: breathingSince, now: timeline.date) {
                        Text("跟着震动，慢慢吸气……")
                    } else {
                        Text("……慢慢呼气")
                    }
                }
            } else {
                Text(level.hint)
            }
        }
        .font(theme.headingFont)
        .foregroundStyle(theme.textPrimary)
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.4), value: breathingSince)
        .animation(.easeInOut(duration: 0.6), value: calmed)
        .animation(.easeInOut(duration: 0.3), value: level)
    }

    /// 在不愉快那边停住 3 秒 → 呼吸引导；跟着呼吸几轮、褪到平常 → 收尾（动一下滑杆就都取消）
    private func waitForStillness() {
        stillTask?.cancel()
        guard breathingSince == nil, MoodLevel(valence: valence).isUnpleasant else { return }
        let start = valence
        stillTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let since = haptics.beginBreathing() else { return }
            breathingSince = since
            try? await Task.sleep(for: .seconds(MoodCalm.duration(from: start)))
            guard !Task.isCancelled else { return }
            calmed = true
            haptics.finishBreathing()
        }
    }
}

// MARK: - 滑杆

/// 一根带刻度的滑杆（像尺子，九档之间八道刻度）。可以滑到任意位置，愉悦度是连续的；九档只决定显示的字和手感
private struct MoodSlider: View {
    @Binding var valence: Double
    let track: Color
    let tick: Color

    private let height: CGFloat = 44
    private let thumb: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - thumb)
            ZStack(alignment: .topLeading) {
                Capsule().fill(track)
                ForEach(1..<MoodLevel.count, id: \.self) { i in
                    Rectangle()
                        .fill(tick)
                        .frame(width: 1, height: 8)
                        .position(x: CGFloat(i) / CGFloat(MoodLevel.count) * usable + thumb / 2, y: height / 2)
                }
                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                    .position(x: (valence + 1) / 2 * usable + thumb / 2, y: height / 2)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        valence = min(max((g.location.x - thumb / 2) / usable * 2 - 1, -1), 1)
                    }
            )
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(Text("此刻的心情"))
        .accessibilityValue(Text(MoodLevel(valence: valence).title))
        .accessibilityAdjustableAction { direction in
            let level = MoodLevel(valence: valence)
            switch direction {
            case .increment: valence = (MoodLevel(rawValue: min(MoodLevel.count - 1, level.rawValue + 1)) ?? level).centerValence
            case .decrement: valence = (MoodLevel(rawValue: max(0, level.rawValue - 1)) ?? level).centerValence
            @unknown default: break
            }
        }
    }
}
