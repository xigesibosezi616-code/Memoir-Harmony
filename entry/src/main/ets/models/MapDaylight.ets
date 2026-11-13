/**
 * 世界笔友地图的白天黑夜（U01 决策 15）：**你这里天黑了，地图就是夜里的深色；
 * 天亮了是浅色**。三套主题一样，和主题深浅无关 —— 地图是窗外的世界，不是纸。
 * 对应 iOS `Services/PenPals/MapDaylight.swift`。
 *
 * - 知道你大概在哪：按太阳的高度算。太阳落到地平线下 6°（民用晨昏蒙影，
 *   天真正黑下来）算夜里 —— 十月的北京六点多就黑了，六月要到八点；
 *   用固定钟点会在夏天傍晚天还亮着时就变黑
 * - 不知道（没给定位权限）：按这台手机的时区，18:00–6:00 算夜里
 *   （`localHour` 由调用方按设备时区取，纯函数好测）
 *
 * 跨端规则：两端跑同一组用例得出同一结果（U01「标准答案」附北京四个时刻）。
 */

import { PenPalCoordinate } from './PenPal';

/** 太阳低于地平线这么多度算「天黑了」（民用晨昏蒙影） */
export const NIGHT_BELOW_DEGREES: number = -6.0;

/**
 * 现在是夜里吗。`location` 传 null = 不知道你在哪（按手机时区的钟点算，
 * `localHour` = 此刻在设备时区下的小时数，如 `new Date(atMs).getHours()`）。
 */
export function isNight(atMs: number, location: PenPalCoordinate | null,
  localHour: number): boolean {
  if (location !== null) {
    return solarElevation(atMs, location.lat, location.lon) < NIGHT_BELOW_DEGREES;
  }
  return localHour < 6 || localHour >= 18;
}

/**
 * 太阳高度角（度）。NOAA 的简化算法，误差在 0.1° 以内，判断天黑天亮足够
 * （iOS solarElevation 同款公式，两端结果一致）。
 */
export function solarElevation(atMs: number, latitude: number, longitude: number): number {
  const rad = Math.PI / 180;
  // 距 J2000.0 的天数
  const n = atMs / 86_400_000 + 2_440_587.5 - 2_451_545.0;
  const meanLongitude = (280.460 + 0.985_647_4 * n) % 360;
  const meanAnomaly = (357.528 + 0.985_600_3 * n) % 360 * rad;
  const eclipticLongitude = (meanLongitude + 1.915 * Math.sin(meanAnomaly) +
    0.020 * Math.sin(2 * meanAnomaly)) * rad;
  const obliquity = (23.439 - 0.000_000_4 * n) * rad;
  const declination = Math.asin(Math.sin(obliquity) * Math.sin(eclipticLongitude));
  const rightAscension = Math.atan2(Math.cos(obliquity) * Math.sin(eclipticLongitude),
    Math.cos(eclipticLongitude));
  // 格林尼治恒星时（小时）→ 当地恒星时（弧度）
  const gmst = (18.697_374_558 + 24.065_709_824_419_08 * n) % 24;
  const localSidereal = (gmst * 15 + longitude) * rad;
  const hourAngle = localSidereal - rightAscension;
  const phi = latitude * rad;
  return Math.asin(Math.sin(phi) * Math.sin(declination) +
    Math.cos(phi) * Math.cos(declination) * Math.cos(hourAngle)) / rad;
}
