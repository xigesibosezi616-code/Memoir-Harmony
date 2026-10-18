/**
 * 块 ↔ 编辑器文档的双向转换（10_BUILD_MANUAL.md 2.5）。对应 iOS `Views/Components/RichText/RichDocument.swift`。
 *
 * 编辑器侧的中间表示是「一整段文字 + 逐段格式」：
 * - `text`：整篇正文连成一段 UTF-16 字符串（换行、锚点都在里面）
 * - `spans`：按格式切开的连续区间，相邻区间格式必不同（平文区间也在内，
 *   覆盖满全篇 —— 编辑器装载时逐 span 注入样式，全靠它连续）
 *
 * **规则**（与 iOS 完全一致）：
 * - 相邻两个文本块是两段（中间补一个换行）
 * - 照片锚点（RICH_ANCHOR，U+FFFC）放在它后面那段文字的开头，文字与锚点同段；
 *   拆回去时照片前那个换行是拼接时补的，去掉
 * - 录音 / 痕迹锚点**自成一段**：前后各一个换行。拆回去时它前后那两个换行都是补的，去掉
 * - 找不到本体（anchored 里没有）的锚点不拆，锚点字符留在文字里（iOS 同款）
 *
 * 墨迹字段（writtenAt / struckAt，2.8 墨迹会干用）在模型层全程保留；
 * 2.5 编辑器还装不下它们（RichEditor 无自定义属性），2.8 接交互时补。
 */
import { ContentBlock, ContentBlockType, TextStyleRun } from './ContentBlock';

/** 锚点字符（U+FFFC）：照片 / 录音 / 痕迹块在正文流里的占位（本体在 anchored 侧表里） */
export const RICH_ANCHOR: string = String.fromCharCode(0xFFFC);

/**
 * 一段文字带哪几种格式。语义与 iOS `TextFlags` 一致：
 * 富文本里是这几个布尔 + 墨迹时刻，存盘时变成 `TextStyleRun`。
 */
export class RichFormatFlags {
  bold: boolean;
  italic: boolean;
  heading: boolean;
  highlight: boolean;
  /** 这段字什么时候写的（Unix 秒）。没写 = 日记写下时就有 */
  writtenAt: number | undefined;
  /** 什么时候划掉的（Unix 秒）。没划掉 = undefined */
  struckAt: number | undefined;

  constructor(bold: boolean = false, italic: boolean = false, heading: boolean = false,
    highlight: boolean = false, writtenAt: number | undefined = undefined,
    struckAt: number | undefined = undefined) {
    this.bold = bold;
    this.italic = italic;
    this.heading = heading;
    this.highlight = highlight;
    this.writtenAt = writtenAt;
    this.struckAt = struckAt;
  }

  /** 全空（六项都没）——存盘时这样的区间不进 `styles` */
  isPlain(): boolean {
    return !this.bold && !this.italic && !this.heading && !this.highlight &&
      this.writtenAt === undefined && this.struckAt === undefined;
  }

  /** 六项全等才叫同一种格式（相邻合并的判定） */
  sameAs(other: RichFormatFlags): boolean {
    return this.bold === other.bold && this.italic === other.italic &&
      this.heading === other.heading && this.highlight === other.highlight &&
      this.writtenAt === other.writtenAt && this.struckAt === other.struckAt;
  }
}

/**
 * 编辑器文档里的一段连续文字。
 * - 文本区间：`text` 是原文，`anchorBlockId` 为 undefined
 * - 锚点区间：`text` 恰一个 RICH_ANCHOR 字符，`anchorBlockId` 指向非文本块本体
 */
export class RichSpan {
  text: string;
  flags: RichFormatFlags;
  anchorBlockId: string | undefined;
  /** 锚点块的类型（判断照片不换行 / 录音痕迹要换行用） */
  anchorType: ContentBlockType | undefined;

  constructor(text: string, flags: RichFormatFlags, anchorBlockId: string | undefined = undefined,
    anchorType: ContentBlockType | undefined = undefined) {
    this.text = text;
    this.flags = flags;
    this.anchorBlockId = anchorBlockId;
    this.anchorType = anchorType;
  }
}

