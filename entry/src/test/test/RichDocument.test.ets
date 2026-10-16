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
  blocksWithEditorDocument,
  editorDocumentFromBlocks,
  mergeAdjacentRichSpans
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
  })
}
