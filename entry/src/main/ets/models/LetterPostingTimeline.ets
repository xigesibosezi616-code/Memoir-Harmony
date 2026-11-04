/**
 * 投信一口气的时间轴（秒，从点下邮筒算起）。
 * 对应 iOS `Posting/LetterPostingFlight.swift` 的 `LetterPostingTimeline`，秒值逐字一致
 * （动画、震动、声音三处踩同一条时间轴，**改一处要三处一起改**）。
 *
 * 全程不过冲：分段都是 linear 夹取或 smoothstep（u²(3−2u)），没有回弹
 * （R-POST-08、记忆「交互贴着实物」）。
 */
export class LetterPostingTimeline {
  /** 那叠日记收拢成一页信纸，悬在打开的信封上方 */
  static readonly GATHER_START: number = 0.0;
  static readonly GATHER_END: number = 0.32;
  /** 信纸滑进信封 */
  static readonly SLIDE_IN_START: number = 0.32;
  static readonly SLIDE_IN_END: number = 0.95;
  /** 封舌合上，1.40 落下 */
  static readonly FLAP_CLOSE_START: number = 0.95;
  static readonly FLAP_CLOSE_END: number = 1.40;
  /** 会员：火漆落下、压平（1.76 压实）；免费：手指顺着封口抹一下 */
  static readonly SEAL_START: number = 1.46;
  static readonly SEAL_END: number = 1.76;
  /** 信封举到投信口 */
  static readonly RISE_START: number = 1.82;
  static readonly RISE_END: number = 2.42;
  /** 推进投信口 */
  static readonly INSERT_START: number = 2.42;
  static readonly INSERT_END: number = 2.82;
  /** 投信口里的翻板落回去，2.90 那一声闷响 */
  static readonly FLAP_FALL_START: number = 2.82;
  static readonly FLAP_FALL_END: number = 2.90;
  /** 整个动作的长度 */
  static readonly TOTAL: number = 2.95;

  /** t 在区间里走到哪（0…1，线性），出区间夹住；退化区间（end ≤ start）按端点判 */
  static linear(t: number, start: number, end: number): number {
    if (end <= start) {
      return t >= end ? 1 : 0;
    }
    const u = (t - start) / (end - start);
    return Math.min(1, Math.max(0, u));
  }

  /** 同上，两头缓（smoothstep，不过冲） */
  static smooth(t: number, start: number, end: number): number {
    const u = LetterPostingTimeline.linear(t, start, end);
    return u * u * (3 - 2 * u);
  }

  /**
   * 信封的拆信进度倒着走（投信时 progress 从 1 收到 0）：
   * 信纸滑进去（1 → 0.55），封舌合上（0.55 → 0.12），合上后归零。
   */
  static envelopeProgress(t: number): number {
    if (t < LetterPostingTimeline.SLIDE_IN_START) {
      return 1;
    }
    if (t < LetterPostingTimeline.SLIDE_IN_END) {
      return 1 - 0.45 *
        LetterPostingTimeline.linear(t, LetterPostingTimeline.SLIDE_IN_START, LetterPostingTimeline.SLIDE_IN_END);
    }
    if (t < LetterPostingTimeline.FLAP_CLOSE_END) {
      return 0.55 - 0.43 *
        LetterPostingTimeline.linear(t, LetterPostingTimeline.FLAP_CLOSE_START, LetterPostingTimeline.FLAP_CLOSE_END);
    }
    return 0;
  }

  /** 火漆沿封舌边裂开的程度（progress 0…1 → 0…1，拆信用；投信全程在封着的那头） */
  static envelopeCrack(progress: number): number {
    return LetterPostingTimeline.smooth(progress, 0, 0.14);
  }

  /** 封舌翻起的比例（progress 0…1 → 0…1，×180° 是封舌角度） */
  static envelopeLift(progress: number): number {
    return LetterPostingTimeline.smooth(progress, 0.12, 0.55);
  }

  /** 信纸往外抽的比例（progress 0…1 → 0…1，1 = 完全抽出悬在信封上方） */
  static envelopeSlide(progress: number): number {
    return LetterPostingTimeline.smooth(progress, 0.55, 1);
  }
}