/** 编辑器文档：一整篇正文（UTF-16）+ 覆盖满全篇的连续格式区间 */
export class RichEditorDocument {
  text: string = '';
  spans: RichSpan[] = [];
}

/** 存盘区间（TextStyleRun）的六项语义是否全等（相邻合并判定用） */
function textStyleRunSameFlags(a: TextStyleRun, b: TextStyleRun): boolean {
  return a.bold === b.bold && a.italic === b.italic && a.heading === b.heading &&
    a.highlight === b.highlight && a.writtenAt === b.writtenAt && a.struckAt === b.struckAt;
}

function docEndsWithNewline(doc: RichEditorDocument): boolean {
  return doc.text.length > 0 && doc.text.charCodeAt(doc.text.length - 1) === 0x0A;
}

/** 末尾是不是照片锚点：照片后面的文字与锚点同段，不再补换行（iOS `endsWithPhotoAnchor`） */
function docEndsWithPhotoAnchor(doc: RichEditorDocument): boolean {
  const last: RichSpan | undefined = doc.spans.length > 0 ? doc.spans[doc.spans.length - 1] : undefined;
  return last !== undefined && last.anchorType === ContentBlockType.Photo;
}

function appendSpanToDoc(doc: RichEditorDocument, text: string, flags: RichFormatFlags): void {
  if (text.length === 0) {
    return;
  }
  doc.spans.push(new RichSpan(text, flags));
  doc.text += text;
}

/** 一个文本块的字符级格式 → 按格式切段，逐段追加进文档（含块内换行） */
function appendTextBlockToDoc(doc: RichEditorDocument, text: string, styles: TextStyleRun[] | undefined): void {
  if (text.length === 0) {
    return;
  }
  // 字符级格式表：默认平文（共享实例——本层只整体替换、从不改实例字段）
  const charFlags: RichFormatFlags[] = new Array<RichFormatFlags>(text.length);
  const plainFlags = new RichFormatFlags();
  for (let i = 0; i < text.length; i++) {
    charFlags[i] = plainFlags;
  }
  // 逐段套格式：区间越界 / 非正长度跳过（iOS guard 同款）；
  // 相互重叠的段后者整段覆盖前者（iOS setAttributes 同款）
  if (styles !== undefined) {
    for (const run of styles) {
      const location = run.location;
      const length = run.length;
      if (location < 0 || length <= 0 || location + length > text.length) {
        continue;
      }
      const runFlags = new RichFormatFlags(run.bold === true, run.italic === true,
        run.heading === true, run.highlight === true, run.writtenAt, run.struckAt);
      for (let i = location; i < location + length; i++) {
        charFlags[i] = runFlags;
      }
    }
  }
  // 格式相同的相邻字符合并成一段
  let start = 0;
  while (start < text.length) {
    const flags = charFlags[start];
    let end = start + 1;
    while (end < text.length && charFlags[end].sameAs(flags)) {
      end++;
    }
    appendSpanToDoc(doc, text.substring(start, end), flags);
    start = end;
  }
}

/**
 * 块列表里的非文本块（照片 / 录音 / 痕迹本体）按 id 建侧表：
 * `loadDocument(doc, anchored)` 装锚点、页面恢复草稿 / 日记时用它。
 */
export function anchoredBlocksOf(blocks: ContentBlock[]): Map<string, ContentBlock> {
  const map = new Map<string, ContentBlock>();
  for (const block of blocks) {
    if (block.type !== ContentBlockType.Text) {
      map.set(block.id, block);
    }
  }
  return map;
}

/**
 * 文本块在 `editorDocumentFromBlocks` 产出的 doc.text 里的区间
 * （编辑态光标 / 命中查询用：段内偏移 + 区间起点 = 全文档偏移）。
 */
export class TextBlockRange {
  /** 对应 blocks 下标（文本块） */
  blockIndex: number;
  /** 块文本在 doc.text 里的起点 */
  start: number;
  /** 块文本长度 */
  length: number;

  constructor(blockIndex: number, start: number, length: number) {
    this.blockIndex = blockIndex;
    this.start = start;
    this.length = length;
  }
}

