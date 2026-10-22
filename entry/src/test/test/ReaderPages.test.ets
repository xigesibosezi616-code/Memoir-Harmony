/**
 * 翻页阅读器纯逻辑单测（10_BUILD_MANUAL.md 3.5）。
 * 核心不变量（R-READ-05）：任何一页「页眉/小标题 + 渲染组」的合计高度
 * 不超过页面内容区 —— 长短日记、照片、录音、痕迹任意组合都不截断正文。
 * 测量器用确定性 mock（等宽字符模型），渲染高度模型与页面视图共用 ReaderLayout。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  ContentBlock, ContentBlockType, PaperStyle, PhotoPosition, TextStyleRun
} from '../../main/ets/models/ContentBlock';
import { JournalEntry } from '../../main/ets/models/JournalEntry';
import {
  HeightRun, ReaderGeometry, ReaderGroupKind, ReaderLayout, ReaderPage,
  ReaderPageAnchor, ReaderPageKind, ReaderRenderGroup, ReaderTextMeasurer,
  buildReaderPages, estimateHeaderHeight, indexOfEntryFirstPage, indexOfPageAnchor,
  pageAnchorOf, paginateEntry, renderGroupsOf
} from '../../main/ets/models/ReaderPages';

/** 等宽字符模型：每字符宽 = 字号 × 0.5，单行高 = ceil(字号 × 1.5) + 行距。
 *  heading 字符按 20fp 字宽计（大字号占位更宽），与页面视图渲染模型一致 */
class MockMeasurer implements ReaderTextMeasurer {
  charWidthOf(fontSize: number): number {
    return fontSize * 0.5;
  }

  lineHeightOf(fontSize: number, lineSpacing: number): number {
    return Math.ceil(fontSize * 1.35) + lineSpacing;
  }

  heightOfPlain(text: string, fontSize: number, lineSpacing: number, width: number): number {
    if (text.length === 0) {
      return 0;
    }
    const cw = fontSize * 0.5;
    let lines = 1;
    let pos = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (ch === '\n') {
        lines++;
        pos = 0;
        continue;
      }
      if (pos > 0 && pos + cw > width) {
        lines++;
        pos = cw;
        continue;
      }
      pos += cw;
    }
    const lh = Math.ceil(fontSize * 1.5);
    return lines * lh + (lines - 1) * lineSpacing;
  }

  heightOfStyled(text: string, runs: HeightRun[], width: number): number {
    if (text.length === 0) {
      return 0;
    }
    const flags = this.headingFlags(text, runs);
    let lines = 1;
    let wacc = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      const w = flags[i] ? 10 : 8; // heading 20fp vs 正文 16fp 的等宽字宽
      if (ch === '\n') {
        lines++;
        wacc = 0;
        continue;
      }
      if (wacc > 0 && wacc + w > width) {
        lines++;
        wacc = w;
        continue;
      }
      wacc += w;
    }
    return lines * 24 + (lines - 1) * 8;
  }

  fittingLength(text: string, runs: HeightRun[], width: number, height: number): number {
    if (text.length === 0) {
      return 0;
    }
    const flags = this.headingFlags(text, runs);
    const lh = 24;
    const sp = 8;
    if (height < lh) {
      return 0;
    }
    const maxLines = 1 + Math.floor((height - lh) / (lh + sp));
    let line = 1;
    let wacc = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      const w = flags[i] ? 10 : 8;
      if (ch === '\n') {
        if (line >= maxLines) {
          return this.retreat(text, i + 1);
        }
        line++;
        wacc = 0;
        continue;
      }
      if (wacc === 0 || wacc + w <= width) {
        wacc += w;
        continue;
      }
      if (line >= maxLines) {
        return this.retreat(text, i);
      }
      line++;
      wacc = w;
    }
    return text.length;
  }

  private headingFlags(text: string, runs: HeightRun[]): boolean[] {
    const flags: boolean[] = [];
    for (let i = 0; i < text.length; i++) {
      flags.push(false);
    }
    for (const run of runs) {
      if (!run.heading) {
        continue;
      }
      const end = Math.min(run.location + run.length, text.length);
      for (let i = Math.max(0, run.location); i < end; i++) {
        flags[i] = true;
      }
    }
    return flags;
  }

  private retreat(text: string, index: number): number {
    if (index > 0 && index < text.length) {
      const prev = text.charCodeAt(index - 1);
      if (prev >= 0xD800 && prev <= 0xDBFF) {
        return index - 1;
      }
    }
    return index;
  }
}

