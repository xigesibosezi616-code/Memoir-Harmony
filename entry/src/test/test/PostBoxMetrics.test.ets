/**
 * 邮筒页版式度量单测（PostBoxMetrics）。
 * 锚点：iOS iPhone 15 Pro（852pt 窗高、叠纸 188=22%、34/40/24）、
 * Mate X6 折叠态（2440px/3.1154=782.65vp、安全区 39.2/28）、
 * 展开态（≈731vp）、横屏矮窗（≈347vp）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { PostBoxMetrics, POSTBOX_SPACING_VP } from '../../main/ets/views/postbox/PostBoxMetrics';

export default function postBoxMetricsTest() {
  describe('PostBoxMetricsTest', () => {
    it('tallPhoneMatchesIOSAbsoluteSizes', 0, () => {
      // 高窗：叠纸封顶 188，头行/行高/渐隐逐字等于 iOS OutgoingPile
      const m = PostBoxMetrics.compute(900, 40, 30);
      expect(m.pileHeightVp).assertEqual(188);
      expect(m.pileHeaderHeightVp).assertEqual(34);
      expect(m.pileRowHeightVp).assertEqual(40);
      expect(m.pileFadeHeightVp).assertEqual(24);
    })

    it('mateX6FoldedAnchor', 0, () => {
      // Mate X6 折叠态：叠纸 172.18（=782.65×22%），顶 39.2+70、底 28+102
      const m = PostBoxMetrics.compute(782.65, 39.2, 28);
      expect(m.topOffsetVp).assertEqual(109.2);
      expect(m.bottomOffsetVp).assertEqual(130);
      expect(Math.abs(m.pileHeightVp - 172.183) < 0.001).assertTrue();
      expect(m.statusMinHeightVp).assertEqual(28);
      // 邮筒拿走剩余全部且不为负
      expect(Math.abs(m.stageHeightVp - 315.267) < 0.001).assertTrue();
      expect(m.contentMaxWidthVp).assertEqual(430);
    })

    it('unfoldedKeepsProportion', 0, () => {
      // 展开态（≈731vp）：叠纸跟着窗高等比，仍 ≥ iOS 下限 132
      const m = PostBoxMetrics.compute(731, 12, 28);
      expect(Math.abs(m.pileHeightVp - 160.82) < 0.001).assertTrue();
      expect(m.stageHeightVp > 0).assertTrue();
    })

    it('pileClampedToIOSBounds', 0, () => {
      // 超高窗不放大（iOS 绝对值封顶），矮窗不小于 132
      expect(PostBoxMetrics.compute(2000, 40, 30).pileHeightVp).assertEqual(188);
      expect(PostBoxMetrics.compute(347, 0, 0).pileHeightVp).assertEqual(132);
    })

    it('compactTierForShortWindows', 0, () => {
      // 横屏矮窗（<520）：不留导航区、底部收紧、状态行更矮
      const m = PostBoxMetrics.compute(347, 0, 0);
      expect(m.topOffsetVp).assertEqual(8);
      expect(m.bottomOffsetVp).assertEqual(56);
      expect(m.statusMinHeightVp).assertEqual(26);
      expect(m.stageHeightVp).assertEqual(97);
    })

    it('stageNeverNegative', 0, () => {
      // 极矮窗口 stage 夹 0（叠纸仍在，只是插画收没），不出现负 layoutWeight
      const m = PostBoxMetrics.compute(200, 0, 0);
      expect(m.stageHeightVp).assertEqual(0);
    })

    it('pileIdentityHeaderPlusRowsPlusBacking', 0, () => {
      // 不变式：header + row×3.5 + 14（垫纸露边）= 整叠高，任意窗高成立
      for (const h of [347, 500, 600, 731, 782.65, 852, 900, 1200, 2000]) {
        const m = PostBoxMetrics.compute(h, 39.2, 28);
        const rebuilt = m.pileHeaderHeightVp + m.pileRowHeightVp * 3.5 + 14;
        expect(Math.abs(rebuilt - m.pileHeightVp) < 0.01).assertTrue();
      }
    })

    it('stageIdentitySpendsWholeWindow', 0, () => {
      // 不变式：顶+插画+间距×2+状态行+叠纸+底 = 窗高（stage>0 时）
      const h = 782.65;
      const m = PostBoxMetrics.compute(h, 39.2, 28);
      const spent = m.topOffsetVp + m.stageHeightVp + POSTBOX_SPACING_VP * 2
        + m.statusMinHeightVp + m.pileHeightVp + m.bottomOffsetVp;
      expect(Math.abs(spent - h) < 0.01).assertTrue();
    })
  })
}