/**
 * 与 `editorDocumentFromBlocks` 同步推演的文本块区间表（只算偏移，不建文档）。
 * 规则逐条对应：文本块前按需补 `\n`（段间 / 不以换行结尾且不在照片锚点后）、
 * 锚点块前补 `\n`、录音 / 痕迹锚点后补 `\n`。单测对二者做一致性校验。
 */
export function textBlockRangesOfBlocks(blocks: ContentBlock[]): TextBlockRange[] {
  const ranges: TextBlockRange[] = [];
  let cursor = 0; // 镜像 doc.text.length
  let endsWithNewline = false;
  let endsWithPhotoAnchor = false;
  for (let i = 0; i < blocks.length; i++) {
    const block = blocks[i];
    if (block.type === ContentBlockType.Text) {
      const text = block.text ?? '';
      if (cursor > 0 && !endsWithNewline && !endsWithPhotoAnchor && text.length > 0) {
        cursor += 1; // 补段间 \n
      }
      ranges.push(new TextBlockRange(i, cursor, text.length));
      cursor += text.length;
      // 空文本块不改 doc.text 末字符状态（fromBlocks 的 docEndsWithNewline 看全局末字符）
      if (text.length > 0) {
        endsWithNewline = text.charCodeAt(text.length - 1) === 0x0A;
      }
      endsWithPhotoAnchor = false;
      continue;
    }
    if (cursor > 0 && !endsWithNewline) {
      cursor += 1; // 锚点前补 \n
    }
    cursor += 1; // RICH_ANCHOR
    if (block.type === ContentBlockType.Audio || block.type === ContentBlockType.Trace) {
      cursor += 1; // 录音 / 痕迹后补 \n
      endsWithNewline = true;
    } else {
      endsWithNewline = false;
    }
    endsWithPhotoAnchor = block.type === ContentBlockType.Photo;
  }
  return ranges;
}

/**
 * 内容块 → 编辑器文档。照片 / 录音 / 痕迹块变成锚点字符，
 * 本体不进文字流（编辑器里怎么画是 2.6/2.7 的事，这层只管占位）。
 */
export function editorDocumentFromBlocks(blocks: ContentBlock[]): RichEditorDocument {
  const doc = new RichEditorDocument();
  for (const block of blocks) {
    if (block.type === ContentBlockType.Text) {
      const text = block.text ?? '';
      // 两个文本块之间是分段；照片后面紧跟的文字与锚点同段，不补
      if (doc.text.length > 0 && !docEndsWithNewline(doc) && !docEndsWithPhotoAnchor(doc) &&
        text.length > 0) {
        appendSpanToDoc(doc, '\n', new RichFormatFlags());
      }
      appendTextBlockToDoc(doc, text, block.styles);
      continue;
    }
    if (doc.text.length > 0 && !docEndsWithNewline(doc)) {
      appendSpanToDoc(doc, '\n', new RichFormatFlags());
    }
    doc.spans.push(new RichSpan(RICH_ANCHOR, new RichFormatFlags(), block.id, block.type));
    doc.text += RICH_ANCHOR;
    // 录音 / 痕迹自成一段：后面总跟一个换行，下面永远有一行能接着写
    if (block.type === ContentBlockType.Audio || block.type === ContentBlockType.Trace) {
      appendSpanToDoc(doc, '\n', new RichFormatFlags());
    }
  }
  return doc;
}

/**
 * 一段范围（相对 doc.text 的绝对 UTF-16 偏移）里的存盘格式区间：
 * 相对这段的开头、UTF-16 计、相邻且格式相同的合并、平文区间丢弃；空返回 undefined。
 */
