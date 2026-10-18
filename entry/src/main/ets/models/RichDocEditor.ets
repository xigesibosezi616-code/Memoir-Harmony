/**
 * 字符级编辑算子（10_BUILD_MANUAL.md 2.5b，B1 隐形输入层方案）。
 *
 * 在 `RichEditorDocument`（`text` + `spans` 逐字对齐）上做插入 / 删除 / 样式替换，
 * 供隐形 `RichEditor` 的 IME 事件流驱动；块 ↔ 文档双向转换复用 `RichDocument`。
 *
 * 语义对齐 2.5 的 RichBodyController（iOS 同款）：
 * - 插入的新字继承插入点**左一字符**的格式（文档开头 = 平文）
 * - 删除命中照片 / 录音锚点（U+FFFC 单字符 span）不执行，返回 `anchor`
 *   由上层走「退格先选中再删」交互（R-RICH-06）
 * - 样式是**整段替换**（iOS `setAttributes`），做完相邻同格式合并
 */
import { ContentBlockType } from './ContentBlock';
import {
  RICH_ANCHOR,
  RichEditorDocument,
  RichFormatFlags,
  RichSpan
} from './RichDocument';

/** 删除结果：`ok` 已删 / `anchor` 命中锚点未删（上层走选中再删）/ `empty` 空范围 */
export type RichDocDeleteResult = 'ok' | 'anchor' | 'empty';

/** 文本 diff 种类：单点插入 / 单点删除；两头同时变（替换 / 多处变化）算 `complex` 交上层整建 */
export type TextEditDiffKind = 'none' | 'insert' | 'delete' | 'complex';

/** 隐形层前后文本的单点 diff 结果（B1 隐形输入层：系统改了隐形层 → diff → 同步编辑模型） */
export class TextEditDiff {
  readonly kind: TextEditDiffKind;
  /** 变化起点（prev 里的偏移；insert 时即插入点） */
  readonly offset: number;
  /** insert：插入串 */
  readonly value: string;
  /** delete：删除长度 */
  readonly length: number;

  constructor(kind: TextEditDiffKind, offset: number, value: string, length: number) {
    this.kind = kind;
    this.offset = offset;
    this.value = value;
    this.length = length;
  }
}

/**
 * 单点文本 diff：公共前缀 + 公共后缀夹出唯一变化区。
 * 插入（prev 变长）/ 删除（prev 变短）单点可表达；前后同时变返回 `complex`。
 * 隐形层组合输入（拼音逐键）是「删预览 + 插新预览」的连续两步，每步各自单点。
 */
export function diffTextEdit(prev: string, next: string): TextEditDiff {
  if (prev === next) {
    return new TextEditDiff('none', 0, '', 0);
  }
  const minLen = Math.min(prev.length, next.length);
  let prefix = 0;
  while (prefix < minLen && prev[prefix] === next[prefix]) {
    prefix++;
  }
  let suffix = 0;
  while (suffix < minLen - prefix &&
    prev[prev.length - 1 - suffix] === next[next.length - 1 - suffix]) {
    suffix++;
  }
  const deleted = prev.length - suffix - prefix;
  const inserted = next.length - suffix - prefix;
  if (deleted === 0 && inserted > 0) {
    return new TextEditDiff('insert', prefix, next.substring(prefix, prefix + inserted), 0);
  }
  if (inserted === 0 && deleted > 0) {
    return new TextEditDiff('delete', prefix, '', deleted);
  }
  return new TextEditDiff('complex', prefix, next.substring(prefix, prefix + inserted), deleted);
}

/**
 * 把 `spans` 在绝对偏移 `offset` 处切开（返回新数组；落在 span 边界不切）。
 * `offset` 夹到 [0, textLength]。
 */
function splitSpansAt(spans: RichSpan[], offset: number, textLength: number): RichSpan[] {
  const at = Math.min(Math.max(offset, 0), textLength);
  const result: RichSpan[] = [];
  let cursor = 0;
  for (const span of spans) {
    const spanEnd = cursor + span.text.length;
    if (at > cursor && at < spanEnd) {
      const left = new RichSpan(span.text.substring(0, at - cursor), span.flags,
        span.anchorBlockId, span.anchorType);
      const right = new RichSpan(span.text.substring(at - cursor), span.flags,
        span.anchorBlockId, span.anchorType);
      result.push(left, right);
    } else {
      result.push(span);
    }
    cursor = spanEnd;
  }
  return result;
}

