/**
 * 眼动翻页状态机单测（10_BUILD_MANUAL.md 3.5 眼动翻页）。
 * 不变量：
 * - 标定没满 EYE_CALIBRATION_SAMPLES 个样本绝不触发（样本再多也不触发）
 * - 基线 = 样本中位数（抗野值：一半样本被污染仍稳）
 * - 抬头 ≥ 阈值且持续够 EYE_RAISE_HOLD_MS 才触发一次；
 *   迟滞带（阈值下方 EYE_RAISE_HYSTERESIS_DEG 内）不重置持续计时
 * - 触发后：冷却期内不响应；头不低回迟滞带以内不再触发（不连翻）
 * - 无脸 / pause()：持续计时清零，基线保留
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  EYE_CALIBRATION_SAMPLES,
  EYE_FLIP_COOLDOWN_MS,
  EYE_RAISE_HYSTERESIS_DEG,
  EYE_RAISE_HOLD_MS,
  EYE_RAISE_THRESHOLD_DEG,
  EyeFlipMachine,
  EyeFlipPhase,
  pitchOfLargestFace
} from '../../main/ets/models/EyeFlipMachine';
import { faceDetector } from '@kit.CoreVisionKit';

/** 造一帧检测结果里的 Face（只填用到的字段，其余给 0 / 空数组） */
function makeFace(width: number, height: number, pitch: number): faceDetector.Face {
  return {
    probability: 1,
    pose: { yaw: 0, pitch: pitch, roll: 0 },
    rect: { left: 0, top: 0, width: width, height: height },
    points: []
  };
}