// ---- 构造辅助 ----

let idCounter = 0;
function nextId(): string {
  idCounter++;
  return `reader-test-${idCounter}`;
}

function makeEntry(dateMs: number, blocks: ContentBlock[]): JournalEntry {
  const entry = new JournalEntry(nextId(), dateMs, dateMs + 1000, dateMs + 2000);
  entry.setContentBlocks(blocks, dateMs + 2000);
  return entry;
}

function textBlock(text: string): ContentBlock {
  return ContentBlock.makeText(nextId(), text);
}

function photoBlock(): ContentBlock {
  return ContentBlock.makePhoto(nextId(), 'photos/p.jpg', undefined,
    PhotoPosition.Right, PaperStyle.Original);
}

function audioBlock(): ContentBlock {
  return ContentBlock.makeAudio(nextId(), 'audio/a.m4a');
}

function traceBlock(): ContentBlock {
  return ContentBlock.makeTrace(nextId(), ContentBlockType.Photo, 1700000000);
}

function repeat(ch: string, count: number): string {
  let out = '';
  for (let i = 0; i < count; i++) {
    out += ch;
  }
  return out;
}

function stripNewlines(text: string): string {
  return text.split('\n').join('');
}

/** 一篇里全部文本块的文字（去换行）—— 文字保全对照的「原文」 */
function entryTextOf(entry: JournalEntry): string {
  let out = '';
  for (const block of entry.contentBlocks) {
    if (block.type === ContentBlockType.Text) {
      out += block.text ?? '';
    }
  }
  return stripNewlines(out);
}

/** 一页渲染出来的全部文字（去换行） */
function pageTextOf(page: ReaderPage): string {
  let out = '';
  for (const group of page.groups) {
    if (group.kind === ReaderGroupKind.FullText) {
      out += group.textBlock !== undefined ? (group.textBlock.text ?? '') : '';
    } else if (group.kind === ReaderGroupKind.PhotoWithText) {
      out += group.besideBlock !== undefined ? (group.besideBlock.text ?? '') : '';
      out += group.belowBlock !== undefined ? (group.belowBlock.text ?? '') : '';
    }
  }
  return stripNewlines(out);
}

/** 一个渲染组的渲染高度（与页面视图同一套版式常量；照片按 280 标称封顶） */
function renderHeightOfGroup(group: ReaderRenderGroup, width: number, m: MockMeasurer): number {
  if (group.kind === ReaderGroupKind.FullText) {
    const block = group.textBlock;
    if (block === undefined) {
      return 0;
    }
    return m.heightOfStyled(block.text ?? '', headingRunsOf(block), width);
  }
  if (group.kind === ReaderGroupKind.PhotoWithText) {
    const wrappedW = Math.max(1, width * (1 - ReaderLayout.photoWidthRatio)
      - ReaderLayout.photoTextGap);
    const beside = group.besideBlock;
    const besideH = beside !== undefined
      ? m.heightOfPlain(beside.text ?? '', ReaderLayout.wrappedTextFontSize,
        ReaderLayout.wrappedLineSpacing, wrappedW)
      : 0;
    let h = Math.max(ReaderLayout.photoBlockHeight, besideH);
    const below = group.belowBlock;
    if (below !== undefined) {
      h += 8 + m.heightOfPlain(below.text ?? '', ReaderLayout.bodyFontSize,
        ReaderLayout.bodyLineSpacing, width);
    }
    return h;
  }
  if (group.kind === ReaderGroupKind.StandalonePhoto) {
    return ReaderLayout.photoBlockHeight;
  }
  if (group.kind === ReaderGroupKind.Audio) {
    return ReaderLayout.audioBlockHeight;
  }
  return ReaderLayout.traceBlockHeight;
}

