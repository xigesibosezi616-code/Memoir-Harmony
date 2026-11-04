/**
 * 投信震动编排单测（PostingHapticPattern）。
 * 锚点：iOS `Posting/LetterPostingFeel.swift` 的事件表 1:1 转译；
 * 时间节点踩 LetterPostingTimeline，SDK 约束（取值范围 / 点数）必须全过。
 */
import { describe, it, expect } from '@ohos/hypium';
import { PostingHapticPattern, HapticEventKind, HapticPatternEvent } from '../../main/ets/models/PostingHapticPattern';
import { LetterPostingTimeline } from '../../main/ets/models/LetterPostingTimeline';

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

export default function postingHapticPatternTest() {
  describe('PostingHapticPatternTest', () => {
    it('eventsStayWithinSdkRanges', 0, () => {
      // VibrateFromPattern 的硬约束：intensity/frequency [0,100] 整数、
      // duration (0,5000]、points 4~16 个、点增益 [0,1] 且不越出事件时长
      for (const sealed of [false, true]) {
        const events = PostingHapticPattern.build(sealed);
        expect(events.length > 0).assertTrue();
        // IPC 硬上限：超过 16 个事件，服务端 VibratePattern 反序列化直接失败（14600101）
        expect(events.length <= PostingHapticPattern.MAX_EVENTS).assertTrue();
        for (const e of events) {
          expect(Number.isInteger(e.time)).assertTrue();
          expect(e.time >= 0).assertTrue();
          expect(e.time <= (LetterPostingTimeline.FLAP_FALL_END + 0.2) * 1000).assertTrue();
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
    })

    it('marksAlignWithTimeline', 0, () => {
      const plain = PostingHapticPattern.build(false);
      // 收拢第一下纸响 0.02s（伽马提亮：0.22 → 43）
      const firstTap = findTap(plain, 20);
      expect(firstTap !== undefined).assertTrue();
      if (firstTap !== undefined) {
        expect(firstTap.intensity).assertEqual(43);
        expect(firstTap.frequency).assertEqual(50);
      }
      // 滑进信封：0.32s 起、0.63s 长、钟形曲线 11 个点（samples+1）；底强度提亮 0.42 → 62
      const slide = findHold(plain, 320);
      expect(slide !== undefined).assertTrue();
      if (slide !== undefined) {
        expect(slide.duration).assertEqual(630);
        expect(slide.intensity).assertEqual(62);
        expect(slide.points.length).assertEqual(11);
        expect(slide.points[0].intensity).assertEqual(0.15);
        expect(slide.points[5].intensity > 0.99).assertTrue();
      }
      // 封舌合上 0.95s 起 0.45s；1.40 落下软软一拍（曲线末端增益 0.1 折进去，
      // 提亮后 0.05 → 19——旧值 5 在真机上几乎无感）
      const flap = findHold(plain, 950);
      expect(flap !== undefined).assertTrue();
      if (flap !== undefined) {
        expect(flap.duration).assertEqual(450);
      }
      const flapLand = findTap(plain, 1400);
      expect(flapLand !== undefined).assertTrue();
      if (flapLand !== undefined) {
        expect(flapLand.intensity).assertEqual(19);
        expect(flapLand.frequency).assertEqual(25);
      }
      // 推进投信口 2.42s 起 0.40s，曲线两头低、85% 处最重（越推越紧）；底强度提亮 0.5 → 68
      const insert = findHold(plain, 2420);
      expect(insert !== undefined).assertTrue();
      if (insert !== undefined) {
        expect(insert.duration).assertEqual(400);
        expect(insert.intensity).assertEqual(68);
        expect(insert.points.length).assertEqual(4);
        expect(insert.points[2].intensity).assertEqual(1.0);
      }
      // 翻板落回去 2.90s：重重一下（满强度、中低频——伽马整形 1.0 不变）
      const thud = findTap(plain, 2900);
      expect(thud !== undefined).assertTrue();
      if (thud !== undefined) {
        expect(thud.intensity).assertEqual(100);
        expect(thud.frequency).assertEqual(35);
      }
      // 余震 2.91s 起 0.14s，线性衰减到 0
      const tail = findHold(plain, 2910);
      expect(tail !== undefined).assertTrue();
      if (tail !== undefined) {
        expect(tail.duration).assertEqual(140);
        expect(tail.points[tail.points.length - 1].intensity).assertEqual(0);
      }
    })

    it('intensityShapingLiftsLowEndAndKeepsExtremes', 0, () => {
      // 伽马提亮：0 → 0、1 → 100 不变；低值上拉且排序不变（真机弱反馈的设备校准）
      expect(PostingHapticPattern.shapeIntensity(0)).assertEqual(0);
      expect(PostingHapticPattern.shapeIntensity(1)).assertEqual(100);
      expect(PostingHapticPattern.shapeIntensity(0.22)).assertEqual(43);
      expect(PostingHapticPattern.shapeIntensity(0.42)).assertEqual(62);
      expect(PostingHapticPattern.shapeIntensity(0.85)).assertEqual(91);
      expect(PostingHapticPattern.shapeIntensity(0.16) > PostingHapticPattern.shapeIntensity(0.12))
        .assertTrue();
      // 频率下限：低 sharpness 抬到 25（马达有效频段），高于下限的原样直译
      expect(PostingHapticPattern.shapeFrequency(0.05)).assertEqual(25);
      expect(PostingHapticPattern.shapeFrequency(0.25)).assertEqual(25);
      expect(PostingHapticPattern.shapeFrequency(0.5)).assertEqual(50);
      expect(PostingHapticPattern.shapeFrequency(1)).assertEqual(100);
    })

    it('buildIsDeterministicAndSealedDiffers', 0, () => {
      // 固定种子：每次投信手感一样（iOS 同款要求）
      const a = JSON.stringify(PostingHapticPattern.build(false));
      const b = JSON.stringify(PostingHapticPattern.build(false));
      expect(a).assertEqual(b);
      expect(JSON.stringify(PostingHapticPattern.build(true)))
        .assertEqual(JSON.stringify(PostingHapticPattern.build(true)));
      // 火漆版和普通版编排不同
      expect(JSON.stringify(PostingHapticPattern.build(true)) !== a).assertTrue();
    })

    it('sealedHasWaxPressPlainHasSmoothingRub', 0, () => {
      const sealed = PostingHapticPattern.build(true);
      const plain = PostingHapticPattern.build(false);
      // 火漆压实那一下 1.70s（提亮 0.85 → 91）
      const press = findTap(sealed, 1700);
      expect(press !== undefined).assertTrue();
      if (press !== undefined) {
        expect(press.intensity).assertEqual(91);
      }
      // 普通封口没有这一下
      expect(findTap(plain, 1700) === undefined).assertTrue();
      // 普通封口：1.48s 一下 + 1.481s 起 0.26s 的轻摩擦（+1ms 错开 time 值；提亮 0.2 → 41）
      const rub = findHold(plain, 1481);
      expect(rub !== undefined).assertTrue();
      if (rub !== undefined) {
        expect(rub.duration).assertEqual(260);
        expect(rub.intensity).assertEqual(41);
      }
      expect(findHold(sealed, 1481) === undefined).assertTrue();
    })

    it('eventTimesAreDistinctAndGrainsStayInsideSlide', 0, () => {
      // SDK：事件间 time 值不能重叠
      for (const sealed of [false, true]) {
        const events = PostingHapticPattern.build(sealed);
        const seen = new Set<number>();
        for (const e of events) {
          expect(seen.has(e.time)).assertFalse();
          seen.add(e.time);
        }
      }
      // 纸纤维碎震全部落在滑进信封窗口里（0.38~0.87），强度 ≤ 收拢段主拍（43）；
      // 预算制：普通版 3 个（16 - 13 固定事件）、火漆版 2 个（16 - 14）
      const plain = PostingHapticPattern.build(false);
      let grainCount = 0;
      for (const e of plain) {
        if (e.kind === HapticEventKind.TRANSIENT && e.time > 320 && e.time < 920) {
          grainCount++;
          expect(e.time >= 380).assertTrue();
          expect(e.time <= 870).assertTrue();
          expect(e.intensity >= 0 && e.intensity <= 43).assertTrue();
        }
      }
      expect(grainCount).assertEqual(3);
      const sealedEvents = PostingHapticPattern.build(true);
      let sealedGrainCount = 0;
      for (const e of sealedEvents) {
        if (e.kind === HapticEventKind.TRANSIENT && e.time > 320 && e.time < 920) {
          sealedGrainCount++;
        }
      }
      expect(sealedGrainCount).assertEqual(2);
    })
  })
}
