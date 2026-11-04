/**
 * 拆信时间轴单测（LetterOpeningTimeline）。
 * 锚点：iOS `Views/PostBox/Envelope/LetterOpeningFeel.swift` 的常量段逐字一致。
 */
import { describe, it, expect } from '@ohos/hypium';
import { LetterOpeningTimeline } from '../../main/ets/models/LetterOpeningTimeline';

export default function letterOpeningTimelineTest() {
  describe('LetterOpeningTimelineTest', () => {
    it('constantsMatchIos', 0, () => {
      expect(LetterOpeningTimeline.ANIMATION_DURATION).assertEqual(2.6);
      expect(LetterOpeningTimeline.STAGE_COUNT).assertEqual(3);
      expect(LetterOpeningTimeline.STAGE_TARGETS.length).assertEqual(3);
      expect(LetterOpeningTimeline.STAGE_TARGETS[0]).assertEqual(0.14);
      expect(LetterOpeningTimeline.STAGE_TARGETS[1]).assertEqual(0.55);
      expect(LetterOpeningTimeline.STAGE_TARGETS[2]).assertEqual(1.0);
      expect(LetterOpeningTimeline.UNFOLD_DURATION).assertEqual(0.55);
    })

    it('stageDurationsSumToAnimationDuration', 0, () => {
      // 三步各占整条拆信的 progress 份额：0.36 / 1.07 / 1.17（iOS 文档表）。
      // 浮点运算顺序不同会有尾差，按容差比（CoverEdit 同款）
      expect(Math.abs(LetterOpeningTimeline.durationOfStage(0) - 0.364) < 1e-9).assertTrue();
      expect(Math.abs(LetterOpeningTimeline.durationOfStage(1) - 1.066) < 1e-9).assertTrue();
      expect(Math.abs(LetterOpeningTimeline.durationOfStage(2) - 1.17) < 1e-9).assertTrue();
      // 加起来 = 一口气拆完的时长
      let total = 0;
      for (let stage = 0; stage < LetterOpeningTimeline.STAGE_COUNT; stage++) {
        total += LetterOpeningTimeline.durationOfStage(stage);
      }
      expect(Math.abs(total - LetterOpeningTimeline.ANIMATION_DURATION) < 1e-9).assertTrue();
    })

    it('invalidStageGivesZero', 0, () => {
      expect(LetterOpeningTimeline.durationOfStage(-1)).assertEqual(0);
      expect(LetterOpeningTimeline.durationOfStage(3)).assertEqual(0);
    })
  })
}
