/**
 * 一枚封着的火漆信，一下一下拆开（10_BUILD_MANUAL.md 5.7，R-BOX-05）。
 * 对应 iOS `Views/PostBox/Envelope/SealedLetterOpener.swift`。
 *
 * 第一下打碎火漆 → 第二下打开信封 → 第三下抽出信纸，抽完自己摊成信纸
 * （`onFinished`）。
 * - 每一下点下去，这一步就接着播，播完停在那等下一下——中间不刻意停顿，也不催
 * - **急着连点**：这一步还没播完又点了，就不再等，后面几步首尾相接一口气拆完
 * - 震动和纸声见 `LetterOpeningFeel`（踩 `LetterOpeningTimeline`），动画见 `SealedEnvelope`
 * - 「减弱动态效果」：鸿蒙没有对应系统设置 / 查询 API（平台偏差，记
 *   PROGRESS.md 5.7），iOS 的「点一下直接换成信纸」分支不做
 */
import { LetterPalette } from './LetterPalette';
import { SealedEnvelope } from './SealedEnvelope';
import { LetterOpeningFeel } from '../../services/LetterOpeningFeel';
import { LetterOpeningTimeline } from '../../models/LetterOpeningTimeline';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

/** 信封宽的上限（iOS min(宽 − 64, 340)） */
const ENVELOPE_WIDTH_MAX_VP: number = 340;
/** 信封两侧留白（iOS 64/2） */
const ENVELOPE_SIDE_MARGIN_VP: number = 32;
/** 提示淡入淡出（iOS easeOut 0.3s） */
const HINT_FADE_MS: number = 300;
/** 三条提示（R-BOX-05，随步变） */
const HINTS: Resource[] = [
  $r('app.string.s_ade3dc5859'),
  $r('app.string.s_5b7d127ef6'),
  $r('app.string.s_6c42607c7c')
];

@Component
export struct SealedLetterOpener {
  palette: LetterPalette = LetterPalette.bamboo;
  /** 火漆上压的字（笔友名字的首字） */
  mark: string = '素';
  /** 信封背面那行「来自 某某」 */
  sender: ResourceStr = '';
  /** 第一下打碎火漆的那一刻（信算拆开了） */
  onBroken: () => void = (): void => {};
  /** 信纸抽出来了，该摊开成信纸了 */
  onFinished: () => void = (): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  /** 拆信进度：0 = 封着，1 = 信纸已经抽出来 */
  @State private progress: number = 0;
  /** 已经开始的步数：0 = 还封着，1 = 火漆碎了，2 = 信封开了，3 = 信纸在抽 / 抽完了 */
  @State private stage: number = 0;
  /** 有一步正在播 */
  @State private playing: boolean = false;
  /** 急着连点：后面的步不等了，一口气拆完 */
  @State private hurried: boolean = false;
  /** 信纸抽完了 */
  @State private finished: boolean = false;
  /** 信封宽（容器实测后定，见 onAreaChange） */
  @State private envelopeWidthVp: number = ENVELOPE_WIDTH_MAX_VP;
  private feel: LetterOpeningFeel = new LetterOpeningFeel();

  aboutToAppear(): void {
    // 先把声音和编排预备好，点下去那一刻才不会慢半拍（iOS prepare）
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.feel.prepare(context.resourceManager);
    }
  }

  aboutToDisappear(): void {
    this.feel.release();
  }

  build() {
    Column({ space: 28 }) {
      SealedEnvelope({
        palette: this.palette,
        mark: this.mark,
        hasSeal: true,
        progress: this.progress,
        widthVp: this.envelopeWidthVp,
        sender: this.sender
      })

      // 下一下该做什么。正在播、或者急着拆完的时候不显示
      Stack() {
        this.hint(HINTS[0], this.stage === 0)
        this.hint(HINTS[1], this.stage === 1 && !this.playing && !this.hurried)
        this.hint(HINTS[2], this.stage === 2 && !this.playing && !this.hurried)
      }
      .width('100%')
      .alignContent(Alignment.Top)
    }
    // 信封几何中心对齐屏幕中心（2026-11-05 用户定「信封在屏幕中间」）。
    // 组（信封 + 提示）居中在内容区时，信封中心实测低于屏幕中心 68px
    //（标题栏把内容区往下压 + 提示行在信封下方拖低组中心），单靠 padding
    // 到不了（padding 0 时仍低 68px）——用 offset 上移找齐（真机标定）
    .width('100%')
    .height('100%')
    .offset({ y: -20.5 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      this.tap();
    })
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const w: number = Number(newArea.width);
      this.envelopeWidthVp =
        Math.min(Math.max(w - 2 * ENVELOPE_SIDE_MARGIN_VP, 0), ENVELOPE_WIDTH_MAX_VP);
    })
  }

  /** 一条提示：淡入淡出跟着 visible 走 */
  @Builder
  private hint(text: Resource, visible: boolean) {
    Text(text)
      .fontSize(this.theme.captionFont.size)
      .fontWeight(this.theme.captionFont.weight)
      .fontFamily(this.theme.captionFont.family)
      .fontColor(this.theme.textTertiary)
      .opacity(visible ? 1 : 0)
      .animation({ duration: HINT_FADE_MS, curve: Curve.EaseOut })
  }

  // ---- 一下一下拆 ----

  private tap(): void {
    if (this.finished) {
      return;
    }
    // 这一步还在播又点了：急了，后面的不等了
    if (this.playing) {
      this.hurried = true;
      return;
    }
    this.advance();
  }

  /** 播下一步。播完：抽出来了就摊开；急着拆的话接着播下一步；否则停在这等下一下 */
  private advance(): void {
    if (this.stage >= LetterOpeningTimeline.STAGE_COUNT) {
      return;
    }
    const step = this.stage;
    this.stage += 1;
    this.playing = true;
    if (step === 0) {
      // 第一下打碎火漆的那一刻，信就算拆开了（R-BOX-04）
      this.onBroken();
    }
    // 震动和纸声与这一步的动画同时起步；进度线性推进到这一步的目标
    //（iOS withAnimation(.linear)，平滑在 SealedEnvelope 的 phase 里做）
    this.feel.play(step);
    const durationMs = Math.round(LetterOpeningTimeline.durationOfStage(step) * 1000);
    this.getUIContext().animateTo({
      duration: durationMs,
      curve: Curve.Linear,
      onFinish: (): void => {
        this.playing = false;
        if (this.stage === LetterOpeningTimeline.STAGE_COUNT) {
          this.finished = true;
          this.onFinished();
        } else if (this.hurried) {
          this.advance();
        }
      }
    }, (): void => {
      this.progress = LetterOpeningTimeline.STAGE_TARGETS[step];
    });
  }
}
