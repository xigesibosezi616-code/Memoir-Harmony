/**
 * 墨迹台账（10_BUILD_MANUAL.md 2.8「墨迹会干」）。对应 iOS `RichTextView` 的
 * `.memoirWrittenAt` / `.memoirStruckAt` 文字属性 —— ArkUI RichEditor 装不下
 * 自定义时间戳（Q24），用与活文本逐字符对齐的影子数组保住它们：
 *
 * - `writtenAt[i]` / `struckAt[i]`：活文本第 i 个字符（含锚点占位）的墨迹时刻（Unix 秒）
 * - 每次文本变化（onDidChange）用 `diffTextEdit` 单点 diff 同步台账（插入填本次
 *   编辑会话时刻 `sessionSec`；iOS `freshAttributes` 同款 —— 没开编辑会话（写日记）
 *   填 undefined，墨迹干没干按日记 `createdAt` 判断）
 * - 读回时 `overlayInkOntoSpans` 把台账叠回编辑器读出的纯视觉 spans，
 *   解决「块级 writtenAt 编辑后丢」（Q24）：保存链路从此带上 writtenAt / struckAt
 * - `planInkRespectingDelete`：R-INK-02 删除转划掉的逐字符计划
 *   （iOS `replaceRespectingInk` 的纯函数版，时间可注入）
 */
import { Ink } from './ContentBlock';
import {
  RICH_ANCHOR,
  RichEditorDocument,
  RichFormatFlags,
  RichSpan
} from './RichDocument';
import { TextEditDiff, diffTextEdit } from './RichDocEditor';

/** 与活文本逐字符对齐的墨迹时刻台账 */
export class InkLedger {
  /** 每个字符什么时候写的（Unix 秒）。undefined = 日记写下时就有（按 base 判断干湿） */
  writtenAt: Array<number | undefined> = [];
  /** 每个字符什么时候划掉的（Unix 秒）。undefined = 没划掉 */
  struckAt: Array<number | undefined> = [];

  /** 从编辑器文档（spans 逐字对齐 text，锚点占 1 字符）建台账 */
  static fromDocument(doc: RichEditorDocument): InkLedger {
    const ledger = new InkLedger();
    for (const span of doc.spans) {
      for (let i = 0; i < span.text.length; i++) {
        ledger.writtenAt.push(span.flags.writtenAt);
        ledger.struckAt.push(span.flags.struckAt);
      }
    }
    return ledger;
  }

  get length(): number {
    return this.writtenAt.length;
  }

  /**
   * 前后活文本的单点 diff 落到台账上。插入的新字符记本次编辑会话的时刻
   * `sessionSec`（undefined = 还在写的稿，不记 —— iOS `freshAttributes` 同款）；
   * 复杂 diff（替换）按「先删后插」处理。
   */
  applyTextDiff(diff: TextEditDiff, sessionSec: number | undefined): void {
    if (diff.kind === 'none') {
      return;
    }
    if (diff.kind === 'delete') {
      this.writtenAt.splice(diff.offset, diff.length);
      this.struckAt.splice(diff.offset, diff.length);
      return;
    }
    if (diff.kind === 'insert') {
      this.spliceIn(diff.offset, diff.value.length, sessionSec);
      return;
    }
    // complex：同一处替换（IME 组合 / 粘贴覆盖）—— 先删后插
    this.writtenAt.splice(diff.offset, diff.length);
    this.struckAt.splice(diff.offset, diff.length);
    this.spliceIn(diff.offset, diff.value.length, sessionSec);
  }

  /** 便捷入口：直接给前后活文本，内部 diff（RichBodyController 的 onDidChange 路径） */
  syncText(prev: string, next: string, sessionSec: number | undefined): void {
    this.applyTextDiff(diffTextEdit(prev, next), sessionSec);
  }

  private spliceIn(offset: number, count: number, sessionSec: number | undefined): void {
    for (let i = 0; i < count; i++) {
      this.writtenAt.splice(offset + i, 0, sessionSec);
      this.struckAt.splice(offset + i, 0, undefined);
    }
  }

