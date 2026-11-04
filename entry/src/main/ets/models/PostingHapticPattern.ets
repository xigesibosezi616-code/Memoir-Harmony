/**
 * 投信震动的编排（纯逻辑）：iOS `Posting/LetterPostingFeel.swift` 的事件表
 * 1:1 转译成鸿蒙 `VibratorPatternBuilder`（VibrateFromPattern，API 18+）能吃的形状。
 *
 * iOS 用 CoreHaptics：transient（点打）+ continuous（持续段）+ **全局**强度曲线
 * （CHHapticParameterCurve，乘在窗口里所有事件上）。鸿蒙没有全局曲线，只有
 * continuous 事件自己的 points —— 转译时把曲线折叠进去：
 * - continuous：曲线原样挂到事件的 points 上（增益 0…1）
 * - 曲线窗口里的 transient：把那一刻的曲线增益乘进 intensity
 *
 * 单位换算：秒 → 毫秒；intensity 0…1 → 0…100 整数（伽马提亮，见 INTENSITY_GAMMA）；
 * sharpness 0…1 → frequency 0…100（下限见 FREQUENCY_FLOOR）。
 *
 * 🔴 真机校准（2026-11-04 用户反馈「震动反馈不强」，Mate 80 Pro Max）：
 * - iOS Taptic 引擎低强度瞬时也清脆可感；鸿蒙线性马达强度百分比低于 ~30
 *   几乎无感。iOS 原值 1:1 直译后大半事件落在 12~50，整体偏弱——
 *   intensity 走伽马曲线（i^0.55 × 100）：1.0 仍是 100，低值大幅上拉
 *   （0.22→43、0.42→62、0.85→91），排序不变、节点不变。
 * - iOS 低 sharpness（0.05~0.15）直译出的频率 5~15 落在马达浑浊低频段，
 *   体感进一步打折——频率下限抬到 25（低于默认 50，保留「闷」的质感，
 *   但落在马达能有效驱动的频段）。
 *
 * 纸纤维碎震（grain）iOS 用固定种子的 UInt64 LCG；ArkTS 的 number 位运算
 * 只有 32 位（`seed >> 33` 恒为 0），换 32 位 LCG（Math.imul），分布一致、
 * 序列不同——手感等价，每次投信依然一样（确定性）。
 *
 * 事件数硬上限：IPC 层 `MAX_EVENT_SIZE = 16`（vibrator_infos.cpp 的
 * VibratePattern::Unmarshalling，超限直接反序列化失败 → 14600101）。
 * 碎震走预算制：16 减去固定事件数，窗口均分采样。
 *
 * 时间轴踩 `LetterPostingTimeline`（改一处要三处一起改：动画 / 震动 / 声音）。
 */
import { LetterPostingTimeline } from './LetterPostingTimeline';

/** 事件类型：点打（短促一下）/ 持续（一段嗡鸣，可带调节曲线） */
export enum HapticEventKind {
  TRANSIENT = 0,
  CONTINUOUS = 1
}

/** 持续事件里的调节曲线点（time 相对事件起点；intensity 是 [0,1] 增益） */
export interface HapticCurvePoint {
  time: number;
  intensity: number;
  frequency: number;
}

/** 一条震动事件。单位毫秒；intensity/frequency 取值 [0,100]（SDK 约束，整数） */
export interface HapticPatternEvent {
  kind: HapticEventKind;
  time: number;
  duration: number;
  intensity: number;
  frequency: number;
  points: HapticCurvePoint[];
}

/** 32 位线性同余发生器（数值配方常数）：确定性伪随机，给纸纤维碎震用（拆信编排也用） */
export class Lcg32 {
  private seed: number;

  constructor(seed: number) {
    this.seed = seed >>> 0;
  }

  /** 下一个 [0,1] 均匀随机（同种子序列固定） */
  next(): number {
    this.seed = (Math.imul(this.seed, 1664525) + 1013904223) >>> 0;
    return (this.seed >>> 8) / 0xFFFFFF;
  }
}

export class PostingHapticPattern {
  /** IPC 硬上限：一条 pattern 最多 16 个事件（超出在服务端反序列化直接失败） */
  static readonly MAX_EVENTS = 16;

  /** 强度伽马：鸿蒙线性马达低百分比无感的设备校准（1.0 → 100 不变，低值上拉） */
  static readonly INTENSITY_GAMMA = 0.55;

  /** 频率下限（iOS sharpness 计）：低于此映射到马达浑浊低频段，体感弱 */
  static readonly FREQUENCY_FLOOR = 0.25;

