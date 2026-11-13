/**
 * 世界地图的白天黑夜单测（U01「标准答案」，NOAA 简化太阳高度角）：
 *
 * 北京 (39.9, 116.4)：
 * - 2026-10-15 09:30Z（当地 17:30）≈ +0.2° → 浅色
 * - 2026-10-15 10:10Z（当地 18:10）≈ -7.4° → 深色
 * - 2026-06-21 11:30Z（当地 19:30）≈ +1.9° → 浅色
 * - 2026-06-21 12:30Z（当地 20:30）≈ -7.6° → 深色
 * - 没有位置：手机时区 17:59 浅色、18:00 深色
 */
import { describe, it, expect } from '@ohos/hypium';
import { PenPalCoordinate } from '../../main/ets/models/PenPal';
import { isNight, solarElevation, NIGHT_BELOW_DEGREES } from '../../main/ets/models/MapDaylight';

const BEIJING = new PenPalCoordinate(39.9, 116.4);

const OCT_15_0930Z = Date.UTC(2026, 9, 15, 9, 30);
const OCT_15_1010Z = Date.UTC(2026, 9, 15, 10, 10);
const JUN_21_1130Z = Date.UTC(2026, 5, 21, 11, 30);
const JUN_21_1230Z = Date.UTC(2026, 5, 21, 12, 30);

// 标准答案自带约 0.1° 的算法误差，断言放宽到 1°
const ELEVATION_TOLERANCE = 1.0;

export default function mapDaylightTest() {
  describe('MapDaylightTest', () => {
    it('nightThresholdIsMinusSixDegrees', 0, () => {
      expect(NIGHT_BELOW_DEGREES).assertEqual(-6.0);
    })

    it('beijingOctoberAfternoonIsStillLight', 0, () => {
      const e = solarElevation(OCT_15_0930Z, BEIJING.lat, BEIJING.lon);
      expect(Math.abs(e - 0.2) <= ELEVATION_TOLERANCE).assertTrue();
      expect(isNight(OCT_15_0930Z, BEIJING, 17)).assertFalse();
    })

    it('beijingOctoberEveningIsDark', 0, () => {
      const e = solarElevation(OCT_15_1010Z, BEIJING.lat, BEIJING.lon);
      expect(Math.abs(e - (-7.4)) <= ELEVATION_TOLERANCE).assertTrue();
      expect(isNight(OCT_15_1010Z, BEIJING, 18)).assertTrue();
    })

    it('beijingJuneEveningIsStillLight', 0, () => {
      const e = solarElevation(JUN_21_1130Z, BEIJING.lat, BEIJING.lon);
      expect(Math.abs(e - 1.9) <= ELEVATION_TOLERANCE).assertTrue();
      expect(isNight(JUN_21_1130Z, BEIJING, 19)).assertFalse();
    })

    it('beijingJuneLateEveningIsDark', 0, () => {
      const e = solarElevation(JUN_21_1230Z, BEIJING.lat, BEIJING.lon);
      expect(Math.abs(e - (-7.6)) <= ELEVATION_TOLERANCE).assertTrue();
      expect(isNight(JUN_21_1230Z, BEIJING, 20)).assertTrue();
    })

    it('elevationIsLowerAtNightThanDuringDay', 0, () => {
      const day = solarElevation(Date.UTC(2026, 9, 15, 4, 0), BEIJING.lat, BEIJING.lon);
      const night = solarElevation(OCT_15_1010Z, BEIJING.lat, BEIJING.lon);
      expect(night < day).assertTrue();
    })

    it('noLocationFallsBackToDeviceHour', 0, () => {
      // 17:59 → 17 浅色；18:00 → 18 深色
      expect(isNight(Date.now(), null, 17)).assertFalse();
      expect(isNight(Date.now(), null, 18)).assertTrue();
      // 6:00 起是白天，5:59 还是夜里
      expect(isNight(Date.now(), null, 6)).assertFalse();
      expect(isNight(Date.now(), null, 5)).assertTrue();
    })
  })
}
