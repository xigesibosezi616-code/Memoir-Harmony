/**
 * 拆信震动编排单测（LetterOpeningHapticPattern）。
 * 锚点：iOS `Views/PostBox/Envelope/LetterOpeningFeel.swift` 的事件表 1:1 转译；
 * SDK 约束（IPC 16 事件上限 / 取值范围 / 点数）必须全过。
 */
import { describe, it, expect } from '@ohos/hypium';
import { LetterOpeningHapticPattern } from '../../main/ets/models/LetterOpeningHapticPattern';
import { LetterOpeningTimeline } from '../../main/ets/models/LetterOpeningTimeline';
import { PostingHapticPattern, HapticEventKind, HapticPatternEvent } from '../../main/ets/models/PostingHapticPattern';

function findTap(events: HapticPatternEvent[], time: number): HapticPatternEvent | undefined {
  for (const e of events) {
    if (e.kind === HapticEventKind.TRANSIENT && e.time === time) {
      return e;
    }
  }
  return undefined;
}

function findHold(events: HapticPatternEvent[], time: number): HapticPatternEvent | undefined {
  for (const e of events) {
    if (e.kind === HapticEventKind.CONTINUOUS && e.time === time) {
      return e;
    }
  }
  return undefined;
}

function countGrains(events: HapticPatternEvent[], fromMs: number, toMs: number): number {
  let count = 0;
  for (const e of events) {
    if (e.kind === HapticEventKind.TRANSIENT && e.time > fromMs && e.time < toMs) {
      count++;
    }
  }
  return count;
}