export default function eyeFlipMachineTest() {
  describe('EyeFlipMachine', () => {
    it('no_trigger_before_calibration_completes', 0, () => {
      const m = new EyeFlipMachine();
      // 样本没攒够：哪怕抬头抬得离谱也不触发
      for (let i = 0; i < EYE_CALIBRATION_SAMPLES - 1; i++) {
        expect(m.feed(80, 1000 + i * 350)).assertFalse();
      }
      expect(m.phase).assertEqual(EyeFlipPhase.Calibrating);
      expect(m.baseline).assertUndefined();
    });

    it('baseline_is_median_of_samples', 0, () => {
      const m = new EyeFlipMachine();
      // 一半样本被污染（10,200,10,11,12,13）→ 中位数 11.5，不被 200 带偏
      const samples = [10, 200, 10, 11, 12, 13];
      for (let i = 0; i < samples.length; i++) {
        m.feed(samples[i], 1000 + i * 350);
      }
      expect(m.phase).assertEqual(EyeFlipPhase.Tracking);
      expect(m.baseline !== undefined && Math.abs(m.baseline - 11.5) < 1e-9).assertTrue();
    });

    it('raise_above_threshold_for_hold_ms_triggers_once', 0, () => {
      const m = new EyeFlipMachine();
      for (let i = 0; i < EYE_CALIBRATION_SAMPLES; i++) {
        m.feed(10, i * 350);
      }
      const raised = 10 + EYE_RAISE_THRESHOLD_DEG + 0.5;
      // 持续抬头：0ms 起计，HOLD-1ms 那帧还不满，HOLD ms 帧触发
      expect(m.feed(raised, 10_000)).assertFalse();
      expect(m.feed(raised, 10_000 + EYE_RAISE_HOLD_MS - 1)).assertFalse();
      expect(m.feed(raised, 10_000 + EYE_RAISE_HOLD_MS)).assertTrue();
      // 触发后再喂同样抬头：不连翻（没低过头）
      expect(m.feed(raised, 10_000 + EYE_RAISE_HOLD_MS + 400)).assertFalse();
    });

    it('brief_raise_below_hold_does_not_trigger', 0, () => {
      const m = new EyeFlipMachine();
      for (let i = 0; i < EYE_CALIBRATION_SAMPLES; i++) {
        m.feed(10, i * 350);
      }
      const raised = 10 + EYE_RAISE_THRESHOLD_DEG + 2;
      // 只抬了 350ms 就低头：持续计时作废
      expect(m.feed(raised, 10_000)).assertFalse();
      expect(m.feed(10, 10_350)).assertFalse();
      expect(m.feed(raised, 10_700)).assertFalse();
      // 重新起计：满 HOLD ms 才触发
      expect(m.feed(raised, 10_700 + EYE_RAISE_HOLD_MS - 1)).assertFalse();
      expect(m.feed(raised, 10_700 + EYE_RAISE_HOLD_MS)).assertTrue();
    });

    it('hysteresis_band_keeps_hold_alive', 0, () => {
      const m = new EyeFlipMachine();
      for (let i = 0; i < EYE_CALIBRATION_SAMPLES; i++) {
        m.feed(10, i * 350);
      }
      // 抬头后掉进迟滞带（阈值下方 HYSTERESIS 度内）：持续计时不清零，照常触发
      const raised = 10 + EYE_RAISE_THRESHOLD_DEG + 1;
      const band = 10 + EYE_RAISE_THRESHOLD_DEG - EYE_RAISE_HYSTERESIS_DEG + 1;
      expect(m.feed(raised, 10_000)).assertFalse();
      expect(m.feed(band, 10_350)).assertFalse();
      // 带内那帧没重置计时：距起计差 50ms 还不满，满时长那一帧才触发
      expect(m.feed(raised, 10_000 + EYE_RAISE_HOLD_MS - 50)).assertFalse();
      expect(m.feed(raised, 10_000 + EYE_RAISE_HOLD_MS)).assertTrue();
    });

    it('below_threshold_persistently_never_triggers', 0, () => {
      const m = new EyeFlipMachine();
      for (let i = 0; i < EYE_CALIBRATION_SAMPLES; i++) {
        m.feed(10, i * 350);
      }
      // 差 1° 不够阈值：抬多久都不翻
      const almost = 10 + EYE_RAISE_THRESHOLD_DEG - 1;
      for (let t = 0; t <= 5000; t += 350) {
        expect(m.feed(almost, 10_000 + t)).assertFalse();
      }
    });

    it('no_face_resets_hold_but_keeps_baseline', 0, () => {
      const m = new EyeFlipMachine();
      for (let i = 0; i < EYE_CALIBRATION_SAMPLES; i++) {
        m.feed(10, i * 350);
      }
      const raised = 10 + EYE_RAISE_THRESHOLD_DEG + 1;
      expect(m.feed(raised, 10_000)).assertFalse();
      expect(m.feed(undefined, 10_350)).assertFalse(); // 丢脸：计时作废
      expect(m.feed(raised, 10_700)).assertFalse();
      // 基线还在，重新起计满 600ms 触发（不再要 6 个样本）
      expect(m.feed(raised, 10_700 + EYE_RAISE_HOLD_MS)).assertTrue();
      expect(m.phase).assertEqual(EyeFlipPhase.Tracking);
    });

    it('cooldown_blocks_immediate_retrigger', 0, () => {
      const m = new EyeFlipMachine();
      for (let i = 0; i < EYE_CALIBRATION_SAMPLES; i++) {
        m.feed(10, i * 350);
      }
      const raised = 10 + EYE_RAISE_THRESHOLD_DEG + 1;
      expect(m.feed(raised, 10_000)).assertFalse();
      expect(m.feed(raised, 10_000 + EYE_RAISE_HOLD_MS)).assertTrue();
      // 冷却期内的样本只被吞掉：期间低头不重新武装，抬头起计也不算
      const low = 10 + EYE_RAISE_THRESHOLD_DEG - EYE_RAISE_HYSTERESIS_DEG - 1;
      expect(m.feed(low, 11_000)).assertFalse();
      expect(m.feed(raised, 11_300)).assertFalse();
      expect(m.feed(raised, 11_900)).assertFalse();
      // 冷却过后（触发 + 1200ms）：低头重新武装 → 抬头满持续时长触发
      expect(m.feed(low, 12_000)).assertFalse();
      expect(m.feed(raised, 12_300)).assertFalse();
      expect(m.feed(raised, 12_300 + EYE_RAISE_HOLD_MS)).assertTrue();
    });

    it('must_dip_below_hysteresis_before_retrigger', 0, () => {
      const m = new EyeFlipMachine();
      for (let i = 0; i < EYE_CALIBRATION_SAMPLES; i++) {
        m.feed(10, i * 350);
      }
      const raised = 10 + EYE_RAISE_THRESHOLD_DEG + 1;
      expect(m.feed(raised, 10_000)).assertFalse();
      expect(m.feed(raised, 10_000 + EYE_RAISE_HOLD_MS)).assertTrue();
      // 一直抬着头：冷却过了也不连翻（rearmed 还没回来）
      const far = 10_000 + EYE_RAISE_HOLD_MS + EYE_FLIP_COOLDOWN_MS + 5_000;
      expect(m.feed(raised, far)).assertFalse();
      expect(m.feed(raised, far + EYE_RAISE_HOLD_MS * 3)).assertFalse();
      // 低头到迟滞带以下 → 重新武装 → 再抬头满时长触发
      const low = 10 + EYE_RAISE_THRESHOLD_DEG - EYE_RAISE_HYSTERESIS_DEG - 1;
      expect(m.feed(low, far + 10_000)).assertFalse();
      expect(m.feed(raised, far + 20_000)).assertFalse();
      expect(m.feed(raised, far + 20_000 + EYE_RAISE_HOLD_MS)).assertTrue();
    });

    it('pause_clears_hold_and_reset_recalibrates', 0, () => {
      const m = new EyeFlipMachine();
      for (let i = 0; i < EYE_CALIBRATION_SAMPLES; i++) {
        m.feed(10, i * 350);
      }
      const raised = 10 + EYE_RAISE_THRESHOLD_DEG + 1;
      expect(m.feed(raised, 10_000)).assertFalse();
      m.pause(); // 页面忙（翻页动画中）
      expect(m.feed(raised, 10_000 + EYE_RAISE_HOLD_MS)).assertFalse(); // 计时被清：重新起计
      expect(m.feed(raised, 10_000 + EYE_RAISE_HOLD_MS * 2 + 350)).assertTrue();
      // reset：回标定态
      m.reset();
      expect(m.phase).assertEqual(EyeFlipPhase.Calibrating);
      expect(m.feed(raised, 30_000)).assertFalse();
    });

    it('pitch_of_largest_face_picks_biggest_rect', 0, () => {
      const faces: Array<faceDetector.Face> = [
        makeFace(100, 120, 5),
        makeFace(300, 320, -7),
        makeFace(150, 150, 9)
      ];
      expect(pitchOfLargestFace(faces) === -7).assertTrue();
      expect(pitchOfLargestFace([]) === undefined).assertTrue();
    });
  });
}