function headingRunsOf(block: ContentBlock): HeightRun[] {
  const out: HeightRun[] = [];
  const runs = block.styles;
  if (runs === undefined) {
    return out;
  }
  for (const run of runs) {
    if (run.heading === true && run.length > 0) {
      out.push(new HeightRun(run.location, run.length, true));
    }
  }
  return out;
}

/** 一页「页眉/小标题 + 渲染组 + 块间距」的合计消耗高度 */
function consumedHeightOf(page: ReaderPage, width: number, m: MockMeasurer): number {
  let h = page.pageIndex === 0
    ? estimateHeaderHeight(page.entry, width, m) + ReaderLayout.headerBottomGap
    : m.lineHeightOf(ReaderLayout.runningTitleFontSize, 0) + ReaderLayout.runningTitleBottomGap;
  let first = true;
  for (const group of page.groups) {
    if (!first) {
      h += ReaderLayout.blockSpacing;
    }
    h += renderHeightOfGroup(group, width, m);
    first = false;
  }
  return h;
}

/** R-READ-05 不变量：每页消耗 ≤ 内容区高度，且整篇文字一页不落全在 */
function assertPagesWithinBudget(entry: JournalEntry, m: MockMeasurer): ReaderPage[] {
  const geometry = new ReaderGeometry(390, 844, 47, 34);
  const width = geometry.contentWidth();
  const pages = paginateEntry(entry, geometry, m, nextId);
  expect(pages.length > 0).assertTrue();
  const area = geometry.contentAreaHeight(m);
  let collected = '';
  for (const page of pages) {
    expect(consumedHeightOf(page, width, m) <= area).assertTrue();
    collected += pageTextOf(page);
  }
  expect(collected === entryTextOf(entry)).assertTrue();
  return pages;
}

const M = new MockMeasurer();

