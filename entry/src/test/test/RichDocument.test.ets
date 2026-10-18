/**
 * 块 ↔ 编辑器文档双向转换单测（10_BUILD_MANUAL.md 2.5）。
 * 对齐 iOS `RichDocumentTests`：锚点拼接 / 拆分规则、格式区间保留、越界容错、幂等。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  ContentBlock,
  ContentBlockType,
  PaperStyle,
  PhotoPosition,
  TextStyleRun
} from '../../main/ets/models/ContentBlock';
import {
  RICH_ANCHOR,
  RichFormatFlags,
  RichSpan,
  TextBlockRange,
  audioInsertionPlan,
  blocksWithEditorDocument,
  editorDocumentFromBlocks,
  mergeAdjacentRichSpans,
  photoInsertionPlan,
  textBlockRangesOfBlocks
} from '../../main/ets/models/RichDocument';

let idCounter = 0;
function makeId(): string {
  idCounter++;
  return `richdoc-test-${idCounter}`;
}

function textBlock(text: string): ContentBlock {
  return ContentBlock.makeText(makeId(), text);
}

function photoBlock(): ContentBlock {
  return ContentBlock.makePhoto(makeId(), 'p.jpg', undefined,
    PhotoPosition.Left, PaperStyle.Original);
}

function audioBlock(): ContentBlock {
  return ContentBlock.makeAudio(makeId(), 'audio/a.m4a');
}

/** 把块列表按 id 建侧表（blocksWithEditorDocument 的锚点本体） */
function anchoredMap(blocks: ContentBlock[]): Map<string, ContentBlock> {
  const map = new Map<string, ContentBlock>();
  for (const block of blocks) {
    if (block.type !== ContentBlockType.Text) {
      map.set(block.id, block);
    }
  }
  return map;
}

/**
 * textBlockRangesOfBlocks 一致性不变量（与 editorDocumentFromBlocks 同步推演）：
 * 1. 区间数 = 文本块数，每个区间在 doc.text 里的切片 === 块原文
 * 2. 不属于任何区间的字符（间隙）全部是 '\n' 或 RICH_ANCHOR
 */
function expectRangesConsistent(blocks: ContentBlock[]): void {
  const doc = editorDocumentFromBlocks(blocks);
  const ranges = textBlockRangesOfBlocks(blocks);
  let textBlockCount = 0;
  for (const block of blocks) {
    if (block.type === ContentBlockType.Text) {
      textBlockCount++;
    }
  }
  expect(ranges.length).assertEqual(textBlockCount);
  const covered = new Array<boolean>(doc.text.length).fill(false);
  let r = 0;
  for (const block of blocks) {
    if (block.type !== ContentBlockType.Text) {
      continue;
    }
    const range = ranges[r];
    r++;
    expect(range.blockIndex).assertEqual(blocks.indexOf(block));
    const slice = doc.text.substring(range.start, range.start + range.length);
    expect(slice).assertEqual(block.text ?? '');
    for (let i = range.start; i < range.start + range.length; i++) {
      covered[i] = true;
    }
  }
  for (let i = 0; i < doc.text.length; i++) {
    if (covered[i]) {
      continue;
    }
    const ch = doc.text[i];
    expect(ch === '\n' || ch === RICH_ANCHOR).assertTrue();
  }
}

/** doc.spans 的文本拼起来必须等于 doc.text（区间连续且覆盖满全篇） */
function expectSpansCoverText(docText: string, spans: RichSpan[]): void {
  let joined = '';
  for (const span of spans) {
    joined += span.text;
  }
  expect(joined).assertEqual(docText);
}

