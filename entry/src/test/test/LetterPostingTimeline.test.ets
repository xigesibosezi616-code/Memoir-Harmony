/**
 * 投信时间轴单测（LetterPostingTimeline）。
 * 锚点：iOS `Posting/LetterPostingFlight.swift` 的 LetterPostingTimeline 秒值
 * 逐字一致；动画 / 震动 / 声音三处踩同一条轴，分段衔接处不能有缝或重叠。
 */
import { describe, it, expect } from '@ohos/hypium';
import { LetterPostingTimeline } from '../../main/ets/models/LetterPostingTimeline';

export default function letterPostingTimelineTest() {
  describe('LetterPostingTimelineTest', () => {
    it('segmentsAreSeamlessAndOrdered', 0, () => {
      // 分段首尾相接（0.32 / 0.95 / 1.40 / 2.42 / 2.82…），没有缝也没有重叠
      expect(LetterPostingTimeline.GATHER_END).assertEqual(LetterPostingTimeline.SLIDE_IN_START);
      expect(LetterPostingTimeline.SLIDE_IN_END).assertEqual(LetterPostingTimeline.FLAP_CLOSE_START);
      expect(LetterPostingTimeline.FLAP_CLOSE_END).assertEqual(1.40);
      expect(LetterPostingTimeline.RISE_START).assertEqual(1.82);
      expect(LetterPostingTimeline.RISE_END).assertEqual(LetterPostingTimeline.INSERT_START);
      expect(LetterPostingTimeline.INSERT_END).assertEqual(LetterPostingTimeline.FLAP_FALL_START);
      expect(LetterPostingTimeline.FLAP_FALL_END).assertEqual(2.90);
      expect(LetterPostingTimeline.TOTAL).assertEqual(2.95);
      // 火漆在封舌合上之后、举起之前
      expect(LetterPostingTimeline.SEAL_START > LetterPostingTimeline.FLAP_CLOSE_END).assertTrue();
      expect(LetterPostingTimeline.SEAL_END < LetterPostingTimeline.RISE_START).assertTrue();
    })

    it('linearClampsOutsideRange', 0, () => {
      // 出区间夹 0/1，中点 0.5
      expect(LetterPostingTimeline.linear(0, 1, 2)).assertEqual(0);
      expect(LetterPostingTimeline.linear(3, 1, 2)).assertEqual(1);
      expect(LetterPostingTimeline.linear(1.5, 1, 2)).assertEqual(0.5);
      // 退化区间（end ≤ start）按端点判
      expect(LetterPostingTimeline.linear(2, 2, 2)).assertEqual(1);
      expect(LetterPostingTimeline.linear(1, 2, 2)).assertEqual(0);
    })

    it('smoothIsSMidpointAndClamped', 0, () => {
      // smoothstep 中点 0.5、两头 0/1，不过冲
      expect(LetterPostingTimeline.smooth(1.5, 1, 2)).assertEqual(0.5);
      expect(LetterPostingTimeline.smooth(1, 1, 2)).assertEqual(0);
      expect(LetterPostingTimeline.smooth(2, 1, 2)).assertEqual(1);
      for (const t of [1.1, 1.3, 1.5, 1.7, 1.9]) {
        const v = LetterPostingTimeline.smooth(t, 1, 2);
        expect(v >= 0 && v <= 1).assertTrue();
      }
    })

    it('envelopeProgressRunsBackwardsThroughMarks', 0, () => {
      // 拆信进度倒着走：1 → 0.55（信纸滑进去）→ 0.12 附近（封舌合上）→ 0。
      // 1.40 起直接归 0：progress ≤ 0.12 时封舌角度 / 信纸位移都已饱和，
      // 视觉上就是封好的样子，跳变不可见（iOS 同款）
      expect(LetterPostingTimeline.envelopeProgress(0)).assertEqual(1);
      expect(LetterPostingTimeline.envelopeProgress(0.2)).assertEqual(1);
      expect(Math.abs(LetterPostingTimeline.envelopeProgress(0.95) - 0.55) < 1e-9).assertTrue();
      const closing = LetterPostingTimeline.envelopeProgress(1.30);
      expect(closing > 0.12 && closing < 0.55).assertTrue();
      expect(LetterPostingTimeline.envelopeProgress(1.40)).assertEqual(0);
      expect(LetterPostingTimeline.envelopeProgress(1.5)).assertEqual(0);
      expect(LetterPostingTimeline.envelopeProgress(LetterPostingTimeline.TOTAL)).assertEqual(0);
    })

    it('envelopeProgressNeverRebounds', 0, () => {
      // 全程单调不回升（R-POST-08 平滑不回弹）
      let prev = LetterPostingTimeline.envelopeProgress(0);
      for (let t = 0.05; t <= LetterPostingTimeline.TOTAL + 0.05; t += 0.05) {
        const v = LetterPostingTimeline.envelopeProgress(t);
        expect(v <= prev + 1e-9).assertTrue();
        prev = v;
      }
    })

    it('envelopeSubCurvesHitTheirMarks', 0, () => {
      // 封舌 0.12 起翻、0.55 翻直；信纸 0.55 起抽、1 抽尽；火漆 0.14 内裂开
      expect(LetterPostingTimeline.envelopeLift(0.12)).assertEqual(0);
      expect(LetterPostingTimeline.envelopeLift(0.55)).assertEqual(1);
      expect(LetterPostingTimeline.envelopeSlide(0.55)).assertEqual(0);
      expect(LetterPostingTimeline.envelopeSlide(1)).assertEqual(1);
      expect(LetterPostingTimeline.envelopeCrack(0)).assertEqual(0);
      expect(LetterPostingTimeline.envelopeCrack(1)).assertEqual(1);
    })
  })
}