export default function readerPagesTest() {
  describe('ReaderPagesTest', () => {
    // ---- 几何（R-READ-05 版式共用的前提） ----

    it('geometryCapsContentWidthOnLargeScreens', 0, () => {
      const phone = new ReaderGeometry(390, 844, 47, 34);
      expect(phone.contentWidth()).assertEqual(350);
      // 大屏（折叠屏展开）页宽封顶 420 → 内容宽 380，不跟着屏宽无限涨
      const foldout = new ReaderGeometry(800, 900, 30, 30);
      expect(foldout.contentWidth()).assertEqual(380);
    });

    // ---- 分页核心不变量（R-READ-05：任何一页不截断正文） ----

    it('emptyEntryStillYieldsSinglePage', 0, () => {
      const entry = makeEntry(1700000000000, []);
      const pages = assertPagesWithinBudget(entry, M);
      expect(pages.length).assertEqual(1);
      expect(pages[0].kind).assertEqual(ReaderPageKind.Content);
      expect(pages[0].pageIndex).assertEqual(0);
      expect(pages[0].totalPages).assertEqual(1);
      expect(pages[0].groups.length).assertEqual(0);
    });

    it('longTextSplitsAcrossPagesWithoutTruncation', 0, () => {
      const entry = makeEntry(1700000000000, [textBlock(repeat('长', 1200))]);
      const pages = assertPagesWithinBudget(entry, M);
      expect(pages.length > 1).assertTrue();
      for (let i = 0; i < pages.length; i++) {
        expect(pages[i].pageIndex).assertEqual(i);
        expect(pages[i].totalPages).assertEqual(pages.length);
      }
    });

    it('mixedContentNeverTruncatesOrLosesText', 0, () => {
      // 小标题 + 换行 + 照片 + 短文 + 录音 + 痕迹 + 第二张照片，长短混排
      const headingText = textBlock(repeat('题', 50) + '\n' + repeat('正', 700)
        + '\n' + repeat('文', 48));
      const headingStyle = new TextStyleRun(0, 50);
      headingStyle.heading = true;
      headingText.styles = [headingStyle];
      const blocks: ContentBlock[] = [headingText, photoBlock(), textBlock(repeat('短', 150)),
        audioBlock(), traceBlock(), photoBlock()];
      const entry = makeEntry(1700000000000, blocks);
      const pages = assertPagesWithinBudget(entry, M);
      // 至少三页：正文被切开 + 照片/录音分页
      expect(pages.length >= 2).assertTrue();
      // 小标题样式跟着分页走（首页第一组带 heading）
      const first = pages[0].groups[0];
      expect(first.kind).assertEqual(ReaderGroupKind.FullText);
      const firstBlock = first.textBlock;
      expect(firstBlock !== undefined).assertTrue();
      let headingSurvived = false;
      if (firstBlock !== undefined && firstBlock.styles !== undefined) {
        for (const run of firstBlock.styles) {
          if (run.heading === true && run.length === 50) {
            headingSurvived = true;
          }
        }
      }
      expect(headingSurvived).assertTrue();
    });

    it('firstPageReservesHeaderSpace', 0, () => {
      // 同样 600 字：无页眉装得下一页，带标题+标签要两页 —— 页眉高度真的被扣掉
      const plain = makeEntry(1700000000000, [textBlock(repeat('字', 600))]);
      const plainPages = assertPagesWithinBudget(plain, M);
      const titled = makeEntry(1700000000000, [textBlock(repeat('字', 600))]);
      titled.title = repeat('标', 30);
      titled.tags = ['旅'];
      const titledPages = assertPagesWithinBudget(titled, M);
      expect(plainPages.length).assertEqual(1);
      expect(titledPages.length).assertEqual(2);
    });

    it('estimateHeaderHeightGrowsWithTitleAndTags', 0, () => {
      const geometry = new ReaderGeometry(390, 844, 47, 34);
      const width = geometry.contentWidth();
      const bare = makeEntry(1700000000000, []);
      const titled = makeEntry(1700000000000, []);
      titled.title = repeat('标', 30);
      const tagged = makeEntry(1700000000000, []);
      tagged.title = repeat('标', 30);
      tagged.tags = ['旅'];
      const bareH = estimateHeaderHeight(bare, width, M);
      const titledH = estimateHeaderHeight(titled, width, M);
      const taggedH = estimateHeaderHeight(tagged, width, M);
      expect(bareH < titledH).assertTrue();
      expect(titledH < taggedH).assertTrue();
    });

    // ---- 照片环绕（R-READ-05 的照片路径） ----

    it('photoCarriesCompanionTextToNextPage', 0, () => {
      // 300 字放得进首页、照片放不下 → 文字随照片一起去下一页（iOS 同款），
      // 首页只剩页眉
      const entry = makeEntry(1700000000000, [textBlock(repeat('随', 300)), photoBlock()]);
      const pages = assertPagesWithinBudget(entry, M);
      expect(pages.length).assertEqual(2);
      expect(pages[0].groups.length).assertEqual(0);
      const moved = pages[1].groups[0];
      expect(moved.kind).assertEqual(ReaderGroupKind.PhotoWithText);
      const beside = moved.besideBlock !== undefined ? moved.besideBlock.text ?? '' : '';
      const below = moved.belowBlock !== undefined ? moved.belowBlock.text ?? '' : '';
      expect(beside.length).assertEqual(192);
      expect(below.length).assertEqual(108);
      expect(stripNewlines(beside + below)).assertEqual(repeat('随', 300));
    });

    it('shortTextAndPhotoShareFirstPage', 0, () => {
      const entry = makeEntry(1700000000000, [textBlock(repeat('短', 20)), photoBlock()]);
      const pages = assertPagesWithinBudget(entry, M);
      expect(pages.length).assertEqual(1);
      const group = pages[0].groups[0];
      expect(group.kind).assertEqual(ReaderGroupKind.PhotoWithText);
      expect(group.belowBlock).assertUndefined();
      expect(group.besideBlock !== undefined ? group.besideBlock.text : '').assertEqual(repeat('短', 20));
    });

    it('leadingPhotoThenLongTextKeepsEverything', 0, () => {
      const entry = makeEntry(1700000000000, [photoBlock(), textBlock(repeat('首', 800))]);
      const pages = assertPagesWithinBudget(entry, M);
      expect(pages.length).assertEqual(2);
      const first = pages[0].groups[0];
      expect(first.kind).assertEqual(ReaderGroupKind.StandalonePhoto);
    });

    it('splitRetreatsToSurrogateBoundary', 0, () => {
      // 'x' + 130 个 emoji（260 单元）：环绕容量 192 会落进代理对中间，必须退到边界
      const emojiText = 'x' + repeat('😀', 130);
      const entry = makeEntry(1700000000000, [textBlock(emojiText), photoBlock()]);
      const pages = assertPagesWithinBudget(entry, M);
      const moved = pages[pages.length - 1].groups[0];
      expect(moved.kind).assertEqual(ReaderGroupKind.PhotoWithText);
      const beside = moved.besideBlock !== undefined ? moved.besideBlock.text ?? '' : '';
      const below = moved.belowBlock !== undefined ? moved.belowBlock.text ?? '' : '';
      // 191 = 'x' + 95 个完整 emoji；70 = 35 个完整 emoji，都不劈开代理对
      expect(beside.length).assertEqual(191);
      expect(below.length).assertEqual(70);
      expect(below.charCodeAt(0) >= 0xD800).assertTrue();
    });

    // ---- 渲染组（iOS ContentBlockRenderer 两指针扫描） ----

    it('renderGroupsMergesFollowersUpToCapacity', 0, () => {
      const a = textBlock(repeat('甲', 100));
      const photo = photoBlock();
      const b = textBlock(repeat('乙', 200));
      const groups = renderGroupsOf([a, photo, b], 350, M, nextId);
      expect(groups.length).assertEqual(1);
      expect(groups[0].kind).assertEqual(ReaderGroupKind.PhotoWithText);
      const beside = groups[0].besideBlock !== undefined ? groups[0].besideBlock.text ?? '' : '';
      const below = groups[0].belowBlock !== undefined ? groups[0].belowBlock.text ?? '' : '';
      expect(beside.length).assertEqual(192);
      expect(below.length).assertEqual(109);
      expect(stripNewlines(beside + below))
        .assertEqual(repeat('甲', 100) + repeat('乙', 200));
    });

    it('renderGroupsKeepsNextPhotoAnchorIntact', 0, () => {
      const a = textBlock(repeat('甲', 30));
      const photoA = photoBlock();
      const b = textBlock(repeat('乙', 30));
      const photoB = photoBlock();
      const groups = renderGroupsOf([a, photoA, b, photoB], 350, M, nextId);
      expect(groups.length).assertEqual(2);
      expect(groups[0].kind).assertEqual(ReaderGroupKind.PhotoWithText);
      expect(groups[1].kind).assertEqual(ReaderGroupKind.PhotoWithText);
      expect(groups[0].besideBlock !== undefined ? groups[0].besideBlock.text : '')
        .assertEqual(repeat('甲', 30));
      expect(groups[1].besideBlock !== undefined ? groups[1].besideBlock.text : '')
        .assertEqual(repeat('乙', 30));
      expect(groups[0].belowBlock).assertUndefined();
      expect(groups[1].belowBlock).assertUndefined();
    });

    it('renderGroupsStandalonePhotoForLeadingPhoto', 0, () => {
      const groups = renderGroupsOf([photoBlock(), textBlock('尾')], 350, M, nextId);
      expect(groups.length).assertEqual(2);
      expect(groups[0].kind).assertEqual(ReaderGroupKind.StandalonePhoto);
      expect(groups[1].kind).assertEqual(ReaderGroupKind.FullText);
    });

    it('renderGroupsAudioTraceAreOwnGroups', 0, () => {
      const groups = renderGroupsOf([audioBlock(), traceBlock(), textBlock('文')], 350, M, nextId);
      expect(groups.length).assertEqual(3);
      expect(groups[0].kind).assertEqual(ReaderGroupKind.Audio);
      expect(groups[1].kind).assertEqual(ReaderGroupKind.Trace);
      expect(groups[2].kind).assertEqual(ReaderGroupKind.FullText);
    });

    it('renderGroupsPreservesBoldThroughMergeAndSplit', 0, () => {
      const a = textBlock(repeat('粗', 60));
      const boldRun = new TextStyleRun(0, 60);
      boldRun.bold = true;
      a.styles = [boldRun];
      const groups = renderGroupsOf([a, photoBlock(), textBlock(repeat('平', 200))], 350, M, nextId);
      const beside = groups[0].besideBlock;
      expect(beside !== undefined).assertTrue();
      let hasBold = false;
      if (beside !== undefined && beside.styles !== undefined) {
        for (const run of beside.styles) {
          if (run.bold === true) {
            hasBold = true;
          }
        }
      }
      expect(hasBold).assertTrue();
    });

    // ---- 整本数据源（R-READ-01/02 阅读顺序 + 结尾页） ----

    it('buildReaderPagesOrdersEarlyToLateAndEndsWithEndingPage', 0, () => {
      const early = makeEntry(1700000000000, [textBlock(repeat('早', 100))]);
      const late = makeEntry(1800000000000, [textBlock(repeat('晚', 100))]);
      const pages = buildReaderPages([late, early], new ReaderGeometry(390, 844, 47, 34), M, nextId);
      expect(pages.length).assertEqual(3); // 早 1 页 + 晚 1 页 + ending
      expect(pages[0].kind).assertEqual(ReaderPageKind.Content);
      expect(pages[0].entry.id).assertEqual(early.id);
      expect(pages[1].entry.id).assertEqual(late.id);
      expect(pages[2].kind).assertEqual(ReaderPageKind.Ending);
      expect(pages[2].entry.id).assertEqual(late.id);
    });

    it('indexOfEntryFirstPageJumpsToHeaderPage', 0, () => {
      const early = makeEntry(1700000000000, [textBlock(repeat('早', 100))]);
      const late = makeEntry(1800000000000, [textBlock(repeat('晚', 100))]);
      const pages = buildReaderPages([early, late], new ReaderGeometry(390, 844, 47, 34), M, nextId);
      const idx = indexOfEntryFirstPage(pages, late.id);
      expect(pages[idx].entry.id).assertEqual(late.id);
      expect(pages[idx].pageIndex).assertEqual(0);
      expect(pages[idx].kind).assertEqual(ReaderPageKind.Content);
      // 找不到回 0
      expect(indexOfEntryFirstPage(pages, 'no-such-id')).assertEqual(0);
    });

    // ---- 折叠屏 / 分屏重排：保持当前篇、当前页 ----

    it('pageAnchorAndIndexRebuildsAtSamePosition', 0, () => {
      const entry = makeEntry(1700000000000, [textBlock(repeat('重', 2400))]);
      const wide = buildReaderPages([entry], new ReaderGeometry(390, 844, 47, 34), M, nextId);
      const narrow = buildReaderPages([entry], new ReaderGeometry(320, 844, 47, 34), M, nextId);
      expect(wide.length > 2).assertTrue();
      expect(narrow.length > 2).assertTrue();
      const target = wide.length - 2; // 结尾页前一页，必有内容页
      const anchor = pageAnchorOf(wide, target);
      expect(anchor !== undefined).assertTrue();
      if (anchor === undefined) {
        return;
      }
      const idx = indexOfPageAnchor(narrow, anchor);
      expect(narrow[idx].entry.id).assertEqual(entry.id);
      expect(narrow[idx].kind).assertEqual(ReaderPageKind.Content);
    });

    it('pageAnchorKeepsEndingAndFallsBackSafely', 0, () => {
      const entry = makeEntry(1700000000000, [textBlock(repeat('尾', 200))]);
      const pages = buildReaderPages([entry], new ReaderGeometry(390, 844, 47, 34), M, nextId);
      const endingAnchor = pageAnchorOf(pages, pages.length - 1);
      expect(endingAnchor !== undefined).assertTrue();
      if (endingAnchor !== undefined) {
        expect(endingAnchor.kind).assertEqual(ReaderPageKind.Ending);
        expect(indexOfPageAnchor(pages, endingAnchor)).assertEqual(pages.length - 1);
      }
      const missing = new ReaderPageAnchor('no-such-id', 2, ReaderPageKind.Content);
      expect(indexOfPageAnchor(pages, missing)).assertEqual(0);
      expect(pageAnchorOf(pages, -1) === undefined).assertTrue();
      expect(pageAnchorOf(pages, pages.length) === undefined).assertTrue();
    });
  });
}
