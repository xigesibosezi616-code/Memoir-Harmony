/**
 * 拆火漆信的时间轴（纯逻辑，10_BUILD_MANUAL.md 5.7）。
 * 对应 iOS `Views/PostBox/Envelope/LetterOpeningFeel.swift` 的常量段，秒值逐字一致
 * （动画、震动、声音三处踩同一条时间轴，**改一处要三处一起改**）。
 *
 * 拆信是三下（R-BOX-05）：第一下打碎火漆、第二下打开信封、第三下抽出信纸
 * （抽完自己摊开）。急着连点时三步首尾相接，等于一口气拆完。
 */

/** 拆信三步的下标（stage） */
export enum LetterOpeningStage {
  /** 打碎火漆 */
  Crack = 0,
  /** 打开信封（封舌翻起） */
  Unflap = 1,
  /** 抽出信纸 */
  Slide = 2
}

export class LetterOpeningTimeline {
  /** 拆信一口气走完的时长（三步加起来），各步按 progress 的份额分 */
  static readonly ANIMATION_DURATION: number = 2.6;
  /** 每一步结束时拆信进度到哪：火漆裂开、封舌翻起、信纸抽出 */
  static readonly STAGE_TARGETS: number[] = [0.14, 0.55, 1.0];
  /** 抽出后摊成信纸的淡入时长 */
  static readonly UNFOLD_DURATION: number = 0.55;
  /** 三步 */
  static readonly STAGE_COUNT: number = 3;

  /** 第 stage 步（0、1、2）的动画时长：按它在整条拆信里占的 progress 份额算 */
  static durationOfStage(stage: number): number {
    if (stage < 0 || stage >= LetterOpeningTimeline.STAGE_COUNT) {
      return 0;
    }
    const from = stage === 0 ? 0 : LetterOpeningTimeline.STAGE_TARGETS[stage - 1];
    return (LetterOpeningTimeline.STAGE_TARGETS[stage] - from) *
      LetterOpeningTimeline.ANIMATION_DURATION;
  }
}
