/**
 * 大屏模式纯逻辑单测（10_BUILD_MANUAL.md 3.6 + U06 R-HOME-08/09/10）。
 *
 * 不变量：
 * - 级别几何：列数 1/2/4/8、间距 12/8/4、圆角 26/16/10/6、解码尺寸 1400/600/300/160
 * - 图文配比：字越多照片占比越小（0.86→0.46），正文行数反向收紧（0→11）
 * - digest：无题用正文首行（≤30 字）；缓存按 id 命中，改过时间必重算；
 *   心情色缺时按预设 key 兜底
 * - 四宫格：每 4 篇一页、槽位按中线分、下标 clamp
 * - 总览：同月必并成一段；「手指底下是哪篇」按版式定死算，落在月份标题
 *   算那个月第一篇，超出内容算最后一篇
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  QUAD_PAGE_SIZE,
  DigestMonth,
  EntryDigest,
  ShowcaseZoomLevel,
  cardImageRatio,
  cardTextLines,
  clearDigestCache,
  digestOf,
  overviewCellSize,
  overviewEntryIndexAt,
  overviewFillerDigest,
  overviewMonths,
  padOverviewRow,
  quadEntryIndexAtSlot,
  quadPageCount,
  quadPageOf,
  quadPageStart,
  quadSlotAnchor,
  quadSlotAt,
  showcaseCardSize,
  zoomColumns,
  zoomCornerRadius,
  zoomSpacing,
  zoomPhotoPixels
} from '../../main/ets/models/ShowcaseDigest';
import { JournalEntry } from '../../main/ets/models/JournalEntry';
import { presetMoodColorHex } from '../../main/ets/models/Mood';
import { ContentBlock, PhotoPosition, PaperStyle } from '../../main/ets/models/ContentBlock';

/** 2026-10-19 10:30（周一） */
const OCT19: number = new Date(2026, 9, 19, 10, 30, 0).getTime();
/** 2026-10-01 08:00（周四） */
const OCT01: number = new Date(2026, 9, 1, 8, 0, 0).getTime();
/** 2026-09-05 20:00（周六） */
const SEP05: number = new Date(2026, 8, 5, 20, 0, 0).getTime();

function makeEntry(id: string, date: number): JournalEntry {
  return new JournalEntry(id, date, date, date + 60000);
}

function makePhotoEntry(id: string, date: number, cover: string,
  first: string): JournalEntry {
  const entry = makeEntry(id, date);
  const b1 = ContentBlock.makePhoto('p1', first, undefined,
    PhotoPosition.Left, PaperStyle.Original);
  b1.isCover = false;
  const b2 = ContentBlock.makePhoto('p2', cover, undefined,
    PhotoPosition.Left, PaperStyle.Original);
  b2.isCover = true;
  entry.setContentBlocks([b1, b2], entry.updatedAt);
  return entry;
}

