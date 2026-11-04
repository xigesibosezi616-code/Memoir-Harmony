/**
 * 拆信震动的编排（纯逻辑，10_BUILD_MANUAL.md 5.7）：iOS
 * `Views/PostBox/Envelope/LetterOpeningFeel.swift` 的事件表 1:1 转译成鸿蒙
 * `VibratorPatternBuilder`（VibrateFromPattern，API 18+）能吃的形状。
 *
 * 拆信三步各一段编排（R-BOX-05），时间都从这一下点下去算起：
 * - 第 0 步打碎火漆：一下清脆的重击，紧跟三下越来越轻的碎裂，中间夹细砂似的颗粒
 * - 第 1 步封舌翻起：先一点撕开封口的阻力，然后一段持续的低沉震动随翻起速度涨落
 * - 第 2 步信纸抽出 + 摊开：持续的纸张摩擦，中段最强，一路带纤维颗粒；
 *   离开信封轻轻一松，摊开时落在桌上一顿
 *
 * iOS 全局强度曲线（CHHapticParameterCurve）鸿蒙没有，折叠方式同
 * `PostingHapticPattern`：曲线挂到 continuous 的 points（增益 0…1）；
 * 曲线窗口里的 transient 把那一刻的曲线增益乘进 intensity。
 *
 * 强度整形同 5.6：intensity 走伽马提亮（INTENSITY_GAMMA）、sharpness 走
 * 频率下限（FREQUENCY_FLOOR）——iOS 原值 1:1 直译在鸿蒙线性马达上大半
 * 近乎无感（见 PostingHapticPattern 的整形记录）。
 *
 * 事件数硬上限：IPC 层 `MAX_EVENT_SIZE = 16`。第 2 步的纸纤维碎震走预算制
 * （16 − 4 固定事件 = 12），窗口均分采样，同种子序列固定（手感每次一样）。
 *
 * 时间轴踩 `LetterOpeningTimeline`（改一处要三处一起改：动画 / 震动 / 声音）。
 */
import { HapticEventKind, HapticPatternEvent, HapticCurvePoint, Lcg32,
  PostingHapticPattern } from './PostingHapticPattern';
import { LetterOpeningTimeline } from './LetterOpeningTimeline';

/** 折线上的值（points：[秒, 增益] 二元组，分段线性插值） */
function gainAt(points: number[][], timeSec: number): number {
  if (timeSec <= points[0][0]) {
    return points[0][1];
  }
  for (let i = 1; i < points.length; i++) {
    if (timeSec <= points[i][0]) {
      const span = points[i][0] - points[i - 1][0];
      const u = span > 0 ? (timeSec - points[i - 1][0]) / span : 0;
      return points[i - 1][1] + (points[i][1] - points[i - 1][1]) * u;
    }
  }
  return points[points.length - 1][1];
}

/** 钟形增益（iOS LetterHaptics.bell 的一点的值）：两头 floor、中间 1 */
function bellGain(u: number, floor: number): number {
  return floor + (1 - floor) * 4 * u * (1 - u);
}

export class LetterOpeningHapticPattern {
  /** 第 stage 步（0 火漆 / 1 封舌 / 2 信纸）的编排。纯函数：同参数结果逐字段一致 */
  static build(stage: number): HapticPatternEvent[] {
    switch (stage) {
      case 0:
        return LetterOpeningHapticPattern.crackEvents();
      case 1:
        return LetterOpeningHapticPattern.flapEvents();
      case 2:
        return LetterOpeningHapticPattern.slideEvents();
      default:
        return [];
    }
  }

  // —— 第 0 步：火漆裂开（0.36s）。曲线窗口 0.02~0.26s：1.0 → 0.6 → 0 ——

  private static crackEvents(): HapticPatternEvent[] {
    const events: HapticPatternEvent[] = [];
    const curve: number[][] = [[0, 1.0], [0.12, 0.6], [0.24, 0]];
    // 一下清脆的重击，紧跟三下越来越轻的碎裂（iOS 原值 × 曲线增益）
    const taps: number[][] = [
      [0.03, 1.0, 0.85],
      [0.078, 0.55, 0.75],
      [0.122, 0.38, 0.7],
      [0.186, 0.24, 0.6]
    ];
    for (const t of taps) {
      events.push(LetterOpeningHapticPattern.tap(t[0], t[1] * gainAt(curve, t[0] - 0.02), t[2]));
    }
    // 细砂似的颗粒：0.24s 持续段，强度沿同一条曲线衰减（iOS 3 个控制点，
    // SDK 要 4~16 个——沿同一条折线补采样，形状不变）
    events.push(LetterOpeningHapticPattern.hold(0.02, 0.24, 0.22, 0.9, [
      { time: 0, intensity: 1.0, frequency: 0 },
      { time: 60, intensity: 0.8, frequency: 0 },
      { time: 120, intensity: 0.6, frequency: 0 },
      { time: 180, intensity: 0.3, frequency: 0 },
      { time: 240, intensity: 0.0, frequency: 0 }
    ]));
    return events;
  }