function styleRunsForRange(doc: RichEditorDocument, start: number, end: number): TextStyleRun[] | undefined {
  const runs: TextStyleRun[] = [];
  let cursor = 0; // 逐 span 推进的绝对偏移（span 与 doc.text 逐字对齐）
  for (const span of doc.spans) {
    const spanEnd = cursor + span.text.length;
    if (spanEnd <= start) {
      cursor = spanEnd;
      continue;
    }
    if (cursor >= end) {
      break;
    }
    if (!span.flags.isPlain()) {
      const overlapStart = Math.max(cursor, start);
      const overlapEnd = Math.min(spanEnd, end);
      if (overlapEnd > overlapStart) {
        const run = new TextStyleRun(overlapStart - start, overlapEnd - overlapStart);
        const flags = span.flags;
        if (flags.bold) {
          run.bold = true;
        }
        if (flags.italic) {
          run.italic = true;
        }
        if (flags.heading) {
          run.heading = true;
        }
        if (flags.highlight) {
          run.highlight = true;
        }
        if (flags.writtenAt !== undefined) {
          run.writtenAt = flags.writtenAt;
        }
        if (flags.struckAt !== undefined) {
          run.struckAt = flags.struckAt;
        }
        // 相邻且格式相同的合并成一段
        const last: TextStyleRun | undefined = runs.length > 0 ? runs[runs.length - 1] : undefined;
        if (last !== undefined && last.location + last.length === run.location &&
          textStyleRunSameFlags(last, run)) {
          last.length += run.length;
        } else {
          runs.push(run);
        }
      }
    }
    cursor = spanEnd;
  }
  return runs.length > 0 ? runs : undefined;
}

function appendTextBlockForRange(doc: RichEditorDocument, blocks: ContentBlock[],
  start: number, end: number, makeId: () => string): void {
  if (end <= start) {
    return;
  }
  const block = ContentBlock.makeText(makeId(), doc.text.substring(start, end));
  const runs = styleRunsForRange(doc, start, end);
  if (runs !== undefined) {
    block.styles = runs;
  }
  blocks.push(block);
}

/**
 * 编辑器文档 → 内容块。`anchored` 是照片 / 录音 / 痕迹块的本体（按 id 找）；
 * 找不到的锚点不拆（锚点字符留在文字里，iOS 同款）。
 * 空文档保底一个空文本块（写日记页靠它判断「还没写」）。
 */
export function blocksWithEditorDocument(doc: RichEditorDocument,
  anchored: Map<string, ContentBlock>, makeId: () => string): ContentBlock[] {
  const blocks: ContentBlock[] = [];
  let segmentStart = 0;
  let cursor = 0; // 逐 span 推进的绝对偏移（span 与 doc.text 逐字对齐）
  for (const span of doc.spans) {
    if (span.anchorBlockId === undefined) {
      cursor += span.text.length;
      continue;
    }
    const anchorOffset = cursor;
    const anchoredBlock = anchored.get(span.anchorBlockId);
    cursor += span.text.length;
    if (anchoredBlock === undefined) {
      continue; // 本体不在侧表里：锚点留在文字里，随文字一起拆
    }
    // 锚点前那个换行是拼接时补的，去掉
    let textEnd = anchorOffset;
    if (textEnd > segmentStart && doc.text.charCodeAt(textEnd - 1) === 0x0A) {
      textEnd -= 1;
    }
    appendTextBlockForRange(doc, blocks, segmentStart, textEnd, makeId);
    blocks.push(anchoredBlock);
    segmentStart = anchorOffset + span.text.length;
    // 录音 / 痕迹后面那个换行也是补的，去掉
    if (anchoredBlock.type === ContentBlockType.Audio || anchoredBlock.type === ContentBlockType.Trace) {
      if (segmentStart < doc.text.length && doc.text.charCodeAt(segmentStart) === 0x0A) {
        segmentStart += 1;
      }
    }
  }
  appendTextBlockForRange(doc, blocks, segmentStart, doc.text.length, makeId);
  if (blocks.length === 0) {
    blocks.push(ContentBlock.makeText(makeId(), ''));
  }
  return blocks;
}

/**
 * R-RICH-03 在光标处插照片的落点计划。
 * `text` 是编辑器活文本（照片锚点各占 1 个 RICH_ANCHOR 字符），`caret` 先夹到 [0, len]：
 * - 光标在段尾（光标右一字符是换行）→ 锚点插到下一段开头，光标不动 —— 不凭空多出空行
 * - 光标在段首（文档开头 / 左一字符是换行）→ 挂这一段开头，光标落到照片后
 * - 段中 / 全文末尾 → 先断成两段（needsNewlineBefore），照片挂后一段开头
 */