/** 删除裁剪结果：裁剪后的 spans + 是否命中锚点（命中则整次删除不执行） */
class CropResult {
  readonly spans: RichSpan[];
  readonly hitsAnchor: boolean;

  constructor(spans: RichSpan[], hitsAnchor: boolean) {
    this.spans = spans;
    this.hitsAnchor = hitsAnchor;
  }
}

/** 绝对区间 [offset, offset+length) 与每个 span 的重叠裁剪（跨 span 删除）；锚点 span 相交返回 hitsAnchor */
function cropSpansRange(spans: RichSpan[], offset: number, length: number): CropResult {
  const start = Math.max(offset, 0);
  const end = Math.min(offset + Math.max(length, 0), spansLength(spans));
  const result: RichSpan[] = [];
  let hitsAnchor = false;
  let cursor = 0;
  for (const span of spans) {
    const spanEnd = cursor + span.text.length;
    if (spanEnd <= start || cursor >= end) {
      result.push(span);
      cursor = spanEnd;
      continue;
    }
    if (span.anchorBlockId !== undefined) {
      hitsAnchor = true; // 锚点字符被删区间覆盖：整次删除不执行
    }
    if (cursor < start) {
      result.push(new RichSpan(span.text.substring(0, start - cursor), span.flags,
        span.anchorBlockId, span.anchorType));
    }
    if (spanEnd > end) {
      result.push(new RichSpan(span.text.substring(end - cursor), span.flags,
        span.anchorBlockId, span.anchorType));
    }
    cursor = spanEnd;
  }
  return new CropResult(result, hitsAnchor);
}

function spansLength(spans: RichSpan[]): number {
  let total = 0;
  for (const span of spans) {
    total += span.text.length;
  }
  return total;
}

/** 相邻且格式相同的**文本** span 合并（锚点 span 不参与） */
function mergeAdjacentTextSpans(spans: RichSpan[]): RichSpan[] {
  const merged: RichSpan[] = [];
  for (const span of spans) {
    const last: RichSpan | undefined = merged.length > 0 ? merged[merged.length - 1] : undefined;
    if (last !== undefined && last.anchorBlockId === undefined && span.anchorBlockId === undefined &&
      last.flags.sameAs(span.flags)) {
      last.text += span.text;
    } else {
      merged.push(span);
    }
  }
  return merged;
}

/** 字符级编辑器（不可变文档进出；每次操作内部重建 spans，参考 RichEditorDocument 语义） */
export class RichDocEditor {
  private doc: RichEditorDocument;

  constructor(doc: RichEditorDocument) {
    this.doc = doc;
  }

  /** 当前全文档文本（UTF-16） */
  get text(): string {
    return this.doc.text;
  }

  /** 当前 spans（逐字对齐 text） */
  get spans(): RichSpan[] {
    return this.doc.spans;
  }

  /** 底层文档（拆回块用，交给 `blocksWithEditorDocument`） */
  get document(): RichEditorDocument {
    return this.doc;
  }

  /** 插入点左一字符的 flags（文档开头 = 平文；插入点在锚点后 = 平文） */
  private inheritedFlagsAt(offset: number): RichFormatFlags {
    if (offset <= 0) {
      return new RichFormatFlags();
    }
    let cursor = 0;
    for (const span of this.doc.spans) {
      const spanEnd = cursor + span.text.length;
      if (offset <= spanEnd) {
        return span.flags;
      }
      cursor = spanEnd;
    }
    return new RichFormatFlags();
  }