  /**
   * 范围里有没有干了的字（iOS `containsDryText`）：锚点占位符另算（照片 / 录音 /
   * 痕迹走块级 addedAt 判断），其余字符按自己的 writtenAt（没有按 `baseSec` =
   * 日记写下时刻）。`baseSec` 没有还在写的新稿一律不干（05 §3.4）。
   */
  containsDry(text: string, start: number, end: number,
    baseSec: number | undefined, nowSec: number): boolean {
    if (baseSec === undefined) {
      return false;
    }
    const hi = Math.min(end, text.length, this.writtenAt.length);
    for (let i = Math.max(0, start); i < hi; i++) {
      if (text.charCodeAt(i) === RICH_ANCHOR.charCodeAt(0)) {
        continue;
      }
      if (Ink.isDry(this.writtenAt[i], baseSec, nowSec)) {
        return true;
      }
    }
    return false;
  }

  /** 范围里有没有划掉不到 24 小时的（iOS `hasWetStrike`：能取消的划线） */
  hasWetStrike(start: number, end: number, nowSec: number): boolean {
    const hi = Math.min(end, this.struckAt.length);
    for (let i = Math.max(0, start); i < hi; i++) {
      const struck = this.struckAt[i];
      if (struck !== undefined && !Ink.isDry(struck, undefined, nowSec)) {
        return true;
      }
    }
    return false;
  }
}

/** 删除计划里每个字符的下场（R-INK-02） */
export enum InkDeleteOpKind {
  /** 干了的字：划掉（留着，变淡加删除线，记 struckAt） */
  Strike,
  /** 没干的字：照常删 */
  Delete,
  /** 不动：锚点（块级另算）、换行、已经划过的 */
  Keep
}

export class InkDeleteOp {
  readonly kind: InkDeleteOpKind;
  readonly offset: number;

  constructor(kind: InkDeleteOpKind, offset: number) {
    this.kind = kind;
    this.offset = offset;
  }
}

/**
 * R-INK-02「删除转划掉」的逐字符计划（iOS `replaceRespectingInk` 的纯函数版）：
 * 干的字划掉（换行 / 锚点 / 已划过的跳过），没干的照常删。
 * 基准时刻 `baseSec`（日记写下时刻）没有（还在写的新稿）时全部照常删。
 * 执行方从**后往前**应用（前段偏移不漂移）：Strike 重画单字符、Delete 定点删。
 */
export function planInkRespectingDelete(text: string, ledger: InkLedger,
  start: number, end: number, baseSec: number | undefined,
  nowSec: number): InkDeleteOp[] {
  const ops: InkDeleteOp[] = [];
  const lo = Math.max(0, start);
  const hi = Math.min(end, text.length, ledger.length);
  for (let i = lo; i < hi; i++) {
    const code = text.charCodeAt(i);
    if (code === RICH_ANCHOR.charCodeAt(0)) {
      ops.push(new InkDeleteOp(InkDeleteOpKind.Keep, i)); // 锚点：块级另算，不动
      continue;
    }
    if (!Ink.isDry(ledger.writtenAt[i], baseSec, nowSec)) {
      ops.push(new InkDeleteOp(InkDeleteOpKind.Delete, i));
      continue;
    }
    if (code === 0x0A || ledger.struckAt[i] !== undefined) {
      ops.push(new InkDeleteOp(InkDeleteOpKind.Keep, i)); // 干了的换行留着；划过的不再重划
      continue;
    }
    ops.push(new InkDeleteOp(InkDeleteOpKind.Strike, i));
  }
  return ops;
}

/**
 * 编辑器读回的纯视觉 spans 叠上墨迹台账 → 带全六项的 spans（Q24 的读回侧）：
 * 每个 span 内按台账的 writtenAt / struckAt 边界再切开，锚点 span 原样过。
 * 之后照旧走 `mergeAdjacentRichSpans` 合并。
 */
export function overlayInkOntoSpans(spans: RichSpan[], ledger: InkLedger): RichSpan[] {
  const result: RichSpan[] = [];
  let cursor = 0;
  for (const span of spans) {
    const len = span.text.length;
    if (span.anchorBlockId !== undefined) {
      result.push(span);
      cursor += len;
      continue;
    }
    let i = 0;
    while (i < len) {
      const w = cursor + i < ledger.length ? ledger.writtenAt[cursor + i] : undefined;
      const s = cursor + i < ledger.length ? ledger.struckAt[cursor + i] : undefined;
      let j = i + 1;
      while (j < len && cursor + j < ledger.length &&
        ledger.writtenAt[cursor + j] === w && ledger.struckAt[cursor + j] === s) {
        j++;
      }
      const flags = new RichFormatFlags(span.flags.bold, span.flags.italic, span.flags.heading,
        span.flags.highlight, w, s);
      result.push(new RichSpan(span.text.substring(i, j), flags));
      i = j;
    }
    cursor += len;
  }
  return result;
}
