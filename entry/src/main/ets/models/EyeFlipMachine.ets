/**
 * 眼动翻页状态机（纯逻辑，可单测）。华为阅读同款思路：标定正常阅读时的
 * 头部姿态基线，之后「抬头」偏离基线够多、够久 → 触发一次前向翻页。
 *
 * - 标定：前 `EYE_CALIBRATION_SAMPLES` 个有效样本取中位数为基线
 *   （中位数抗单帧野值；样本不足时绝不触发）
 * - 触发：pitch − 基线 ≥ `EYE_RAISE_THRESHOLD_DEG` 且持续
 *   `EYE_RAISE_HOLD_MS` → 触发一次（防瞬时晃动误翻）
 * - 迟滞：偏离回落到阈值 − `EYE_RAISE_HYSTERESIS_DEG` 以内才算「抬头
 *   结束」，边界抖动不重置持续计时；触发后必须先回落到迟滞带以内
 *   才重新武装（一直抬着头不会连环翻页，想翻下一页要先低头再抬）
 * - 冷却：触发后 `EYE_FLIP_COOLDOWN_MS` 内不响应（翻页动画 ~0.6s，
 *   冷却盖过它）
 * - 无脸 / 暂停：拿不到 pitch（没脸 / 检测失败 / 页面忙）不推进任何
 *   计时，持续计时清零但基线保留
 *
 * 输入 pitch 为 faceDetector Face.pose.pitch（度）。视图层决定何时喂
 * （页面忙时喂 pause()），机器本身不管翻页怎么画。
 */
import { faceDetector } from '@kit.CoreVisionKit';

/** 标定样本数（~350ms 一帧 ≈ 2s 出基线） */
export const EYE_CALIBRATION_SAMPLES: number = 6;
/** 抬头触发阈值：pitch 相对基线抬高这么多度（华为同款量级，实测可调） */
export const EYE_RAISE_THRESHOLD_DEG: number = 9;
/** 抬头迟滞带：回落到阈值以下这么多度才算抬头结束 */
export const EYE_RAISE_HYSTERESIS_DEG: number = 5;
/** 抬头需持续的时长（ms）：防低头瞄一眼 / 打哈欠误翻 */
export const EYE_RAISE_HOLD_MS: number = 500;
/** 触发后冷却（ms）：盖过翻页动画，也吸收触发后的残余抬头 */
export const EYE_FLIP_COOLDOWN_MS: number = 1200;

/** 机器所处阶段（UI 可据此换提示文案） */
export enum EyeFlipPhase {
  /** 攒标定样本中 */
  Calibrating = 'calibrating',
  /** 基线就绪，盯抬头 */
  Tracking = 'tracking'
}

export class EyeFlipMachine {
  /** 阅读姿态基线（度）；undefined = 还在标定 */
  private baselineDeg: number | undefined = undefined;
  /** 标定攒的样本 */
  private calibrationSamples: number[] = [];
  /** 本轮抬头从何时开始（ms；undefined = 当前没在抬头） */
  private holdSinceMs: number | undefined = undefined;
  /** 冷却截止（ms） */
  private cooldownUntilMs: number = 0;
  /** 触发后是否已重新武装（要先回落到迟滞带以内） */
  private rearmed: boolean = true;

  get phase(): EyeFlipPhase {
    return this.baselineDeg === undefined ? EyeFlipPhase.Calibrating : EyeFlipPhase.Tracking;
  }

  /** 只读基线（诊断日志用） */
  get baseline(): number | undefined {
    return this.baselineDeg;
  }

  /** 清零重来（关眼动 / 换页面重建时）：回到标定态 */
  reset(): void {
    this.baselineDeg = undefined;
    this.calibrationSamples = [];
    this.holdSinceMs = undefined;
    this.cooldownUntilMs = 0;
    this.rearmed = true;
  }

  /** 页面忙 / 不该翻的时机：清掉抬头持续计时，基线和冷却保留 */
  pause(): void {
    this.holdSinceMs = undefined;
  }

  /**
   * 喂一帧检测结果。
   * @param pitchDeg 本帧最大脸的 pitch（度）；undefined = 没检测到脸
   * @param nowMs 当前时间（ms）
   * @returns true = 该翻页了（每真抬头只返回一次）
   */
  feed(pitchDeg: number | undefined, nowMs: number): boolean {
    if (pitchDeg === undefined) {
      // 没脸：不推进标定也不算抬头，持续计时作废
      this.holdSinceMs = undefined;
      return false;
    }
    if (this.baselineDeg === undefined) {
      this.calibrationSamples.push(pitchDeg);
      if (this.calibrationSamples.length >= EYE_CALIBRATION_SAMPLES) {
        this.baselineDeg = EyeFlipMachine.medianOf(this.calibrationSamples);
      }
      return false;
    }
    if (nowMs < this.cooldownUntilMs) {
      this.holdSinceMs = undefined;
      return false;
    }
    const delta = pitchDeg - this.baselineDeg;
    if (delta < EYE_RAISE_THRESHOLD_DEG - EYE_RAISE_HYSTERESIS_DEG) {
      // 明确低头了：抬头计时作废；触发过的从这里重新武装
      this.holdSinceMs = undefined;
      this.rearmed = true;
      return false;
    }
    if (!this.rearmed) {
      return false; // 上次触发后头一直没低回去：不连翻
    }
    if (delta < EYE_RAISE_THRESHOLD_DEG) {
      return false; // 迟滞带里（阈值下方 HYSTERESIS 度内）：维持现状
    }
    if (this.holdSinceMs === undefined) {
      this.holdSinceMs = nowMs;
      return false;
    }
    if (nowMs - this.holdSinceMs < EYE_RAISE_HOLD_MS) {
      return false;
    }
    this.holdSinceMs = undefined;
    this.cooldownUntilMs = nowMs + EYE_FLIP_COOLDOWN_MS;
    this.rearmed = false;
    return true;
  }

  /** 中位数（偶数个取中间两数均值）；空数组返回 0（调用方保证非空） */
  private static medianOf(values: number[]): number {
    if (values.length === 0) {
      return 0;
    }
    const sorted = values.slice().sort((a: number, b: number): number => a - b);
    const mid = Math.floor(sorted.length / 2);
    if (sorted.length % 2 === 1) {
      return sorted[mid];
    }
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

/** 从一帧检测结果里取「正脸主力」的 pitch：取面积最大的脸 */
export function pitchOfLargestFace(faces: Array<faceDetector.Face>): number | undefined {
  let best: faceDetector.Face | undefined = undefined;
  let bestArea = 0;
  for (const face of faces) {
    const area = face.rect.width * face.rect.height;
    if (best === undefined || area > bestArea) {
      best = face;
      bestArea = area;
    }
  }
  return best !== undefined ? best.pose.pitch : undefined;
}
