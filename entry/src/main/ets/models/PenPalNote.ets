/**
 * 笔友手记里的一条（U01 B3；对应 iOS `Models/PenPalNote.swift`）。
 *
 * 为什么有它：让用户觉得这个笔友是真的他的一个长期的笔友，而不是感觉像一个 AI，
 * 今天发生的事情或者前几周发生的事情过一段时间就忘了。
 *
 * - **每位笔友各一本**（`penPalID`）：世界笔友用他的 id，自己起名的那位用
 *   `PenPalNote.ownID`（"own"，世界笔友的 id 都是小写英文名，不会撞）。各记各的：
 *   寄给谁就只带谁的那本，只寄给 3 位的事，另外 12 位永远不知道
 * - **只存在本机**，寄信时随请求带上，服务端用完即弃；跟着备份包导出（R-NOTEBOOK-02）
 * - 两种（`kind`）：
 *   - 画像（profile）：这个人是谁。**一位笔友一份完整的文本**，需要时整份重写
 *   - 大事（recent）：生活里重要的事和节点，带日期。寄信时带最近的 `recentLimit` 件
 * - `notedAtMs` = 记下它的那封回信的写信时刻 —— 信可能隔几周才寄，
 *   他得知道这是哪天记的（「上个月的面试」就该问「后来怎么样了」）
 * - 🔴 **用户在 App 里看不到、也删不了**（2026-10-24 产品定）：不做任何查看 /
 *   编辑 / 删除手记的界面
 */
import { generateUuid } from './Uuid';

/** 手记两种：画像（一位一份，整份重写）/ 大事（带日期，快满时笔友自己合并旧的） */
export enum PenPalNoteKind {
  Profile = 'profile',
  Recent = 'recent'
}

export class PenPalNote {
  /** 大写带横线 UUID（回执按它改写 / 删，备份包按它去重） */
  id: string = generateUuid();
  penPalID: string;
  text: string;
  /** 记下它的那封回信的写信时刻（毫秒） */
  notedAtMs: number;
  createdAtMs: number = Date.now();
  /** 画像还是大事。不认识的值（更新版本加的）原样保留，寄信 / 应用改法时按大事 */
  kind: string = PenPalNoteKind.Recent;
  /** 笔友改过这条的时刻（毫秒）；undefined = 没改过 */
  updatedAtMs?: number;

  constructor(penPalID: string, text: string, notedAtMs: number) {
    this.penPalID = penPalID;
    this.text = text;
    this.notedAtMs = notedAtMs;
  }

  /** 解析后的种类：不认识的 kind 按大事（iOS noteKind 同款） */
  noteKind(): PenPalNoteKind {
    return this.kind === PenPalNoteKind.Profile
      ? PenPalNoteKind.Profile : PenPalNoteKind.Recent;
  }

  /** 最后一次记下 / 改写的时刻（毫秒） */
  touchedMs(): number {
    return this.updatedAtMs ?? this.notedAtMs;
  }

  /** 自己起名的那位的手记用这个 id */
  static readonly ownID: string = 'own';
  /** 大事带最近的几件去（快满时笔友自己合并旧的，与后端 RECENT_LIMIT 一致） */
  static readonly recentLimit: number = 30;
}