export default function letterOpeningHapticPatternTest() {
  describe('LetterOpeningHapticPatternTest', () => {
    it('eventsStayWithinSdkRanges', 0, () => {
      // VibrateFromPattern 的硬约束：intensity/frequency [0,100] 整数、
      // duration (0,5000]、points 4~16 个、点增益 [0,1] 且不越出事件时长
      const maxEndMs = (LetterOpeningTimeline.durationOfStage(2) + 0.7) * 1000;
      for (let stage = 0; stage < LetterOpeningTimeline.STAGE_COUNT; stage++) {
        const events = LetterOpeningHapticPattern.build(stage);
        expect(events.length > 0).assertTrue();
        // IPC 硬上限：超过 16 个事件，服务端 VibratePattern 反序列化直接失败（14600101）
        expect(events.length <= PostingHapticPattern.MAX_EVENTS).assertTrue();
        for (const e of events) {
          expect(Number.isInteger(e.time)).assertTrue();
          expect(e.time >= 0).assertTrue();
          expect(e.time <= maxEndMs).assertTrue();
          expect(Number.isInteger(e.intensity)).assertTrue();
          expect(e.intensity >= 0 && e.intensity <= 100).assertTrue();
          expect(Number.isInteger(e.frequency)).assertTrue();
          expect(e.frequency >= 0 && e.frequency <= 100).assertTrue();
          if (e.kind === HapticEventKind.CONTINUOUS) {
            expect(e.duration > 0 && e.duration <= 5000).assertTrue();
            if (e.points.length > 0) {
              expect(e.points.length >= 4 && e.points.length <= 16).assertTrue();
              for (const p of e.points) {
                expect(p.intensity >= 0 && p.intensity <= 1).assertTrue();
                expect(p.frequency >= -100 && p.frequency <= 100).assertTrue();
                expect(p.time >= 0 && p.time <= e.duration).assertTrue();
              }
            }
          } else {
            expect(e.duration).assertEqual(0);
            expect(e.points.length).assertEqual(0);
          }
        }
      }
      // 不认识的步：空表（调用方不该播）
      expect(LetterOpeningHapticPattern.build(3).length).assertEqual(0);
      expect(LetterOpeningHapticPattern.build(-1).length).assertEqual(0);
    })

    it('eventTimesAreDistinct', 0, () => {
      // SDK：事件间 time 值不能重叠
      for (let stage = 0; stage < LetterOpeningTimeline.STAGE_COUNT; stage++) {
        const events = LetterOpeningHapticPattern.build(stage);
        const seen = new Set<number>();
        for (const e of events) {
          expect(seen.has(e.time)).assertFalse();
          seen.add(e.time);
        }
      }
    })

    it('crackStageMatchesIosTable', 0, () => {
      const events = LetterOpeningHapticPattern.build(0);
      // 一下清脆的重击（1.0 × 曲线增益 0.967 → 整形后 98）+ 三下越来越轻的碎裂
      const hit = findTap(events, 30);
      expect(hit !== undefined).assertTrue();
      if (hit !== undefined) {
        expect(hit.intensity).assertEqual(98);
        expect(hit.frequency).assertEqual(85);
      }
      expect(findTap(events, 78) !== undefined).assertTrue();
      const crack3 = findTap(events, 122);
      expect(crack3 !== undefined).assertTrue();
      if (crack3 !== undefined) {
        expect(crack3.intensity).assertEqual(47);
      }
      // 细砂颗粒：20ms 起 240ms，沿 iOS 曲线（1.0 → 0.6 → 0）衰减到 0
      const sand = findHold(events, 20);
      expect(sand !== undefined).assertTrue();
      if (sand !== undefined) {
        expect(sand.duration).assertEqual(240);
        expect(sand.points[0].intensity).assertEqual(1.0);
        expect(sand.points[sand.points.length - 1].intensity).assertEqual(0);
      }
    })

    it('flapStageMatchesIosTable', 0, () => {
      const events = LetterOpeningHapticPattern.build(1);
      const duration = LetterOpeningTimeline.durationOfStage(1);
      // 撕开封口的细碎阻力：iOS 原值 × 钟形增益（曲线窗口内），整形后抬出无感区
      const tear1 = findTap(events, 5);
      expect(tear1 !== undefined).assertTrue();
      if (tear1 !== undefined) {
        expect(tear1.intensity).assertEqual(15);
      }
      // 翻过头顶软软一顿：0.51s，增益已到钟形顶（≈1），整形后 62
      const top = findTap(events, 510);
      expect(top !== undefined).assertTrue();
      if (top !== undefined) {
        expect(top.intensity).assertEqual(62);
        expect(top.frequency).assertEqual(25);
      }
      // 持续低沉震动：0 起、整步长、钟形曲线（floor 0.12）11 个点
      const hum = findHold(events, 0);
      expect(hum !== undefined).assertTrue();
      if (hum !== undefined) {
        expect(hum.duration).assertEqual(Math.round(duration * 1000));
        expect(hum.points.length).assertEqual(11);
        expect(hum.points[0].intensity).assertEqual(0.12);
        expect(hum.points[5].intensity > 0.99).assertTrue();
      }
    })

    it('slideStageMatchesIosTableAndGrainBudget', 0, () => {
      const events = LetterOpeningHapticPattern.build(2);
      const slide = LetterOpeningTimeline.durationOfStage(2);
      // 持续纸张摩擦：20ms 起 (slide-0.04)s，钟形曲线（floor 0.15）13 个点
      const rub = findHold(events, 20);
      expect(rub !== undefined).assertTrue();
      if (rub !== undefined) {
        expect(rub.duration).assertEqual(1130);
        expect(rub.points.length).assertEqual(13);
        expect(rub.points[6].intensity > 0.99).assertTrue();
      }
      // 纸纤维碎震：预算制 12 个（16 − 4 固定），全落在窗口 (0.07, slide-0.1) 里
      expect(countGrains(events, 70, 1070)).assertEqual(12);
      for (const e of events) {
        if (e.kind === HapticEventKind.TRANSIENT && e.time > 70 && e.time < 1070) {
          // 整形上界：原始 ≤ 0.24 → 伽马提亮后 ≤ 46
          expect(e.intensity >= 0 && e.intensity <= 46).assertTrue();
        }
      }
      // 离开信封轻轻一松（0.32 × 曲线末端增益 ≈ 0.076 → 整形后 24）
      const loose = findTap(events, 1120);
      expect(loose !== undefined).assertTrue();
      if (loose !== undefined) {
        expect(loose.intensity).assertEqual(24);
      }
      // 摊开：1550ms 起 120ms 的轻铺 + 1620ms 落在桌上一顿
      const lay = findHold(events, 1550);
      expect(lay !== undefined).assertTrue();
      if (lay !== undefined) {
        expect(lay.duration).assertEqual(120);
        expect(lay.intensity).assertEqual(39);
      }
      const thud = findTap(events, 1620);
      expect(thud !== undefined).assertTrue();
      if (thud !== undefined) {
        expect(thud.intensity).assertEqual(68);
        expect(thud.frequency).assertEqual(25);
      }
      expect(events.length).assertEqual(16);
    })

    it('buildIsDeterministic', 0, () => {
      // 固定种子：每次拆信手感一样（iOS 同款要求）
      for (let stage = 0; stage < LetterOpeningTimeline.STAGE_COUNT; stage++) {
        const a = JSON.stringify(LetterOpeningHapticPattern.build(stage));
        const b = JSON.stringify(LetterOpeningHapticPattern.build(stage));
        expect(a).assertEqual(b);
      }
    })
  })
}
