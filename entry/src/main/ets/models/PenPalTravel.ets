/**
 * 路程：信从你这里到笔友那里、回信再回来，要多久（U01 世界笔友）。
 * 对应 iOS `Services/PenPals/PenPalTravel.swift`。
 *
 * **在本机算，位置不上传**。分档是跨端规则 —— 两端必须跑同一组用例、
 * 得出同一档（U01「标准答案」附西安 → 斯图尔特岛 / 京都等固定距离）：
 * - <3000 公里 → 6–24 小时（一天之内）
 * - 3000–9000 → 18–48（一两天）
 * - >9000 → 36–72（两三天）
 * - 南极固定 72–120（三到五天）
 * - 不知道你在哪（没给定位）→ 18–48
 * - 自己起名的那位 → 2–6 小时
 */
import { PenPal, PenPalCoordinate } from './PenPal';

/** 地球平均半径（公里；两端同值，U01 标准答案按它算） */
export const EARTH_RADIUS_KM: number = 6371.0088;

/** 回信分档。范围内随机，到了才知道 —— 现实里也没人知道信哪天到 */
export enum ReplyTime {
  /** 自己起名的那一位：没有住址，就在身边 */
  OwnPenPal = 'ownPenPal',
  /** 3000 公里以内 */
  Near = 'near',
  /** 3000–9000 公里 */
  Middle = 'middle',
  /** 9000 公里以上 */
  Far = 'far',
  /** 南极，多远都一样 */
  Antarctic = 'antarctic',
  /** 不知道你在哪（没给定位权限） */
  UnknownDistance = 'unknownDistance'
}

/** 一档的小时数范围（闭区间） */
export class ReplyHours {
  readonly minHours: number;
  readonly maxHours: number;

  constructor(minHours: number, maxHours: number) {
    this.minHours = minHours;
    this.maxHours = maxHours;
  }
}

/** 每一档寄出到回信到达的小时数（两端一致，U01 标准答案） */
export function replyHoursOf(replyTime: ReplyTime): ReplyHours {
  switch (replyTime) {
    case ReplyTime.OwnPenPal:
      return new ReplyHours(2, 6);
    case ReplyTime.Near:
      return new ReplyHours(6, 24);
    case ReplyTime.Middle:
    case ReplyTime.UnknownDistance:
      return new ReplyHours(18, 48);
    case ReplyTime.Far:
      return new ReplyHours(36, 72);
    case ReplyTime.Antarctic:
      return new ReplyHours(72, 120);
    default:
      return new ReplyHours(18, 48);
  }
}

/**
 * 这一档里均匀随机一个到达时刻。
 * `random01` 由调用方注入（Math.random 或单测的固定序列）；
 * `timeScale` 是开发时的加速倍率（正式包恒为 1）。
 */
export function arrivalDateMs(sentAtMs: number, replyTime: ReplyTime,
  random01: number, timeScale: number = 1): number {
  const hours = replyHoursOf(replyTime);
  const t = Math.min(Math.max(random01, 0), 1);
  const span = hours.minHours + (hours.maxHours - hours.minHours) * t;
  return sentAtMs + span * 3600 * 1000 / Math.max(timeScale, 1);
}

/** 回信多久到（分档判定；user 传 null = 不知道你在哪） */
export function replyTimeTo(penPal: PenPal, user: PenPalCoordinate | null): ReplyTime {
  if (penPal.isAntarctic()) {
    return ReplyTime.Antarctic;
  }
  if (user === null) {
    return ReplyTime.UnknownDistance;
  }
  const distance = distanceKilometers(user, penPal.coordinate);
  if (distance < 3000) {
    return ReplyTime.Near;
  }
  if (distance < 9000) {
    return ReplyTime.Middle;
  }
  return ReplyTime.Far;
}

/** 两点之间的大圆距离（公里，haversine；iOS distanceKilometers 同款） */
export function distanceKilometers(a: PenPalCoordinate, b: PenPalCoordinate): number {
  const rad = Math.PI / 180;
  const phi1 = a.lat * rad;
  const phi2 = b.lat * rad;
  const dPhi = phi2 - phi1;
  const dLambda = (b.lon - a.lon) * rad;
  const h = Math.sin(dPhi / 2) * Math.sin(dPhi / 2) +
    Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) * Math.sin(dLambda / 2);
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * 大圆上从 a 走到 b、走了 `fraction`（0…1）的那一点 ——
 * 地图上画「在路上的信」用（iOS point(from:to:fraction:) 同款）。
 */
export function pointOnGreatCircle(a: PenPalCoordinate, b: PenPalCoordinate,
  fraction: number): PenPalCoordinate {
  const rad = Math.PI / 180;
  const phi1 = a.lat * rad;
  const lambda1 = a.lon * rad;
  const phi2 = b.lat * rad;
  const lambda2 = b.lon * rad;
  const d = distanceKilometers(a, b) / EARTH_RADIUS_KM;
  if (d <= 1e-9) {
    return new PenPalCoordinate(a.lat, a.lon);
  }
  const t = Math.min(Math.max(fraction, 0), 1);
  const wa = Math.sin((1 - t) * d) / Math.sin(d);
  const wb = Math.sin(t * d) / Math.sin(d);
  const x = wa * Math.cos(phi1) * Math.cos(lambda1) + wb * Math.cos(phi2) * Math.cos(lambda2);
  const y = wa * Math.cos(phi1) * Math.sin(lambda1) + wb * Math.cos(phi2) * Math.sin(lambda2);
  const z = wa * Math.sin(phi1) + wb * Math.sin(phi2);
  return new PenPalCoordinate(
    Math.atan2(z, Math.sqrt(x * x + y * y)) / rad,
    Math.atan2(y, x) / rad);
}