export default function showcaseDigestTest() {
  describe('ShowcaseDigest', () => {
    // ---- 级别几何 ----

    it('zoomColumnsDoublesPerLevel', 0, () => {
      expect(zoomColumns(ShowcaseZoomLevel.One)).assertEqual(1);
      expect(zoomColumns(ShowcaseZoomLevel.Four)).assertEqual(2);
      expect(zoomColumns(ShowcaseZoomLevel.Sixteen)).assertEqual(4);
      expect(zoomColumns(ShowcaseZoomLevel.SixtyFour)).assertEqual(8);
    })

    it('zoomSpacingShrinksWithDensity', 0, () => {
      expect(zoomSpacing(ShowcaseZoomLevel.One)).assertEqual(0);
      expect(zoomSpacing(ShowcaseZoomLevel.Four)).assertEqual(12);
      expect(zoomSpacing(ShowcaseZoomLevel.Sixteen)).assertEqual(8);
      expect(zoomSpacing(ShowcaseZoomLevel.SixtyFour)).assertEqual(4);
    })

    it('zoomCornerRadiusScalesWithCell', 0, () => {
      expect(zoomCornerRadius(ShowcaseZoomLevel.One)).assertEqual(26);
      expect(zoomCornerRadius(ShowcaseZoomLevel.Four)).assertEqual(16);
      expect(zoomCornerRadius(ShowcaseZoomLevel.Sixteen)).assertEqual(10);
      expect(zoomCornerRadius(ShowcaseZoomLevel.SixtyFour)).assertEqual(6);
    })

    it('zoomPhotoPixelsDecodesOnlyWhatIsShown', 0, () => {
      expect(zoomPhotoPixels(ShowcaseZoomLevel.One)).assertEqual(1400);
      expect(zoomPhotoPixels(ShowcaseZoomLevel.Four)).assertEqual(600);
      expect(zoomPhotoPixels(ShowcaseZoomLevel.Sixteen)).assertEqual(300);
      expect(zoomPhotoPixels(ShowcaseZoomLevel.SixtyFour)).assertEqual(160);
    })

    // ---- 大卡片尺寸（2026-10-23 真机「细长」修正；比例钳 [2:3, 3:2]）----

    it('showcaseCardSizeCapsAtTwoToThreeOnTallNarrowScreens', 0, () => {
      // X6 折叠态实测容器（vp）：太细长 → 高钳到 2:3——不再拉成 0.575 竖条
      const size = showcaseCardSize(345.6, 554);
      expect(size[0]).assertEqual(309.6);
      expect(Math.abs(size[1] - 464.4) < 0.001).assertTrue();
      expect(size[0] / size[1] > 0.66).assertTrue();
    })

    it('showcaseCardSizeFillsNearSquareUnfoldedContainers', 0, () => {
      // X6 展开态实测容器（vp）：近方（宽高比 1.29，区间内）→ 填满可用区，
      // 不能把宽钳成窄竖条（2026-10-23 展开实测 358.7vp 窄条事故）
      const size = showcaseCardSize(716.8, 554.2);
      expect(Math.abs(size[0] - 680.8) < 0.001).assertTrue();
      expect(Math.abs(size[1] - 538.2) < 0.001).assertTrue();
    })

    it('showcaseCardSizeCapsAtThreeToTwoOnFlatWideContainers', 0, () => {
      // 宽扁容器（平板横屏）：太宽扁 → 宽钳到 3:2
      const size = showcaseCardSize(1000, 400);
      expect(size[1]).assertEqual(384);
      expect(Math.abs(size[0] - 576) < 0.001).assertTrue();
    })

    it('showcaseCardSizeNeverExceedsContainer', 0, () => {
      const tall = showcaseCardSize(345.6, 554);
      expect(tall[0] <= 345.6 - 36).assertTrue();
      expect(tall[1] <= 554 - 16).assertTrue();
      const square = showcaseCardSize(716.8, 554.2);
      expect(square[0] <= 716.8 - 36).assertTrue();
      expect(square[1] <= 554.2 - 16).assertTrue();
    })

    // ---- 图文配比（R-HOME-06）----

    it('cardImageRatioShrinksAsTextGrows', 0, () => {
      expect(cardImageRatio(0)).assertEqual(0.86);
      expect(cardImageRatio(1)).assertEqual(0.70);
      expect(cardImageRatio(39)).assertEqual(0.70);
      expect(cardImageRatio(40)).assertEqual(0.60);
      expect(cardImageRatio(119)).assertEqual(0.60);
      expect(cardImageRatio(120)).assertEqual(0.52);
      expect(cardImageRatio(239)).assertEqual(0.52);
      expect(cardImageRatio(240)).assertEqual(0.46);
      expect(cardImageRatio(1000)).assertEqual(0.46);
    })

    it('cardTextLinesGrowsWithPreviewLength', 0, () => {
      expect(cardTextLines(0)).assertEqual(0);
      expect(cardTextLines(1)).assertEqual(3);
      expect(cardTextLines(39)).assertEqual(3);
      expect(cardTextLines(40)).assertEqual(5);
      expect(cardTextLines(119)).assertEqual(5);
      expect(cardTextLines(120)).assertEqual(8);
      expect(cardTextLines(239)).assertEqual(8);
      expect(cardTextLines(240)).assertEqual(11);
      expect(cardTextLines(1000)).assertEqual(11);
    })

    // ---- digest ----

    it('digestFallsBackToFirstLineWhenNoTitle', 0, () => {
      clearDigestCache();
      const entry = makeEntry('d1', OCT19);
      entry.setContentBlocks([
        ContentBlock.makeText('t1', '第一行内容'),
        ContentBlock.makeText('t2', '第二行内容')
      ], entry.updatedAt);
      const digest = digestOf(entry, 'zh-Hans');
      expect(digest.title).assertEqual('第一行内容');
      expect(digest.preview).assertEqual('第一行内容\n第二行内容');
    })

    it('digestTitleFallbackTruncatesAt30', 0, () => {
      clearDigestCache();
      const entry = makeEntry('d2', OCT19);
      const long = '一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一';
      entry.setContentBlocks([ContentBlock.makeText('t1', long)], entry.updatedAt);
      const digest = digestOf(entry, 'zh-Hans');
      expect(digest.title.length).assertEqual(30);
      expect(digest.title).assertEqual(long.substring(0, 30));
    })

    it('digestPrefersExplicitTitle', 0, () => {
      clearDigestCache();
      const entry = makeEntry('d3', OCT19);
      entry.title = ' 有标题 ';
      entry.setContentBlocks([ContentBlock.makeText('t1', '正文')], entry.updatedAt);
      const digest = digestOf(entry, 'zh-Hans');
      expect(digest.title).assertEqual('有标题');
    })

    it('digestCacheHitsUntilEntryChanges', 0, () => {
      clearDigestCache();
      const entry = makeEntry('d4', OCT19);
      entry.setContentBlocks([ContentBlock.makeText('t1', '旧内容')], entry.updatedAt);
      const first = digestOf(entry, 'zh-Hans');
      // 同签名：同一份缓存，不再解 JSON
      expect(digestOf(entry, 'zh-Hans') === first).assertTrue();
      // 改过时间变了 → 重算
      entry.setContentBlocks([ContentBlock.makeText('t1', '新内容')], entry.updatedAt + 1);
      const second = digestOf(entry, 'zh-Hans');
      expect(second === first).assertFalse();
      expect(second.preview).assertEqual('新内容');
    })

    it('digestDatesMatchAppLanguage', 0, () => {
      clearDigestCache();
      const entry = makeEntry('d5', OCT19);
      entry.setContentBlocks([ContentBlock.makeText('t1', 'x')], entry.updatedAt);
      const zh = digestOf(entry, 'zh-Hans');
      expect(zh.monthKey).assertEqual('2026年10月');
      expect(zh.month).assertEqual(202610);
      expect(zh.dayAndWeekday).assertEqual('10月19日 星期一');
      expect(zh.dayWithWeekday).assertEqual('19日 周一');
      expect(zh.day).assertEqual(19);
      // 换语言是另一个缓存签名：月头跟着语言走
      const en = digestOf(entry, 'en');
      expect(en.monthKey).assertEqual('October 2026');
    })

    it('digestMoodColorFallsBackToPreset', 0, () => {
      clearDigestCache();
      const entry = makeEntry('d6', OCT19);
      entry.mood = 'calm';
      entry.setContentBlocks([ContentBlock.makeText('t1', 'x')], entry.updatedAt);
      const digest = digestOf(entry, 'zh-Hans');
      const preset = presetMoodColorHex('calm');
      expect(preset !== undefined).assertTrue();
      expect(digest.moodColorHex).assertEqual(preset);
      // 用户自己选过的心情色优先
      const custom = makeEntry('d7', OCT19);
      custom.mood = 'calm';
      custom.moodColorHex = '#123456';
      custom.setContentBlocks([ContentBlock.makeText('t1', 'x')], custom.updatedAt);
      expect(digestOf(custom, 'zh-Hans').moodColorHex).assertEqual('#123456');
    })

    it('digestCoverPrefersIsCoverBlock', 0, () => {
      clearDigestCache();
      const entry = makePhotoEntry('d8', OCT19, 'cover.jpg', 'first.jpg');
      const digest = digestOf(entry, 'zh-Hans');
      expect(digest.cover).assertEqual('cover.jpg');
    })

    // ---- 四宫格 ----

    it('quadPagesChunkByFour', 0, () => {
      expect(quadPageCount(0)).assertEqual(0);
      expect(quadPageCount(1)).assertEqual(1);
      expect(quadPageCount(QUAD_PAGE_SIZE)).assertEqual(1);
      expect(quadPageCount(QUAD_PAGE_SIZE + 1)).assertEqual(2);
      expect(quadPageStart(2)).assertEqual(8);
      expect(quadPageOf(QUAD_PAGE_SIZE - 1)).assertEqual(0);
      expect(quadPageOf(QUAD_PAGE_SIZE)).assertEqual(1);
    })

    it('quadSlotSplitsByMidlines', 0, () => {
      expect(quadSlotAt(25, 50, 100, 200)).assertEqual(0);
      expect(quadSlotAt(75, 50, 100, 200)).assertEqual(1);
      expect(quadSlotAt(25, 150, 100, 200)).assertEqual(2);
      expect(quadSlotAt(75, 150, 100, 200)).assertEqual(3);
      // 中线本身归左 / 上
      expect(quadSlotAt(50, 100, 100, 200)).assertEqual(0);
    })

    it('quadEntryIndexClampsToLast', 0, () => {
      expect(quadEntryIndexAtSlot(0, 2, 10)).assertEqual(2);
      // 末页只有 2 篇：右下槽 clamp 到第 2 篇
      expect(quadEntryIndexAtSlot(8, 3, 10)).assertEqual(9);
    })

    it('quadSlotAnchorIsCellCenter', 0, () => {
      expect(quadSlotAnchor(0)[0]).assertEqual(0.27);
      expect(quadSlotAnchor(0)[1]).assertEqual(0.27);
      expect(quadSlotAnchor(1)[0]).assertEqual(0.73);
      expect(quadSlotAnchor(2)[1]).assertEqual(0.73);
      expect(quadSlotAnchor(5)[0]).assertEqual(0.73);
      expect(quadSlotAnchor(6)[1]).assertEqual(0.73);
    })

    // ---- 总览按月分组 ----

    it('overviewMonthsGroupsSameMonthTogether', 0, () => {
      clearDigestCache();
      const entries = [makeEntry('m1', OCT19), makeEntry('m2', OCT01),
        makeEntry('m3', SEP05)];
      const months = overviewMonths(entries, 'zh-Hans');
      expect(months.length).assertEqual(2);
      expect(months[0].month).assertEqual(202610);
      expect(months[0].title).assertEqual('2026年10月');
      expect(months[0].startIndex).assertEqual(0);
      expect(months[0].count).assertEqual(2);
      expect(months[1].month).assertEqual(202609);
      expect(months[1].startIndex).assertEqual(2);
      expect(months[1].count).assertEqual(1);
    })

    it('overviewCellSizeSubtractsMarginsAndSpacing', 0, () => {
      // 360 宽、十六篇级：4 列、8 缝、两边 18 → (360-36-24)/4 = 75
      const size = overviewCellSize(360, ShowcaseZoomLevel.Sixteen);
      expect(size[0]).assertEqual(75);
      expect(Math.abs(size[1] - 75 / 0.66) < 1e-9).assertTrue();
    })

    it('padOverviewRowFillsIncompleteTailRowLikePhotoAlbum', 0, () => {
      // 真机反馈：第三档（十六篇）本月 5 篇 → 尾行 1 格被 layoutWeight 拉成
      // 全宽大卡。相册逻辑：尾行补占位（id=''）保持同尺寸留空
      const real = digestOf(makeEntry('e1', OCT19), 'zh-Hans');
      const row = [real];
      const padded = padOverviewRow(row, 4);
      expect(padded.length).assertEqual(4);
      expect(padded[0].id).assertEqual('e1');
      expect(padded[1].id).assertEqual('');
      expect(padded[2].id).assertEqual('');
      expect(padded[3].id).assertEqual('');
      // 满行原样（4/4 无占位）
      const full: EntryDigest[] = [real, real, real, real];
      expect(padOverviewRow(full, 4).length).assertEqual(4);
      // 六十四篇 8 列同样补满
      expect(padOverviewRow([real], 8).length).assertEqual(8);
      // 不改入参
      expect(row.length).assertEqual(1);
      // 占位 digest 全空
      const filler = overviewFillerDigest();
      expect(filler.id).assertEqual('');
      expect(filler.cover).assertEqual('');
    })

    it('overviewEntryIndexResolvesFingerPosition', 0, () => {
      // 两个月段：10 月 8 篇（2 行）、9 月 2 篇（1 行）；pageWidth 360、
      // 4 列 → 格宽 75、格高 75/0.66、行进 75/0.66+8、月头 34
      const cellHeight = 75 / 0.66;
      const rowStride = cellHeight + 8;
      const months = [
        new DigestMonth(202610, '2026年10月', 0, 8),
        new DigestMonth(202609, '2026年9月', 8, 2)
      ];
      const zoom = ShowcaseZoomLevel.Sixteen;
      // 空宫格
      expect(overviewEntryIndexAt([], zoom, 360, 50, 50)).assertEqual(-1);
      // 落在月份标题上 → 那个月第一篇
      expect(overviewEntryIndexAt(months, zoom, 360, 55, 10)).assertEqual(0);
      // 第一行第 0 / 第 3 列
      expect(overviewEntryIndexAt(months, zoom, 360, 55, 34 + 10)).assertEqual(0);
      expect(overviewEntryIndexAt(months, zoom, 360, 18 + 3 * 83 + 30, 34 + 10)).assertEqual(3);
      // 第二行第 0 列 → 4
      expect(overviewEntryIndexAt(months, zoom, 360, 55, 34 + rowStride + 10)).assertEqual(4);
      // 第二个月标题 → 8；这个月只有 2 篇，第 3 列 clamp 到第 2 篇（9）
      const monthBTop = 34 + 2 * rowStride;
      expect(overviewEntryIndexAt(months, zoom, 360, 55, monthBTop + 10)).assertEqual(8);
      expect(overviewEntryIndexAt(months, zoom, 360, 18 + 3 * 83 + 30,
        monthBTop + 34 + 10)).assertEqual(9);
      // 手指在内容底下 → 最后一篇
      expect(overviewEntryIndexAt(months, zoom, 360, 55, 100000)).assertEqual(9);
    })
  })
}