export default function richDocumentTest() {
  describe('RichDocumentTest', () => {
    // ---- 块 → 文档 ----

    it('emptyBlocksGiveEmptyDocument', 0, () => {
      const doc = editorDocumentFromBlocks([]);
      expect(doc.text).assertEqual('');
      expect(doc.spans.length).assertEqual(0);
    })

    it('plainTextBlockBecomesSingleSpan', 0, () => {
      const doc = editorDocumentFromBlocks([textBlock('今天天气很好')]);
      expect(doc.text).assertEqual('今天天气很好');
      expect(doc.spans.length).assertEqual(1);
      expect(doc.spans[0].text).assertEqual('今天天气很好');
      expect(doc.spans[0].flags.isPlain()).assertTrue();
      expect(doc.spans[0].anchorBlockId).assertUndefined();
    })

    it('twoTextBlocksJoinedWithNewline', 0, () => {
      // 相邻两个文本块是两段（中间补一个换行）
      const doc = editorDocumentFromBlocks([textBlock('ab'), textBlock('cd')]);
      expect(doc.text).assertEqual('ab\ncd');
      expectSpansCoverText(doc.text, doc.spans);
    })

    it('textBlockNewlineInsideStaysOneSpan', 0, () => {
      // 块内换行是文字的一部分（老 iOS 纯文本正文就是这种）
      const doc = editorDocumentFromBlocks([textBlock('a\nb')]);
      expect(doc.text).assertEqual('a\nb');
      expect(doc.spans.length).assertEqual(1);
      expect(doc.spans[0].text).assertEqual('a\nb');
    })

    it('styleRunsBecomeFlaggedSpans', 0, () => {
      const block = textBlock('abcdef');
      const boldRun = new TextStyleRun(0, 2);
      boldRun.bold = true;
      const hlRun = new TextStyleRun(3, 2);
      hlRun.highlight = true;
      block.styles = [boldRun, hlRun];
      const doc = editorDocumentFromBlocks([block]);
      expect(doc.text).assertEqual('abcdef');
      expectSpansCoverText(doc.text, doc.spans);
      expect(doc.spans.length).assertEqual(4);
      expect(doc.spans[0].text).assertEqual('ab');
      expect(doc.spans[0].flags.bold).assertTrue();
      expect(doc.spans[1].text).assertEqual('c');
      expect(doc.spans[1].flags.isPlain()).assertTrue();
      expect(doc.spans[2].text).assertEqual('de');
      expect(doc.spans[2].flags.highlight).assertTrue();
      expect(doc.spans[3].text).assertEqual('f');
      expect(doc.spans[3].flags.isPlain()).assertTrue();
    })

    it('overlappingRunsLaterWins', 0, () => {
      // 相互重叠的段后者整段覆盖前者（iOS setAttributes 同款）
      const block = textBlock('abcde');
      const boldRun = new TextStyleRun(0, 5);
      boldRun.bold = true;
      const italicRun = new TextStyleRun(2, 2);
      italicRun.italic = true;
      block.styles = [boldRun, italicRun];
      const doc = editorDocumentFromBlocks([block]);
      expect(doc.spans.length).assertEqual(3);
      expect(doc.spans[0].text).assertEqual('ab');
      expect(doc.spans[0].flags.bold).assertTrue();
      expect(doc.spans[0].flags.italic).assertFalse();
      expect(doc.spans[1].text).assertEqual('cd');
      expect(doc.spans[1].flags.bold).assertFalse();
      expect(doc.spans[1].flags.italic).assertTrue();
      expect(doc.spans[2].text).assertEqual('e');
      expect(doc.spans[2].flags.bold).assertTrue();
    })

    it('outOfRangeRunsSkipped', 0, () => {
      const block = textBlock('abc');
      const beyond = new TextStyleRun(2, 5);
      beyond.bold = true;
      const negative = new TextStyleRun(-1, 2);
      negative.italic = true;
      const zero = new TextStyleRun(0, 0);
      zero.heading = true;
      block.styles = [beyond, negative, zero];
      const doc = editorDocumentFromBlocks([block]);
      expect(doc.spans.length).assertEqual(1);
      expect(doc.spans[0].flags.isPlain()).assertTrue();
    })

    it('inkTimestampsCarriedThroughDocument', 0, () => {
      // 墨迹时刻（writtenAt / struckAt）在模型层全程保留（2.8 墨迹会干用）
      const block = textBlock('abcd');
      const old = new TextStyleRun(0, 2);
      old.writtenAt = 100;
      old.struckAt = 200;
      const fresh = new TextStyleRun(2, 2);
      fresh.writtenAt = 300;
      block.styles = [old, fresh];
      const doc = editorDocumentFromBlocks([block]);
      expect(doc.spans.length).assertEqual(2);
      expect(doc.spans[0].flags.writtenAt).assertEqual(100);
      expect(doc.spans[0].flags.struckAt).assertEqual(200);
      expect(doc.spans[1].flags.writtenAt).assertEqual(300);
      expect(doc.spans[1].flags.struckAt).assertUndefined();
    })

    // ---- 锚点拼接 ----

    it('photoAnchorFollowsTextWithoutNewline', 0, () => {
      // 照片锚点独占一行（前补换行），后面紧跟的文字与锚点同段（不再补换行）
      const blocks = [textBlock('ab'), photoBlock(), textBlock('cd')];
      const doc = editorDocumentFromBlocks(blocks);
      expect(doc.text).assertEqual(`ab\n${RICH_ANCHOR}cd`);
      expectSpansCoverText(doc.text, doc.spans);
      const anchorSpan = doc.spans.find(span => span.anchorBlockId !== undefined);
      expect(anchorSpan !== undefined).assertTrue();
      expect(anchorSpan?.anchorType).assertEqual(ContentBlockType.Photo);
    })

    it('photoAtStartHasNoLeadingNewline', 0, () => {
      const blocks = [photoBlock(), textBlock('x')];
      const doc = editorDocumentFromBlocks(blocks);
      expect(doc.text).assertEqual(`${RICH_ANCHOR}x`);
    })

    it('audioAnchorIsOwnParagraph', 0, () => {
      // 录音自成一段：前后各一个换行
      const blocks = [textBlock('a'), audioBlock(), textBlock('b')];
      const doc = editorDocumentFromBlocks(blocks);
      expect(doc.text).assertEqual(`a\n${RICH_ANCHOR}\nb`);
      expectSpansCoverText(doc.text, doc.spans);
    })

    it('audioAtDocumentEndKeepsTrailingNewline', 0, () => {
      const blocks = [textBlock('a'), audioBlock()];
      const doc = editorDocumentFromBlocks(blocks);
      expect(doc.text).assertEqual(`a\n${RICH_ANCHOR}\n`);
    })

    it('traceAnchorIsOwnParagraphLikeAudio', 0, () => {
      const trace = ContentBlock.makeTrace(makeId(), ContentBlockType.Photo, 123);
      const blocks = [textBlock('a'), trace];
      const doc = editorDocumentFromBlocks(blocks);
      expect(doc.text).assertEqual(`a\n${RICH_ANCHOR}\n`);
    })

    // ---- 文档 → 块 ----

    it('roundTripPlainBlocksMergeAdjacentText', 0, () => {
      // 相邻文本块只在锚点处切分：round-trip 后合并成一块
      const original = [textBlock('ab'), textBlock('cd')];
      const doc = editorDocumentFromBlocks(original);
      const back = blocksWithEditorDocument(doc, new Map<string, ContentBlock>(), makeId);
      expect(back.length).assertEqual(1);
      expect(back[0].type).assertEqual(ContentBlockType.Text);
      expect(back[0].text).assertEqual('ab\ncd');
      expect(back[0].styles).assertUndefined();
    })

    it('roundTripPreservesStyleRuns', 0, () => {
      const block = textBlock('abcdef');
      const boldRun = new TextStyleRun(0, 2);
      boldRun.bold = true;
      const hlRun = new TextStyleRun(3, 2);
      hlRun.highlight = true;
      block.styles = [boldRun, hlRun];
      const doc = editorDocumentFromBlocks([block]);
      const back = blocksWithEditorDocument(doc, new Map<string, ContentBlock>(), makeId);
      expect(back.length).assertEqual(1);
      expect(back[0].text).assertEqual('abcdef');
      const styles = back[0].styles!;
      expect(styles.length).assertEqual(2);
      expect(styles[0].location).assertEqual(0);
      expect(styles[0].length).assertEqual(2);
      expect(styles[0].bold).assertTrue();
      expect(styles[1].location).assertEqual(3);
      expect(styles[1].length).assertEqual(2);
      expect(styles[1].highlight).assertTrue();
    })

    it('roundTripPreservesInkTimestamps', 0, () => {
      const block = textBlock('abcd');
      const run = new TextStyleRun(1, 2);
      run.writtenAt = 100;
      run.struckAt = 200;
      block.styles = [run];
      const doc = editorDocumentFromBlocks([block]);
      const back = blocksWithEditorDocument(doc, new Map<string, ContentBlock>(), makeId);
      const styles = back[0].styles!;
      expect(styles.length).assertEqual(1);
      expect(styles[0].location).assertEqual(1);
      expect(styles[0].length).assertEqual(2);
      expect(styles[0].writtenAt).assertEqual(100);
      expect(styles[0].struckAt).assertEqual(200);
    })

    it('roundTripAdjacentSameFlagsRunsMerge', 0, () => {
      // 相邻且格式相同的存盘区间合并成一段
      const block = textBlock('abcd');
      const r1 = new TextStyleRun(0, 2);
      r1.bold = true;
      const r2 = new TextStyleRun(2, 2);
      r2.bold = true;
      block.styles = [r1, r2];
      const doc = editorDocumentFromBlocks([block]);
      const back = blocksWithEditorDocument(doc, new Map<string, ContentBlock>(), makeId);
      const styles = back[0].styles!;
      expect(styles.length).assertEqual(1);
      expect(styles[0].location).assertEqual(0);
      expect(styles[0].length).assertEqual(4);
    })

    it('roundTripPhotoSplitsTextAtAnchor', 0, () => {
      const blocks = [textBlock('ab'), photoBlock(), textBlock('cd')];
      const photo = blocks[1];
      const doc = editorDocumentFromBlocks(blocks);
      const back = blocksWithEditorDocument(doc, anchoredMap(blocks), makeId);
      expect(back.length).assertEqual(3);
      expect(back[0].type).assertEqual(ContentBlockType.Text);
      expect(back[0].text).assertEqual('ab');
      expect(back[1].id).assertEqual(photo.id);
      expect(back[1].type).assertEqual(ContentBlockType.Photo);
      expect(back[2].type).assertEqual(ContentBlockType.Text);
      expect(back[2].text).assertEqual('cd');
    })

    it('roundTripAudioDropsBothInjectedNewlines', 0, () => {
      const blocks = [textBlock('a'), audioBlock(), textBlock('b')];
      const audio = blocks[1];
      const doc = editorDocumentFromBlocks(blocks);
      const back = blocksWithEditorDocument(doc, anchoredMap(blocks), makeId);
      expect(back.length).assertEqual(3);
      expect(back[0].text).assertEqual('a');
      expect(back[1].id).assertEqual(audio.id);
      expect(back[2].text).assertEqual('b');
    })

    it('roundTripAudioAtEndHasNoTrailingText', 0, () => {
      const blocks = [textBlock('a'), audioBlock()];
      const doc = editorDocumentFromBlocks(blocks);
      const back = blocksWithEditorDocument(doc, anchoredMap(blocks), makeId);
      expect(back.length).assertEqual(2);
      expect(back[0].text).assertEqual('a');
      expect(back[1].type).assertEqual(ContentBlockType.Audio);
    })

    it('unresolvableAnchorStaysInText', 0, () => {
      // 本体不在侧表里：锚点字符留在文字里，不拆（iOS 同款前向兼容）
      const blocks = [textBlock('ab'), photoBlock(), textBlock('cd')];
      const doc = editorDocumentFromBlocks(blocks);
      const back = blocksWithEditorDocument(doc, new Map<string, ContentBlock>(), makeId);
      expect(back.length).assertEqual(1);
      expect(back[0].type).assertEqual(ContentBlockType.Text);
      expect(back[0].text).assertEqual(`ab\n${RICH_ANCHOR}cd`);
    })

    it('styleRangeSpansAcrossAnchorBoundary', 0, () => {
      // 样式区间只落在锚点前的文字里：拆回去时按锚点切开，样式跟着各自的文字走
      const blocks = [textBlock('ab'), photoBlock(), textBlock('cd')];
      const boldRun = new TextStyleRun(0, 2);
      boldRun.bold = true;
      blocks[0].styles = [boldRun];
      const doc = editorDocumentFromBlocks(blocks);
      const back = blocksWithEditorDocument(doc, anchoredMap(blocks), makeId);
      expect(back.length).assertEqual(3);
      expect(back[0].text).assertEqual('ab');
      expect(back[0].styles!.length).assertEqual(1);
      expect(back[0].styles![0].bold).assertTrue();
      expect(back[2].text).assertEqual('cd');
      expect(back[2].styles).assertUndefined();
    })

    it('emptyDocumentFallsBackToSingleEmptyTextBlock', 0, () => {
      // 空文档保底一个空文本块（写日记页靠它判断「还没写」）
      const doc = editorDocumentFromBlocks([]);
      const back = blocksWithEditorDocument(doc, new Map<string, ContentBlock>(), makeId);
      expect(back.length).assertEqual(1);
      expect(back[0].type).assertEqual(ContentBlockType.Text);
      expect(back[0].text).assertEqual('');
    })

    it('conversionIsIdempotent', 0, () => {
      // 转过去再转回来，文档完全一致（幂等）：编辑器刷新 / 保存来回跑不会漂
      const block = textBlock('abc');
      const boldRun = new TextStyleRun(0, 3);
      boldRun.bold = true;
      block.styles = [boldRun];
      const blocks = [block, photoBlock(), textBlock('de')];
      const doc1 = editorDocumentFromBlocks(blocks);
      const back1 = blocksWithEditorDocument(doc1, anchoredMap(blocks), makeId);
      const doc2 = editorDocumentFromBlocks(back1);
      expect(doc2.text).assertEqual(doc1.text);
      expect(doc2.spans.length).assertEqual(doc1.spans.length);
      for (let i = 0; i < doc2.spans.length; i++) {
        expect(doc2.spans[i].text).assertEqual(doc1.spans[i].text);
        expect(doc2.spans[i].anchorBlockId).assertEqual(doc1.spans[i].anchorBlockId);
        expect(doc2.spans[i].flags.sameAs(doc1.spans[i].flags)).assertTrue();
      }
      const back2 = blocksWithEditorDocument(doc2, anchoredMap(blocks), makeId);
      expect(back2.length).assertEqual(back1.length);
      for (let i = 0; i < back2.length; i++) {
        expect(back2[i].type).assertEqual(back1[i].type);
        expect(back2[i].text ?? '').assertEqual(back1[i].text ?? '');
      }
    })

    // ---- mergeAdjacentRichSpans ----

    it('mergeAdjacentPlainSpans', 0, () => {
      const spans = [
        new RichSpan('ab', new RichFormatFlags()),
        new RichSpan('cd', new RichFormatFlags())
      ];
      const merged = mergeAdjacentRichSpans(spans);
      expect(merged.length).assertEqual(1);
      expect(merged[0].text).assertEqual('abcd');
    })

    it('mergeOnlySameFlags', 0, () => {
      const bold = new RichFormatFlags();
      bold.bold = true;
      const spans = [
        new RichSpan('ab', bold),
        new RichSpan('cd', new RichFormatFlags()),
        new RichSpan('ef', new RichFormatFlags())
      ];
      const merged = mergeAdjacentRichSpans(spans);
      expect(merged.length).assertEqual(2);
      expect(merged[0].text).assertEqual('ab');
      expect(merged[1].text).assertEqual('cdef');
    })

    it('mergeSkipsAnchorSpans', 0, () => {
      const spans = [
        new RichSpan('ab', new RichFormatFlags()),
        new RichSpan(RICH_ANCHOR, new RichFormatFlags(), 'p1', ContentBlockType.Photo),
        new RichSpan('cd', new RichFormatFlags())
      ];
      const merged = mergeAdjacentRichSpans(spans);
      expect(merged.length).assertEqual(3);
      expect(merged[0].text).assertEqual('ab');
      expect(merged[1].anchorBlockId).assertEqual('p1');
      expect(merged[2].text).assertEqual('cd');
    })

    // ---- R-RICH-03 插照落点（photoInsertionPlan） ----

    it('insertAtParagraphEndHangsOnNextParagraph', 0, () => {
      // 光标在段尾（右一字符是换行）：挂到下一段开头，光标不动
      const text = '第一段\n第二段';
      const plan = photoInsertionPlan(text, 3);
      expect(plan.insertOffset).assertEqual(4);
      expect(plan.needsNewlineBefore).assertFalse();
      expect(plan.caretAfter).assertEqual(3);
    })

    it('insertAtParagraphStartHangsOnThisParagraph', 0, () => {
      // 光标在段首（左一字符是换行）：挂这一段开头，光标落到照片后
      const text = '第一段\n第二段';
      const plan = photoInsertionPlan(text, 4);
      expect(plan.insertOffset).assertEqual(4);
      expect(plan.needsNewlineBefore).assertFalse();
      expect(plan.caretAfter).assertEqual(5);
    })

    it('insertAtDocumentStartHangsOnFirstParagraph', 0, () => {
      // 文档开头：挂第一段开头
      const plan = photoInsertionPlan('正文', 0);
      expect(plan.insertOffset).assertEqual(0);
      expect(plan.needsNewlineBefore).assertFalse();
      expect(plan.caretAfter).assertEqual(1);
    })

    it('insertMidParagraphSplitsIntoTwo', 0, () => {
      // 段中：断成两段，照片挂后一段开头，光标跟在照片后
      const text = 'abcdef';
      const plan = photoInsertionPlan(text, 3);
      expect(plan.insertOffset).assertEqual(3);
      expect(plan.needsNewlineBefore).assertTrue();
      expect(plan.caretAfter).assertEqual(5);
    })

    it('insertAtDocumentEndAppendsAfterSplit', 0, () => {
      // 全文末尾（左一字符不是换行）：同段中分支，末尾断段追加
      const plan = photoInsertionPlan('abcdef', 6);
      expect(plan.insertOffset).assertEqual(6);
      expect(plan.needsNewlineBefore).assertTrue();
      expect(plan.caretAfter).assertEqual(8);
    })

    it('insertCaretIsClamped', 0, () => {
      // 光标越界先夹回 [0, len]，不抛不炸
      const plan = photoInsertionPlan('abc', 99);
      expect(plan.insertOffset).assertEqual(3);
      const planBefore = photoInsertionPlan('abc', -1);
      expect(planBefore.insertOffset).assertEqual(0);
    })

    it('insertAfterTrailingAnchorAtEndSplits', 0, () => {
      // 末尾已是照片锚点、光标在其后：走段中分支，新照片另起一段
      const text = `一段话\n${RICH_ANCHOR}`;
      const plan = photoInsertionPlan(text, text.length);
      expect(plan.insertOffset).assertEqual(text.length);
      expect(plan.needsNewlineBefore).assertTrue();
    })

    it('insertWhenNextCharIsAnchorFollowsParagraphRule', 0, () => {
      // 光标右一字符是锚点（不是换行）：不属段尾分支，按段中/段首规则走
      const text = `ab\n${RICH_ANCHOR}cd`;
      const planAtAnchorStart = photoInsertionPlan(text, 3);
      // 段首分支：左一字符是换行 → 挂这段开头（锚点前面）
      expect(planAtAnchorStart.insertOffset).assertEqual(3);
      expect(planAtAnchorStart.needsNewlineBefore).assertFalse();
    })

    // ---- R-RICH-04 录音落点（audioInsertionPlan，iOS insertAudio 同款规则） ----

    it('audioMidParagraphInsertsBelowIt', 0, () => {
      // 光标在段中：录音插到这一段下面（换行后自成一段），光标不动
      const text = '第一段\n第二段';
      const plan = audioInsertionPlan(text, 2);
      expect(plan.insertOffset).assertEqual(4); // 第一段的换行后（第二段开头前）
      expect(plan.needsNewlineBefore).assertFalse();
      expect(plan.caretAfter).assertEqual(2); // 光标留在原地
    })

    it('audioAtParagraphEndFollowsNewline', 0, () => {
      // 光标在段尾（右一字符是换行）：录音挂换行后面，光标不动
      const plan = audioInsertionPlan('ab\ncd', 2);
      expect(plan.insertOffset).assertEqual(3);
      expect(plan.needsNewlineBefore).assertFalse();
      expect(plan.caretAfter).assertEqual(2);
    })

    it('audioAtDocumentEndWithoutNewlinePrependsOne', 0, () => {
      // 录在最后一段且段尾没换行：先补换行隔开，光标落到录音下一行
      const plan = audioInsertionPlan('abcdef', 6);
      expect(plan.insertOffset).assertEqual(6);
      expect(plan.needsNewlineBefore).assertTrue();
      expect(plan.caretAfter).assertEqual(9); // 6 + 前置换行 1 + 锚点 1 + 后随换行 1
    })

    it('audioAtDocumentEndWithTrailingNewlineNeedsNoPrefix', 0, () => {
      // 文档末尾已有收尾换行：直接挂末尾，光标落到录音下一行
      const plan = audioInsertionPlan('abc\n', 4);
      expect(plan.insertOffset).assertEqual(4);
      expect(plan.needsNewlineBefore).assertFalse();
      expect(plan.caretAfter).assertEqual(6);
    })

    it('audioIntoEmptyDocument', 0, () => {
      // 空文档：录音直接挂开头，光标落到录音下一行
      const plan = audioInsertionPlan('', 0);
      expect(plan.insertOffset).assertEqual(0);
      expect(plan.needsNewlineBefore).assertFalse();
      expect(plan.caretAfter).assertEqual(2);
    })

    it('audioCaretIsClamped', 0, () => {
      // 光标越界先夹回 [0, len]：超长落到文末（补换行挂录音），负数落到段首（挂本段换行后）
      const planOver = audioInsertionPlan('ab\ncd', 99);
      expect(planOver.insertOffset).assertEqual(5);
      expect(planOver.needsNewlineBefore).assertTrue();
      const planUnder = audioInsertionPlan('ab\ncd', -1);
      expect(planUnder.insertOffset).assertEqual(3);
      expect(planUnder.needsNewlineBefore).assertFalse();
    })

    it('roundTripMixedPhotoAndAudioKeepsOrderAndIds', 0, () => {
      // 照片 + 录音混排：文档拼装 → 拆回，顺序与锚点 id 全保留（2.7 统一锚点）；
      // 文本块每次拆装拿新 id（实现如此），只比对文字内容
      const t1 = textBlock('前文');
      const photo = photoBlock();
      const t2 = textBlock('中间');
      const audio = audioBlock();
      const t3 = textBlock('后文');
      const blocks = [t1, photo, t2, audio, t3];
      const doc = editorDocumentFromBlocks(blocks);
      const out = blocksWithEditorDocument(doc, anchoredMap(blocks), makeId);
      expect(out.length).assertEqual(5);
      expect(out[0].type).assertEqual(ContentBlockType.Text);
      expect(out[0].text).assertEqual('前文');
      expect(out[1].id).assertEqual(photo.id);
      expect(out[1].type).assertEqual(ContentBlockType.Photo);
      expect(out[2].type).assertEqual(ContentBlockType.Text);
      expect(out[2].text).assertEqual('中间');
      expect(out[3].id).assertEqual(audio.id);
      expect(out[3].type).assertEqual(ContentBlockType.Audio);
      expect(out[4].type).assertEqual(ContentBlockType.Text);
      expect(out[4].text).assertEqual('后文');
      expectRangesConsistent(out);
    })

    it('roundTripTraceKeepsIdAndMetadata', 0, () => {
      // 痕迹块（2.8）：干了的照片取下后留在原处的记录 ——
      // 拼装 → 拆回 id / traceOf / removedAt 全保留，普通文本不受影响
      const t1 = textBlock('前文');
      const trace = ContentBlock.makeTrace(makeId(), ContentBlockType.Photo, 12345);
      const t2 = textBlock('后文');
      const blocks = [t1, trace, t2];
      const doc = editorDocumentFromBlocks(blocks);
      const out = blocksWithEditorDocument(doc, anchoredMap(blocks), makeId);
      expect(out.length).assertEqual(3);
      expect(out[0].type).assertEqual(ContentBlockType.Text);
      expect(out[0].text).assertEqual('前文');
      expect(out[1].id).assertEqual(trace.id);
      expect(out[1].type).assertEqual(ContentBlockType.Trace);
      expect(out[1].traceOf).assertEqual(ContentBlockType.Photo as string);
      expect(out[1].removedAt).assertEqual(12345);
      expect(out[2].type).assertEqual(ContentBlockType.Text);
      expect(out[2].text).assertEqual('后文');
      expectRangesConsistent(out);
    })
  })

  describe('textBlockRangesOfBlocks', () => {
    it('rangesMatchPlainParagraphs', 0, () => {
      expectRangesConsistent([textBlock('第一段'), textBlock('第二段')]);
    })

    it('rangesMatchPhotoBetweenTexts', 0, () => {
      expectRangesConsistent([textBlock('前文'), photoBlock(), textBlock('后文')]);
    })

    it('rangesMatchAudioAndTrace', 0, () => {
      const trace = ContentBlock.makeTrace(makeId(), ContentBlockType.Photo, 12);
      expectRangesConsistent([textBlock('a'), audioBlock(), textBlock('b'), trace, textBlock('c')]);
    })

    it('rangesMatchEmptyAndNewlineEnding', 0, () => {
      expectRangesConsistent([textBlock('段尾换行\n'), textBlock(''), textBlock('x')]);
    })

    it('rangesMatchAnchorOnlyAndEmptyDoc', 0, () => {
      expectRangesConsistent([photoBlock()]);
      expectRangesConsistent([]);
      expectRangesConsistent([textBlock('')]);
    })

    it('rangesStableAfterEditRoundtrip', 0, () => {
      // 编辑后拆回的块，区间表仍然一致（光标映射在编辑中途不失准）
      const blocks = [textBlock('第一段'), photoBlock(), textBlock('第二段')];
      const doc = editorDocumentFromBlocks(blocks);
      doc.text = doc.text.substring(0, 2) + '插入' + doc.text.substring(2);
      const out = blocksWithEditorDocument(doc, anchoredMap(blocks), makeId);
      expectRangesConsistent(out);
    })
  })
}
