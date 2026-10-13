import SwiftUI

/// 一枚封着的火漆信，一下一下拆开（2026-10-11 产品定）：
/// 第一下打碎火漆 → 第二下打开信封 → 第三下抽出信纸，抽完自己摊成信纸（`onFinished`）。
///
/// - 每一下点下去，这一步就接着播，播完停在那等下一下 —— 中间不刻意停顿，也不催
/// - **急着连点**：这一步还没播完又点了，就不再等，后面几步首尾相接一口气拆完，和以前的一气呵成一样
/// - 「减弱动态效果」打开时：点一下直接换成信纸，只轻轻一顿
/// - 旁白（VoiceOver）的「激活」动作一口气拆完
///
/// 震动和纸声见 `LetterOpeningFeel`，动画见 `SealedEnvelope`
struct SealedLetterOpener: View {
    let palette: LetterPalette
    /// 火漆上压的字（笔友名字的首字）
    let sealMark: String?
    /// 信封背面那行「来自 某某」，也是旁白读出来的
    let sender: Text
    /// 第一下打碎火漆的那一刻（信算拆开了）
    var onBroken: () -> Void = {}
    /// 信纸抽出来了，该摊开成信纸了
    var onFinished: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var feel = LetterOpeningFeel()
    @State private var progress: Double = 0
    /// 已经开始的步数：0 = 还封着，1 = 火漆碎了，2 = 信封开了，3 = 信纸在抽 / 抽完了
    @State private var stage = 0
    /// 有一步正在播
    @State private var playing = false
    /// 急着连点：后面的步不等了，一口气拆完
    @State private var hurried = false
    @State private var finished = false

    var body: some View {
        let theme = themeManager.current
        GeometryReader { geo in
            VStack(spacing: 28) {
                SealedEnvelope(palette: palette, sealMark: sealMark, sender: sender, progress: progress)
                    .frame(width: min(geo.size.width - 64, 340))

                // 下一下该做什么。正在播、或者急着拆完的时候不显示
                ZStack {
                    hint(Text("轻点火漆，拆开这封信"), visible: stage == 0)
                    hint(Text("再点一下，打开信封"), visible: stage == 1 && !playing && !hurried)
                    hint(Text("再点一下，抽出信纸"), visible: stage == 2 && !playing && !hurried)
                }
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
            }
            // 抽出来的信纸会冒出信封上沿，整体放在中间偏下，给它留出地方
            .padding(.top, 80)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { tap() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sender)
        .accessibilityHint(Text("拆开这封信"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            hurried = true
            if !playing { tap() }
        }
        // 先把震动引擎热起来，点下去那一刻才不会慢半拍
        .onAppear { feel.prepare() }
        .onDisappear { feel.stop() }
    }

    private func hint(_ text: Text, visible: Bool) -> some View {
        text
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: visible)
    }

    // MARK: - 一下一下拆

    private func tap() {
        guard !finished else { return }
        if reduceMotion {
            guard stage == 0 else { return }
            stage = 3
            finished = true
            onBroken()
            feel.playQuiet()
            onFinished()
            return
        }
        // 这一步还在播又点了：急了，后面的不等了
        if playing {
            hurried = true
            return
        }
        advance()
    }

    /// 播下一步。播完：抽出来了就摊开；急着拆的话接着播下一步；否则停在这等下一下
    private func advance() {
        guard stage < LetterOpeningFeel.stageTargets.count else { return }
        let step = stage
        stage += 1
        playing = true
        if step == 0 { onBroken() }
        // 震动和纸声与这一步的动画同时起步
        feel.play(stage: step)
        withAnimation(.linear(duration: LetterOpeningFeel.duration(ofStage: step))) {
            progress = LetterOpeningFeel.stageTargets[step]
        } completion: {
            playing = false
            if stage == LetterOpeningFeel.stageTargets.count {
                finished = true
                onFinished()
            } else if hurried {
                advance()
            }
        }
    }
}
