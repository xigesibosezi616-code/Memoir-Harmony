/**
 * 投信动画几何单测（LetterPostingFlightGeometry）。
 * 锚点：iOS `Posting/PostBoxPage.swift` 的 slotInImage（0.317/0.19/0.367/0.024）、
 * 邮筒线稿 588×1410、信封 1.56；关键帧（t=0 原地、举起、推入、放完）逐个钉死。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  PostingRun,
  fitRectInRect,
  slotRectOf,
  computeFlightFrame,
  MAILBOX_IMAGE_ASPECT,
  ENVELOPE_ASPECT,
  RectF
} from '../../main/ets/models/LetterPostingFlightGeometry';
import { LetterPostingTimeline } from '../../main/ets/models/LetterPostingTimeline';

/** 固定测试几何：叠纸在左下、口子在右上（数值任意，只要求帧间关系稳定） */
const PILE: RectF = { x: 28, y: 500, width: 300, height: 188 };
const SLOT: RectF = { x: 100, y: 300, width: 120, height: 8 };

function frameAt(t: number, hasSeal: boolean) {
  return computeFlightFrame(t, PILE, SLOT, hasSeal);
}

export default function letterPostingFlightGeometryTest() {
  describe('LetterPostingFlightGeometryTest', () => {
    it('imageAndEnvelopeAspectsMatchIOS', 0, () => {
      // 邮筒线稿 588×1410、信封 1.56（iOS SealedEnvelope.aspect 同值）
      expect(Math.abs(MAILBOX_IMAGE_ASPECT - 588 / 1410) < 1e-12).assertTrue();
      expect(ENVELOPE_ASPECT).assertEqual(1.56);
    })

    it('fitRectInRectContainsAndCenters', 0, () => {
      // 高框：按宽 contain、垂直居中
      const tall = fitRectInRect({ x: 0, y: 0, width: 100, height: 200 }, 1);
      expect(tall.width).assertEqual(100);
      expect(tall.height).assertEqual(100);
      expect(tall.y).assertEqual(50);
      expect(tall.x).assertEqual(0);
      // 宽框：按高 contain、水平居中
      const wide = fitRectInRect({ x: 10, y: 20, width: 200, height: 100 }, 1);
      expect(wide.height).assertEqual(100);
      expect(wide.width).assertEqual(100);
      expect(wide.x).assertEqual(60);
      expect(wide.y).assertEqual(20);
      // 退化：零框 / 非法比例出零矩形，不抛
      const zero = fitRectInRect({ x: 5, y: 6, width: 0, height: 0 }, 1);
      expect(zero.width).assertEqual(0);
      expect(zero.height).assertEqual(0);
      expect(zero.x).assertEqual(5);
    })

    it('slotRectOfMapsProportionsOntoDrawnMailbox', 0, () => {
      // 口子四个比例值原样落到绘制矩形上（0.317/0.19/0.367/0.024）
      const drawn: RectF = { x: 10, y: 20, width: 100, height: 300 };
      const slot = slotRectOf(drawn);
      expect(Math.abs(slot.x - (10 + 31.7)) < 1e-9).assertTrue();
      expect(Math.abs(slot.y - (20 + 57)) < 1e-9).assertTrue();
      expect(Math.abs(slot.width - 36.7) < 1e-9).assertTrue();
      expect(Math.abs(slot.height - 7.2) < 1e-9).assertTrue();
    })

    it('sealMarkOfTakesFirstLetterOrFallsBack', 0, () => {
      // 印面 = 名字首字，拉丁转大写；空 / 符号 / 数字开头压「素」
      expect(PostingRun.sealMarkOf('青鸟')).assertEqual('青');
      expect(PostingRun.sealMarkOf('gavin')).assertEqual('G');
      expect(PostingRun.sealMarkOf('álom')).assertEqual('Á');
      expect(PostingRun.sealMarkOf('')).assertEqual('素');
      expect(PostingRun.sealMarkOf(undefined)).assertEqual('素');
      expect(PostingRun.sealMarkOf('   ')).assertEqual('素');
      expect(PostingRun.sealMarkOf('🎉hi')).assertEqual('素');
      expect(PostingRun.sealMarkOf('3st')).assertEqual('素');
      expect(PostingRun.sealMarkOf('·点')).assertEqual('素');
    })

    it('frameAtZeroSitsOnThePile', 0, () => {
      // t=0：信封还是叠纸那副身板（宽 min(叠宽×0.6, 220)），透明 0；
      // 那叠日记原样、那页信纸还没显形、口子关着
      const f = frameAt(0, false);
      expect(f.envWidth).assertEqual(180);
      expect(f.envOpacity).assertEqual(0);
      expect(f.pileScaleX).assertEqual(1);
      expect(f.pileScaleY).assertEqual(1);
      expect(f.pileOffsetX).assertEqual(0);
      expect(f.pileOffsetY).assertEqual(0);
      expect(f.pileOpacity).assertEqual(1);
      expect(f.sheetVisible).assertTrue();
      expect(f.sheetX).assertEqual(PILE.x);
      expect(f.sheetY).assertEqual(PILE.y);
      expect(f.sheetWidth).assertEqual(PILE.width);
      expect(f.sheetHeight).assertEqual(PILE.height);
      expect(f.gapVisible).assertFalse();
      expect(f.sealPress).assertEqual(0);
      expect(f.envTiltDeg).assertEqual(0);
      // 信封横向始终对齐叠纸中线
      expect(Math.abs(f.envX + f.envWidth / 2 - (PILE.x + PILE.width / 2)) < 0.001).assertTrue();
    })

    it('frameAtRiseEndHoversUnderTheSlotTilted', 0, () => {
      // 举到位（2.42）：宽收到口子的 0.7、横向对准口子中线、倾角 25°
      const f = frameAt(LetterPostingTimeline.RISE_END, false);
      expect(Math.abs(f.envWidth - 84) < 1e-9).assertTrue();
      expect(Math.abs(f.envX + f.envWidth / 2 - (SLOT.x + SLOT.width / 2)) < 1e-9).assertTrue();
      expect(f.envTiltDeg).assertEqual(25);
      expect(f.envOpacity).assertEqual(1);
      expect(f.sheetVisible).assertFalse();
      expect(f.envProgress).assertEqual(0);
    })

    it('frameAtInsertEndPushesIntoTheSlot', 0, () => {
      // 推到底（2.82）：中心进到口子里、倾角 25+30；翻板被推开露出黑；
      // 推到一半还有一截在口子底下看得见，推到底整封进了口子（遮罩全裁掉）
      const mid = frameAt(2.6, false);
      expect(mid.gapVisible).assertTrue();
      expect(mid.envY < SLOT.y + SLOT.height).assertTrue();
      expect(mid.envY + mid.envHeight > SLOT.y + SLOT.height).assertTrue();
      const f = frameAt(LetterPostingTimeline.INSERT_END, false);
      expect(f.envTiltDeg).assertEqual(55);
      expect(f.gapVisible).assertTrue();
      expect(f.gapHeight > 0 && f.gapHeight <= SLOT.height).assertTrue();
      expect(f.gapX).assertEqual(SLOT.x);
      // 整封都进了口子上面（信封头越过口子下沿，底下看不见了）
      expect(f.envY + f.envHeight < SLOT.y + SLOT.height).assertTrue();
    })

    it('frameAtTotalRevealsAndSettles', 0, () => {
      // 放完（2.95）：口子合上、下面那块淡出到头、略大落定归 1
      const f = frameAt(LetterPostingTimeline.TOTAL, false);
      expect(f.gapVisible).assertFalse();
      expect(f.revealOpacity).assertEqual(1);
      expect(f.revealScale).assertEqual(1);
      expect(f.envProgress).assertEqual(0);
      expect(f.sheetVisible).assertFalse();
      // 邮戳只在翻板落回之后才亮：2.90 半道上在 0/1 之间
      const mid = frameAt(2.90, false);
      expect(mid.revealOpacity > 0 && mid.revealOpacity < 1).assertTrue();
      expect(mid.revealScale > 1 && mid.revealScale <= 1.05).assertTrue();
    })

    it('sealPressOnlyForSealedRuns', 0, () => {
      // 火漆只会员盖：sealed 从 1.46 起压、1.76 压实；普通封口恒 0
      const sealed = frameAt(LetterPostingTimeline.SEAL_END, true);
      expect(sealed.sealPress).assertEqual(1);
      const before = frameAt(LetterPostingTimeline.SEAL_START, true);
      expect(before.sealPress).assertEqual(0);
      const pressing = frameAt(1.5, true);
      expect(pressing.sealPress > 0 && pressing.sealPress < 1).assertTrue();
      const plain = frameAt(LetterPostingTimeline.SEAL_END, false);
      expect(plain.sealPress).assertEqual(0);
    })

    it('tiltAndRevealNeverGoBackwards', 0, () => {
      // 全程单调：倾角不回正、邮戳不缩回去（R-POST-08 平滑不回弹）
      let prevTilt = -1;
      let prevReveal = -1;
      for (let t = 0; t <= LetterPostingTimeline.TOTAL + 0.001; t += 0.05) {
        const f = frameAt(t, false);
        expect(f.envTiltDeg >= prevTilt - 1e-9).assertTrue();
        expect(f.revealOpacity >= prevReveal - 1e-9).assertTrue();
        prevTilt = f.envTiltDeg;
        prevReveal = f.revealOpacity;
      }
    })

    it('gapOpensOnlyWhileInserting', 0, () => {
      // 口子只在推入那一段被推开：举起前关着、推入中开着、放完合上
      expect(frameAt(2.0, false).gapVisible).assertFalse();
      expect(frameAt(2.5, false).gapVisible).assertTrue();
      expect(frameAt(LetterPostingTimeline.TOTAL, false).gapVisible).assertFalse();
    })
  })
}