export class PhotoInsertionPlan {
  /** 锚点插入处（相对活文本的 UTF-16 偏移；前置换行（若有）也从这里开始 */
  readonly insertOffset: number;
  /** 段中插入时先补一个换行把这段话断开 */
  readonly needsNewlineBefore: boolean;
  /** 插入完成后的光标落点（照片后接着写） */
  readonly caretAfter: number;

  constructor(insertOffset: number, needsNewlineBefore: boolean, caretAfter: number) {
    this.insertOffset = insertOffset;
    this.needsNewlineBefore = needsNewlineBefore;
    this.caretAfter = caretAfter;
  }
}

/** R-RICH-03 三分支的纯函数实现（iOS `RichTextView.insertPhoto` 同款规则） */
export function photoInsertionPlan(text: string, caretRaw: number): PhotoInsertionPlan {
  const len = text.length;
  const caret = Math.min(Math.max(caretRaw, 0), len);
  if (caret < len && text.charCodeAt(caret) === 0x0A) {
    // 段尾：挂在下一段开头（换行后），光标不动
    return new PhotoInsertionPlan(caret + 1, false, caret);
  }
  if (caret === 0 || text.charCodeAt(caret - 1) === 0x0A) {
    // 段首（含文档开头）：挂这一段开头，光标落到照片后面
    return new PhotoInsertionPlan(caret, false, caret + 1);
  }
  // 段中 / 全文末尾：断成两段，照片挂后一段开头，光标跟在照片后
  return new PhotoInsertionPlan(caret, true, caret + 2);
}

/**
 * R-RICH-04 在光标处插录音的落点计划（iOS `RichTextView.insertAudio` 同款规则）：
 * 录音插在光标所在段**下面**、自成一段（锚点 + 后随换行），不拆开这段话。
 * `text` 是编辑器活文本（照片 / 录音锚点各占 1 个 RICH_ANCHOR 字符）。
 */
export class AudioInsertionPlan {
  /** 锚点插入处（相对活文本的 UTF-16 偏移；前置换行（若有）也从这里开始 */
  readonly insertOffset: number;
  /** 录在最后一段且段尾没换行时，先补一个换行把录音与这段隔开 */
  readonly needsNewlineBefore: boolean;
  /** 插入完成后的光标落点（录在文末时落到录音下一行，否则光标不动） */
  readonly caretAfter: number;

  constructor(insertOffset: number, needsNewlineBefore: boolean, caretAfter: number) {
    this.insertOffset = insertOffset;
    this.needsNewlineBefore = needsNewlineBefore;
    this.caretAfter = caretAfter;
  }
}

/** R-RICH-04 的纯函数实现 */
export function audioInsertionPlan(text: string, caretRaw: number): AudioInsertionPlan {
  const len = text.length;
  const caret = Math.min(Math.max(caretRaw, 0), len);
  // 光标所在段的段尾（含收尾换行）：从光标往后找第一个换行
  let paragraphEnd = len;
  for (let i = caret; i < len; i++) {
    if (text.charCodeAt(i) === 0x0A) {
      paragraphEnd = i + 1;
      break;
    }
  }
  const atEnd = paragraphEnd >= len;
  // 段尾有换行：录音插在换行后面（下一段开头处自成一段）；
  // 录在最后一段且没有收尾换行：先补一个，再挂录音
  const needsNewlineBefore = atEnd && len > 0 && text.charCodeAt(len - 1) !== 0x0A;
  const insertOffset = atEnd ? len : paragraphEnd;
  // 光标：录在文末时移到录音下一行（前置换行 + 锚点 + 后随换行之后），否则不动
  const caretAfter = atEnd
    ? insertOffset + (needsNewlineBefore ? 1 : 0) + 2
    : caret;
  return new AudioInsertionPlan(insertOffset, needsNewlineBefore, caretAfter);
}

/** 相邻且格式相同的文本 span 合并（编辑器读回的区间可能切得比格式细） */
export function mergeAdjacentRichSpans(spans: RichSpan[]): RichSpan[] {
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