  // —— 第 1 步：封舌翻起（1.07s）。曲线窗口 0~1.07s：钟形（floor 0.12）——

  private static flapEvents(): HapticPatternEvent[] {
    const events: HapticPatternEvent[] = [];
    const duration = LetterOpeningTimeline.durationOfStage(1);
    const floor = 0.12;
    // 撕开封口的几下细碎阻力（iOS 原值 × 钟形增益）
    const taps: number[][] = [
      [0.005, 0.22, 0.5],
      [0.035, 0.18, 0.5],
      [0.08, 0.15, 0.5],
      [0.13, 0.12, 0.5],
      [0.51, 0.42, 0.22]
    ];
    for (const t of taps) {
      events.push(LetterOpeningHapticPattern.tap(t[0],
        t[1] * bellGain(t[0] / duration, floor), t[2]));
    }
    // 翻起的一段持续低沉震动，强度跟着翻起速度涨落（钟形曲线挂 points）
    events.push(LetterOpeningHapticPattern.hold(0, duration, 0.42, 0.18,
      LetterOpeningHapticPattern.bell(duration * 1000, floor, 10)));
    return events;
  }

  // —— 第 2 步：信纸抽出（1.17s）+ 摊开（0.55s）——

  private static slideEvents(): HapticPatternEvent[] {
    const events: HapticPatternEvent[] = [];
    const slide = LetterOpeningTimeline.durationOfStage(2);
    const floor = 0.15;
    // 持续的纸张摩擦，中段最强（钟形曲线挂 points）
    const holdDur = slide - 0.04;
    events.push(LetterOpeningHapticPattern.hold(0.02, holdDur, 0.5, 0.32,
      LetterOpeningHapticPattern.bell(holdDur * 1000, floor, 12)));
    // 纸纤维碎震：iOS grain 循环（固定种子 'MEMO' 截 32 位）。事件预算 =
    // MAX_EVENTS(16) 减固定事件（摩擦 1 + 离信一松 1 + 摊开轻铺 1 + 落桌一顿 1）：
    // 窗口 [0.07, slide-0.1] 均分、段内由确定性 LCG 抖动；
    // 强度已乘钟形增益（iOS 是全局曲线压着，这里折叠）
    const rng = new Lcg32(0x4D454D4F);
    const grainStart = 0.07;
    const grainEnd = slide - 0.1;
    const budget = 12;
    const segWidth = (grainEnd - grainStart) / budget;
    for (let i = 0; i < budget; i++) {
      const jitter = rng.next();
      const grainSec = grainStart + segWidth * i + jitter * segWidth;
      const speed = 4 * (grainSec / slide) * (1 - grainSec / slide);
      const base = 0.08 + 0.16 * speed * (0.6 + 0.4 * jitter);
      events.push(LetterOpeningHapticPattern.tap(grainSec,
        base * bellGain((grainSec - 0.02) / holdDur, floor), 0.4 + 0.2 * jitter));
    }
    // 离开信封轻轻一松（iOS 0.32 × 曲线末端增益）
    events.push(LetterOpeningHapticPattern.tap(slide - 0.05,
      0.32 * bellGain((slide - 0.05 - 0.02) / holdDur, floor), 0.4));
    // 摊开时：轻轻铺开的一小段 + 落在桌上一顿（曲线窗口外，原值不折）
    events.push(LetterOpeningHapticPattern.hold(1.55, 0.12, 0.18, 0.1, []));
    events.push(LetterOpeningHapticPattern.tap(1.62, 0.5, 0.15));
    return events;
  }

  /** 点打：秒 / intensity、sharpness 都是 0…1，走 5.6 强度整形换算成 0…100 整数 */
  private static tap(atSec: number, intensity: number, sharpness: number): HapticPatternEvent {
    return {
      kind: HapticEventKind.TRANSIENT,
      time: Math.round(atSec * 1000),
      duration: 0,
      intensity: PostingHapticPattern.shapeIntensity(intensity),
      frequency: PostingHapticPattern.shapeFrequency(sharpness),
      points: []
    };
  }

  /** 持续段：秒 / intensity、sharpness 同上（同走整形）；points 为空数组 = 不带曲线 */
  private static hold(atSec: number, durationSec: number, intensity: number, sharpness: number,
    points: HapticCurvePoint[]): HapticPatternEvent {
    return {
      kind: HapticEventKind.CONTINUOUS,
      time: Math.round(atSec * 1000),
      duration: Math.round(durationSec * 1000),
      intensity: PostingHapticPattern.shapeIntensity(intensity),
      frequency: PostingHapticPattern.shapeFrequency(sharpness),
      points: points
    };
  }

  /** 钟形曲线（iOS LetterHaptics.bell）：两头 floor、中间 1 —— 跟动画速度走 */
  private static bell(durationMs: number, floor: number, samples: number): HapticCurvePoint[] {
    const points: HapticCurvePoint[] = [];
    for (let i = 0; i <= samples; i++) {
      const u = i / samples;
      points.push({
        time: Math.round(u * durationMs),
        intensity: floor + (1 - floor) * 4 * u * (1 - u),
        frequency: 0
      });
    }
    return points;
  }
}