  /**
   * 插入文字：继承插入点左一字符的格式；`offset` 夹到 [0, length]。
   * 新字符落在锚点 span 内部时会被切开成独立文本 span（不会污染锚点本体）。
   */
  insert(offset: number, value: string): void {
    if (value.length === 0) {
      return;
    }
    const at = Math.min(Math.max(offset, 0), this.doc.text.length);
    const flags = this.inheritedFlagsAt(at);
    const split = splitSpansAt(this.doc.spans, at, this.doc.text.length);
    // 在切开处插入新 span：找到插入位（累计长度 == at 的 span 边界）
    const next: RichSpan[] = [];
    let cursor = 0;
    let inserted = false;
    for (const span of split) {
      if (!inserted && cursor === at) {
        next.push(new RichSpan(value, flags));
        inserted = true;
      }
      next.push(span);
      cursor += span.text.length;
    }
    if (!inserted) {
      next.push(new RichSpan(value, flags));
    }
    this.doc.spans = mergeAdjacentTextSpans(next);
    this.doc.text = this.doc.text.substring(0, at) + value + this.doc.text.substring(at);
  }

  /**
   * 插入块锚点（照片 / 录音 / 痕迹）：锚点单字符自成 span（平文）。
   * 与 `photoInsertionPlan` 配合用：先按需 `insert` 补换行，再 `insertAnchor`。
   */
  insertAnchor(offset: number, blockId: string, type: ContentBlockType): void {
    const at = Math.min(Math.max(offset, 0), this.doc.text.length);
    const split = splitSpansAt(this.doc.spans, at, this.doc.text.length);
    const next: RichSpan[] = [];
    let cursor = 0;
    let inserted = false;
    for (const span of split) {
      if (!inserted && cursor === at) {
        next.push(new RichSpan(RICH_ANCHOR, new RichFormatFlags(), blockId, type));
        inserted = true;
      }
      next.push(span);
      cursor += span.text.length;
    }
    if (!inserted) {
      next.push(new RichSpan(RICH_ANCHOR, new RichFormatFlags(), blockId, type));
    }
    this.doc.spans = next;
    this.doc.text = this.doc.text.substring(0, at) + RICH_ANCHOR + this.doc.text.substring(at);
  }

  /**
   * 删除 [offset, offset+length)：跨 span 裁剪。
   * 区间覆盖任何锚点字符 → 返回 `anchor` **不执行**（上层先选中锚点再删）；
   * 空范围 / 越界归零 → `empty`。
   */
  deleteRange(offset: number, length: number): RichDocDeleteResult {
    const start = Math.max(offset, 0);
    const end = Math.min(offset + Math.max(length, 0), this.doc.text.length);
    if (end <= start) {
      return 'empty';
    }
    const cropped = cropSpansRange(this.doc.spans, start, end - start);
    if (cropped.hitsAnchor) {
      return 'anchor';
    }
    this.doc.spans = mergeAdjacentTextSpans(cropped.spans);
    this.doc.text = this.doc.text.substring(0, start) + this.doc.text.substring(end);
    return 'ok';
  }

  /**
   * 样式整段替换（iOS `setAttributes` 语义）：[offset, offset+length) 内全部字符设为 `flags`，
   * 边界处切开 spans；做完相邻同格式合并。锚点 span 不参与（保持平文本体）。
   */
  applyFlags(offset: number, length: number, flags: RichFormatFlags): void {
    const s = Math.max(offset, 0);
    const e = Math.min(offset + Math.max(length, 0), this.doc.text.length);
    if (e <= s) {
      return;
    }
    const head = splitSpansAt(this.doc.spans, s, this.doc.text.length);
    const tail = splitSpansAt(head, e, this.doc.text.length);
    const next: RichSpan[] = [];
    let cursor = 0;
    for (const span of tail) {
      const spanEnd = cursor + span.text.length;
      if (spanEnd > s && cursor < e && span.anchorBlockId === undefined) {
        next.push(new RichSpan(span.text, flags));
      } else {
        next.push(span);
      }
      cursor = spanEnd;
    }
    this.doc.spans = mergeAdjacentTextSpans(next);
  }

  /** 某偏移字符的 flags（越界取边界） */
  flagsAt(offset: number): RichFormatFlags {
    const at = Math.min(Math.max(offset, 0), Math.max(this.doc.text.length - 1, 0));
    let cursor = 0;
    for (const span of this.doc.spans) {
      const spanEnd = cursor + span.text.length;
      if (at < spanEnd) {
        return span.flags;
      }
      cursor = spanEnd;
    }
    return new RichFormatFlags();
  }
}