  /** iOS 强度 0…1 → SDK 0…100 整数（伽马提亮；0 仍 0、1 仍 100） */
  static shapeIntensity(intensity01: number): number {
    return Math.round(100 * Math.pow(intensity01, PostingHapticPattern.INTENSITY_GAMMA));
  }

  /** iOS 锐度 0…1 → SDK frequency 0…100（下限 FREQUENCY_FLOOR，保「闷」但可感） */
  static shapeFrequency(sharpness: number): number {
    return Math.round(Math.max(sharpness, PostingHapticPattern.FREQUENCY_FLOOR) * 100);
  }

  /**
   * 整条编排（sealed = 盖火漆的重版）。纯函数：同参数结果逐字段一致。
   * 事件节点和 iOS 的事件表逐字对应，来源见各段注释里的 iOS 行。
   */
  static build(sealed: boolean): HapticPatternEvent[] {
    const T = LetterPostingTimeline;
    const events: HapticPatternEvent[] = [];

    // —— 收拢（0~0.32s）：几下很轻的纸响（iOS: 0.22/0.16/0.12 × sharpness 0.5）
    events.push(PostingHapticPattern.tap(0.02, 0.22, 0.5));
    events.push(PostingHapticPattern.tap(0.09, 0.16, 0.5));
    events.push(PostingHapticPattern.tap(0.17, 0.12, 0.5));

    // —— 滑进信封（0.32~0.95s）：持续的纸擦纸，钟形曲线挂 points
    //（iOS: continuous intensity 0.42 sharpness 0.3 + bell(floor 0.15)）
    const slideFloor = 0.15;
    const slideDur = Math.round((T.SLIDE_IN_END - T.SLIDE_IN_START) * 1000);
    events.push(PostingHapticPattern.hold(T.SLIDE_IN_START, T.SLIDE_IN_END - T.SLIDE_IN_START,
      0.42, 0.3, PostingHapticPattern.bell(slideDur, slideFloor, 10)));

    // 纸纤维碎震：iOS 的 grain 循环（固定种子 0x504F5354）。事件预算 =
    // MAX_EVENTS 减固定事件（收拢 3 + 滑进 1 + 到底一顿 1 + 封舌 2 +
    // 封口 3/2 + 推进 2 + 翻板落回 2）：滑进窗口均分、段内由确定性 LCG 抖动；
    // 强度已经乘进钟形增益（iOS 是全局曲线压着，这里折叠）
    const rng = new Lcg32(0x504F5354);
    const grainStartSec = T.SLIDE_IN_START + 0.06;
    const grainEndSec = T.SLIDE_IN_END - 0.08;
    const fixedEventCount = 11 + (sealed ? 3 : 2);
    const grainBudget = PostingHapticPattern.MAX_EVENTS - fixedEventCount;
    for (let i = 0; i < grainBudget; i++) {
      const jitter = rng.next();
      const segWidth = (grainEndSec - grainStartSec) / grainBudget;
      const grainSec = grainStartSec + segWidth * i + jitter * segWidth;
      const u = (grainSec - T.SLIDE_IN_START) / (T.SLIDE_IN_END - T.SLIDE_IN_START);
      const base = 0.07 + 0.14 * 4 * u * (1 - u) * (0.6 + 0.4 * jitter);
      events.push(PostingHapticPattern.tap(grainSec,
        base * PostingHapticPattern.bellGain(u, slideFloor), 0.4 + 0.2 * jitter));
    }
    // 到底轻轻一顿（iOS: slideIn 上界前 0.03s，intensity 0.32；折钟形增益）
    const endU = (T.SLIDE_IN_END - 0.03 - T.SLIDE_IN_START) / (T.SLIDE_IN_END - T.SLIDE_IN_START);
    events.push(PostingHapticPattern.tap(T.SLIDE_IN_END - 0.03,
      0.32 * PostingHapticPattern.bellGain(endU, slideFloor), 0.3));

    // —— 封舌合上（0.95~1.40s）：低低一段（iOS: 0.22/0.15 + bell(floor 0.1)），
    // 落下软软一拍（iOS: 0.5/0.25，落在曲线末端增益 floor 上）
    const flapFloor = 0.1;
    const flapDur = Math.round((T.FLAP_CLOSE_END - T.FLAP_CLOSE_START) * 1000);
    events.push(PostingHapticPattern.hold(T.FLAP_CLOSE_START, T.FLAP_CLOSE_END - T.FLAP_CLOSE_START,
      0.22, 0.15, PostingHapticPattern.bell(flapDur, flapFloor, 8)));
    events.push(PostingHapticPattern.tap(T.FLAP_CLOSE_END,
      0.5 * PostingHapticPattern.bellGain(1.0, flapFloor), 0.25));

    // —— 封口（1.46~1.76s）
    if (sealed) {
      // 火漆：蜡被压扁一段（0.32/0.08 × 0.22s）、压实一下（0.85/0.28）、回软（0.25/0.05）
      events.push(PostingHapticPattern.hold(T.SEAL_START + 0.04, 0.22, 0.32, 0.08, []));
      events.push(PostingHapticPattern.tap(T.SEAL_END - 0.06, 0.85, 0.28));
      events.push(PostingHapticPattern.hold(T.SEAL_END - 0.05, 0.10, 0.25, 0.05, []));
    } else {
      // 抹平：指腹顺着封舌擦过去（0.2/0.4 一下 + 0.2/0.35 × 0.26s 一段）
      //（持续段 +1ms：SDK 约束事件间 time 值不能重叠，iOS 原表两件事同一时刻）
      events.push(PostingHapticPattern.tap(T.SEAL_START + 0.02, 0.2, 0.4));
      events.push(PostingHapticPattern.hold(T.SEAL_START + 0.02 + 0.001, 0.26, 0.2, 0.35, []));
    }

    // —— 推进投信口（2.42~2.82s）：翻板被顶开一下（0.38/0.6，折曲线增益），
    // 纸蹭铁皮越推越紧（0.5/0.5，曲线两头低、85% 处最重）
    const insertDur = Math.round((T.INSERT_END - T.INSERT_START) * 1000);
    const insertCurve: HapticCurvePoint[] = [
      { time: 0, intensity: 0.3, frequency: 0 },
      { time: Math.round(insertDur * 0.5), intensity: 0.7, frequency: 0 },
      { time: Math.round(insertDur * 0.85), intensity: 1.0, frequency: 0 },
      { time: insertDur, intensity: 0.0, frequency: 0 }
    ];
    const insertTapGain = PostingHapticPattern.curveAt(insertCurve, Math.round(insertDur * 0.075));
    events.push(PostingHapticPattern.tap(T.INSERT_START + 0.03, 0.38 * insertTapGain, 0.6));
    events.push(PostingHapticPattern.hold(T.INSERT_START, T.INSERT_END - T.INSERT_START,
      0.5, 0.5, insertCurve));

    // —— 翻板落回去（2.90s）：重重一下闷响（1.0/0.35）+ 余震（0.4/0.08 × 0.14s，
    // iOS 曲线 2 个控制点，SDK 要 4~16 个 —— 沿同一条直线补采样，形状不变）
    events.push(PostingHapticPattern.tap(T.FLAP_FALL_END, 1.0, 0.35));
    const tailDur = Math.round(0.14 * 1000);
    const tail: HapticCurvePoint[] = [
      { time: 0, intensity: 1.0, frequency: 0 },
      { time: Math.round(tailDur / 3), intensity: 2 / 3, frequency: 0 },
      { time: Math.round(tailDur * 2 / 3), intensity: 1 / 3, frequency: 0 },
      { time: tailDur, intensity: 0.0, frequency: 0 }
    ];
    events.push(PostingHapticPattern.hold(T.FLAP_FALL_END + 0.01, 0.14, 0.4, 0.08, tail));

    return events;
  }

  /** 点打：秒 / intensity、sharpness 都是 iOS 原值（0…1），整形后换算成 0…100 整数 */
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

  /** 持续段：秒 / intensity、sharpness 同上；points 为空数组 = 不带曲线 */
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

  /** 钟形增益（曲线窗口里的点打折叠用） */
  private static bellGain(u: number, floor: number): number {
    return floor + (1 - floor) * 4 * u * (1 - u);
  }

  /** 折线在 timeMs 处的值（分段线性插值） */
  private static curveAt(curve: HapticCurvePoint[], timeMs: number): number {
    if (timeMs <= curve[0].time) {
      return curve[0].intensity;
    }
    for (let i = 1; i < curve.length; i++) {
      if (timeMs <= curve[i].time) {
        const a = curve[i - 1];
        const b = curve[i];
        const span = b.time - a.time;
        const u = span > 0 ? (timeMs - a.time) / span : 0;
        return a.intensity + (b.intensity - a.intensity) * u;
      }
    }
    return curve[curve.length - 1].intensity;
  }
}
