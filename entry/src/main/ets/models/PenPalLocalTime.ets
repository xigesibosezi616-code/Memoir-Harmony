/**
 * 笔友那里此刻：几点、白天还是夜里、什么季节（U01 世界笔友）。
 * 对应 iOS `Services/PenPals/PenPalTravel.swift` 里的 `PenPalLocalTime`。
 *
 * - 纯逻辑：时区换算（IANA 时区在某一刻的偏移量）由调用方注入 `offsetMs`
 *   （服务层用 `@kit.LocalizationKit` 的 i18n 取，单测给固定偏移），
 *   这里只算「偏移之后的小时 / 月份」和季节
 * - 季节：南半球和北半球相反；回归线之间（|纬度| < 23.5°，如新加坡、内罗毕）
 *   没有四季，返回 null 不写
 * - 白天还是夜里：他那里 6:00–18:00 算白天（名片上的太阳 / 月亮图标用）
 */

/** 他那里的季节 */
export enum PenPalSeason {
  Spring = 'spring',
  Summer = 'summer',
  Autumn = 'autumn',
  Winter = 'winter'
}

/** 偏移之后的地方钟点（小时 0–23）和月份（1–12） */
export class LocalCalendar {
  readonly hour: number;
  readonly month: number;

  constructor(hour: number, month: number) {
    this.hour = hour;
    this.month = month;
  }
}

/** `atMs` 在「UTC + offsetMs」时区下的小时与月份（月份 1–12） */
export function localCalendar(atMs: number, offsetMs: number): LocalCalendar {
  const shifted = new Date(atMs + offsetMs);
  return new LocalCalendar(shifted.getUTCHours(), shifted.getUTCMonth() + 1);
}

/** 他那里是白天吗（6:00–18:00；`hour` = 他那里的钟点，localCalendar 取） */
export function isDaytimeAt(hour: number): boolean {
  return hour >= 6 && hour < 18;
}

/** 回归线的纬度：|纬度| 比它小没有四季（新加坡、内罗毕） */
export const TROPICS_LATITUDE: number = 23.5;

/**
 * 他那里的季节。南半球和北半球相反；回归线之间返回 null。
 * `month` = 他那里的月份（1–12，localCalendar 取）。
 */
export function seasonAt(latitude: number, month: number): PenPalSeason | null {
  if (Math.abs(latitude) < TROPICS_LATITUDE) {
    return null;
  }
  let northern: PenPalSeason;
  if (month >= 3 && month <= 5) {
    northern = PenPalSeason.Spring;
  } else if (month >= 6 && month <= 8) {
    northern = PenPalSeason.Summer;
  } else if (month >= 9 && month <= 11) {
    northern = PenPalSeason.Autumn;
  } else {
    northern = PenPalSeason.Winter;
  }
  if (latitude >= 0) {
    return northern;
  }
  // 南半球反着来
  switch (northern) {
    case PenPalSeason.Spring:
      return PenPalSeason.Autumn;
    case PenPalSeason.Summer:
      return PenPalSeason.Winter;
    case PenPalSeason.Autumn:
      return PenPalSeason.Spring;
    default:
      return PenPalSeason.Summer;
  }
}
