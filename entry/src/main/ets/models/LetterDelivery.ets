/**
 * 回信的「寄送」规则与阶段判定（05_DATA_MODEL.md §6.1）。
 * 对应 iOS `Models/LetterDelivery.swift`。
 *
 * - 邮筒 = 寄信（主动）：点邮筒那一刻本地建信，`generatedAt` = 寄出时刻
 * - 信箱 = 收信（被动）：回信在寄出后 **6 小时 ~ 3 天**的随机时刻「到达」，
 *   `deliveredAt` 寄出时就算好（未来时间）
 * - 🔴 阶段判定是**跨端行为规则**，两端必须逐字一致（05 §6.1 的表）
 * - Letter 的时间字段（generatedAt / deliveredAt）是毫秒；`now` 由调用方注入
 */
import { Letter, LetterStatus } from './Letter';

export class LetterDelivery {
  /** 最快多久到（6 小时），秒 */
  static readonly minimumDelaySec: number = 6 * 3600;
  /** 最慢多久到（3 天），秒 */
  static readonly maximumDelaySec: number = 72 * 3600;
  /** 一次最多寄出多少篇日记。只是保护上限 —— 太多篇塞进一封信，提示词会超长 */
  static readonly maximumEntriesPerLetter: number = 14;

  /**
   * 回信的到达时刻：寄出后 [6 小时, 3 天] 内均匀随机。
   * - `random` 返回 [0, 1) 的均匀随机数，测试里注入固定序列
   * - `timeScale` 时间压缩倍率，正式包恒为 1（测试加速见 5.8）
   */
  static arrivalDate(sentAtMs: number, timeScale: number, random: () => number): number {
    const minMs = LetterDelivery.minimumDelaySec * 1000;
    const maxMs = LetterDelivery.maximumDelaySec * 1000;
    const delay = minMs + random() * (maxMs - minMs);
    return sentAtMs + delay / Math.max(timeScale, 1);
  }

  /**
   * 这封信算不算「真正寄出过」的信（05 §6.1「真正的信」）。
   * 老流程留下的 generating / failed / 空正文记录不删，但不算寄出过；
   * status 存的是原样字符串，不认识的值一律不算。
   */
  static isRealLetter(letter: Letter): boolean {
    if (letter.body.length === 0) {
      return false;
    }
    return letter.status === LetterStatus.Pending ||
      letter.status === LetterStatus.Delivered ||
      letter.status === LetterStatus.Read;
  }

  /** 到达时刻。老数据没有 deliveredAt 的按寄出时刻算（等于早就到了） */
  static arrivalOf(letter: Letter): number {
    return letter.deliveredAt !== undefined ? letter.deliveredAt : letter.generatedAt;
  }

  /** 已到达：真正的信 且 (deliveredAt ?? generatedAt) <= now */
  static hasArrived(letter: Letter, nowMs: number): boolean {
    return LetterDelivery.isRealLetter(letter) && LetterDelivery.arrivalOf(letter) <= nowMs;
  }

  /** 在路上：真正的信 且 (deliveredAt ?? generatedAt) > now */
  static isInTransit(letter: Letter, nowMs: number): boolean {
    return LetterDelivery.isRealLetter(letter) && LetterDelivery.arrivalOf(letter) > nowMs;
  }

  /** 未读：已到达 且 status != read */
  static isUnread(letter: Letter, nowMs: number): boolean {
    return LetterDelivery.hasArrived(letter, nowMs) && letter.status !== LetterStatus.Read;
  }

  /** 写信中：status == generating 且正文空（投进邮筒、回信还没写好；对用户也算「在路上」） */
  static isWriting(letter: Letter): boolean {
    return letter.status === LetterStatus.Generating && letter.body.length === 0;
  }

  /**
   * 退回（信件字段部分）：status == failed 且正文空。
   * 「归本机负责」由调用方再滤 —— 那是本机偏好，不进库（05 §6.2，5.3 寄信队列接）。
   */
  static isBounced(letter: Letter): boolean {
    return letter.status === LetterStatus.Failed && letter.body.length === 0;
  }
}
