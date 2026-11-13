/**
 * 笔友那里的钟点与季节单测（U01 世界笔友）。
 *
 * - localCalendar：注入时区偏移后的小时 / 月份
 * - isDaytimeAt：6:00–18:00 是白天
 * - seasonAt：南半球和北半球相反；回归线之间（|纬度| < 23.5°）没有四季
 */
import { describe, it, expect } from '@ohos/hypium';
import { localCalendar, isDaytimeAt, seasonAt,
  PenPalSeason, TROPICS_LATITUDE } from '../../main/ets/models/PenPalLocalTime';

const HOUR_MS = 3600 * 1000;

export default function penPalLocalTimeTest() {
  describe('PenPalLocalTimeTest', () => {
    it('localCalendarAppliesOffset', 0, () => {
      // UTC 2026-10-15 16:30，+8h → 当地 10 月 16 日 0:30
      const at = Date.UTC(2026, 9, 15, 16, 30);
      const cal = localCalendar(at, 8 * HOUR_MS);
      expect(cal.hour).assertEqual(0);
      expect(cal.month).assertEqual(10);
    })

    it('localCalendarNegativeOffset', 0, () => {
      // UTC 2026-01-01 01:00，-5h → 当地 2025-12-31 20:00
      const at = Date.UTC(2026, 0, 1, 1, 0);
      const cal = localCalendar(at, -5 * HOUR_MS);
      expect(cal.hour).assertEqual(20);
      expect(cal.month).assertEqual(12);
    })

    it('localCalendarZeroOffsetIsUtc', 0, () => {
      const at = Date.UTC(2026, 5, 21, 11, 30);
      const cal = localCalendar(at, 0);
      expect(cal.hour).assertEqual(11);
      expect(cal.month).assertEqual(6);
    })

    it('daytimeIsSixToEighteen', 0, () => {
      expect(isDaytimeAt(5)).assertFalse();
      expect(isDaytimeAt(6)).assertTrue();
      expect(isDaytimeAt(12)).assertTrue();
      expect(isDaytimeAt(17)).assertTrue();
      expect(isDaytimeAt(18)).assertFalse();
      expect(isDaytimeAt(23)).assertFalse();
    })

    it('northernHemisphereSeasons', 0, () => {
      expect(seasonAt(40, 1)).assertEqual(PenPalSeason.Winter);
      expect(seasonAt(40, 3)).assertEqual(PenPalSeason.Spring);
      expect(seasonAt(40, 5)).assertEqual(PenPalSeason.Spring);
      expect(seasonAt(40, 6)).assertEqual(PenPalSeason.Summer);
      expect(seasonAt(40, 8)).assertEqual(PenPalSeason.Summer);
      expect(seasonAt(40, 9)).assertEqual(PenPalSeason.Autumn);
      expect(seasonAt(40, 11)).assertEqual(PenPalSeason.Autumn);
      expect(seasonAt(40, 12)).assertEqual(PenPalSeason.Winter);
    })

    it('southernHemisphereSeasonsFlip', 0, () => {
      expect(seasonAt(-40, 1)).assertEqual(PenPalSeason.Summer);
      expect(seasonAt(-40, 7)).assertEqual(PenPalSeason.Winter);
      expect(seasonAt(-40, 4)).assertEqual(PenPalSeason.Autumn);
      expect(seasonAt(-40, 10)).assertEqual(PenPalSeason.Spring);
    })

    it('tropicsHaveNoSeason', 0, () => {
      // 新加坡 (1.33)、内罗毕 (-1.29)
      expect(seasonAt(1.33, 7)).assertNull();
      expect(seasonAt(-1.29, 1)).assertNull();
      // 边界上（= 23.5°）仍有季节
      expect(seasonAt(TROPICS_LATITUDE, 7)).assertEqual(PenPalSeason.Summer);
    })
  })
}
