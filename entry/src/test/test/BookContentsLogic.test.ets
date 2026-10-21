/**
 * 日记本主页纯逻辑单测（10_BUILD_MANUAL.md 3.3）。
 * 对应 iOS `BookDetailView.readingEntries` / `heroSubtitle` +
 * `BookContentsView.monthGroups` / `titleText` + `PageDataSource.readingOrder`：
 * 阅读顺序（date / createdAt 双键）、按名过滤、标题回退链（30 字截断）、
 * 年月跨度副标题（同月合并 / 用户副标题优先）、按月分组（跨年边界 / 编号连续）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { JournalEntry } from '../../main/ets/models/JournalEntry';
import {
  BookContentsItem,
  bookMonthGroups,
  bookReadingEntries,
  contentsTitle,
  heroSubtitle,
  readingOrderSort
} from '../../main/ets/data/BookContentsLogic';

let idCounter = 0;

function makeEntry(date: number, createdAt: number): JournalEntry {
  idCounter++;
  const entry = new JournalEntry(`book-test-${idCounter}`, date, createdAt, createdAt);
  return entry;
}

/** 本地某天的 12:00（避开午夜边界）；month 按 1 月 = 1（人类习惯） */
function noon(year: number, month: number, day: number): number {
  return new Date(year, month - 1, day, 12, 0, 0).getTime();
}

export default function bookContentsLogicTest() {
  describe('BookContentsLogicTest', () => {

    // ---- readingOrderSort（R-READ-01：date 升序、同日按 createdAt 升序） ----

    it('sortsByDateThenCreatedAt', 0, () => {
      const early = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      const lateSameDay = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1) + 3600_000);
      const lateDay = makeEntry(noon(2026, 8, 2), noon(2026, 8, 2));
      const sorted = readingOrderSort([lateDay, lateSameDay, early]);
      expect(sorted[0].id).assertEqual(early.id);
      expect(sorted[1].id).assertEqual(lateSameDay.id);
      expect(sorted[2].id).assertEqual(lateDay.id);
    })

    it('doesNotMutateInput', 0, () => {
      const a = makeEntry(noon(2026, 8, 2), noon(2026, 8, 2));
      const b = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      const input = [a, b];
      readingOrderSort(input);
      expect(input[0].id).assertEqual(a.id);
      expect(input[1].id).assertEqual(b.id);
    })

    // ---- bookReadingEntries（按名过滤；空名 = 全部） ----

    it('filtersByNotebookName', 0, () => {
      const inBook = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      inBook.tags = ['旅行'];
      const outside = makeEntry(noon(2026, 8, 2), noon(2026, 8, 2));
      outside.tags = ['工作'];
      const noBook = makeEntry(noon(2026, 8, 3), noon(2026, 8, 3));
      const result = bookReadingEntries([outside, inBook, noBook], '旅行');
      expect(result.length).assertEqual(1);
      expect(result[0].id).assertEqual(inBook.id);
    })

    it('emptyNameReturnsAllSorted', 0, () => {
      const a = makeEntry(noon(2026, 8, 2), noon(2026, 8, 2));
      const b = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      const result = bookReadingEntries([a, b], '');
      expect(result.length).assertEqual(2);
      expect(result[0].id).assertEqual(b.id);
      expect(result[1].id).assertEqual(a.id);
    })

    // ---- contentsTitle（标题 → 正文第一行 ≤30 字 → ''） ----

    it('titleWinsOverPreview', 0, () => {
      const entry = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      entry.title = '  晨间散步  ';
      entry.content = '正文第一行';
      expect(contentsTitle(entry)).assertEqual('晨间散步');
    })

    it('fallsBackToFirstPreviewLine', 0, () => {
      const entry = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      entry.title = '   ';
      entry.content = '第一行\n第二行';
      expect(contentsTitle(entry)).assertEqual('第一行');
    })

    it('previewFallbackCapsAt30Chars', 0, () => {
      const entry = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      entry.title = '';
      const long = '一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五';
      entry.content = long;
      expect(contentsTitle(entry).length).assertEqual(30);
    })

    it('emptyEverythingReturnsEmptyForUntitledRendering', 0, () => {
      const entry = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      expect(contentsTitle(entry)).assertEqual('');
    })

    // ---- heroSubtitle（用户副标题优先 → 年月跨度，同月只写一个） ----

    it('customSubtitleWinsAfterTrim', 0, () => {
      const a = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      const b = makeEntry(noon(2026, 9, 1), noon(2026, 9, 1));
      expect(heroSubtitle('  我的旅行手记 ', [a, b], 'zh-Hans'))
        .assertEqual('我的旅行手记');
    })

    it('sameMonthWritesSingleMonth', 0, () => {
      const a = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      const b = makeEntry(noon(2026, 8, 15), noon(2026, 8, 15));
      expect(heroSubtitle(undefined, [a, b], 'zh-Hans')).assertEqual('2026年8月');
    })

    it('spanMonthsJoinedWithDash', 0, () => {
      const a = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      const b = makeEntry(noon(2026, 10, 2), noon(2026, 10, 2));
      expect(heroSubtitle('', [a, b], 'zh-Hans')).assertEqual('2026年8月 — 2026年10月');
    })

    it('spanFollowsAppLanguage', 0, () => {
      const a = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      const b = makeEntry(noon(2026, 10, 2), noon(2026, 10, 2));
      const subtitle = heroSubtitle(undefined, [a, b], 'en');
      expect(subtitle.includes('August')).assertTrue();
      expect(subtitle.includes('October')).assertTrue();
    })

    it('emptyBookWithoutSubtitleIsEmpty', 0, () => {
      expect(heroSubtitle(undefined, [], 'zh-Hans')).assertEqual('');
      expect(heroSubtitle('   ', [], 'zh-Hans')).assertEqual('');
    })

    // ---- bookMonthGroups（按月切段、编号连续、跨年边界） ----

    it('groupsByMonthWithContinuousNumbers', 0, () => {
      const aug1 = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      const aug2 = makeEntry(noon(2026, 8, 20), noon(2026, 8, 20));
      const sep1 = makeEntry(noon(2026, 9, 1), noon(2026, 9, 1));
      const groups = bookMonthGroups([aug1, aug2, sep1], 'zh-Hans');
      expect(groups.length).assertEqual(2);
      expect(groups[0].title).assertEqual('2026年8月');
      expect(groups[0].items.length).assertEqual(2);
      expect(groups[1].title).assertEqual('2026年9月');
      expect(groups[1].items.length).assertEqual(1);
      expect(groups[0].items[0].number).assertEqual(1);
      expect(groups[0].items[1].number).assertEqual(2);
      expect(groups[1].items[0].number).assertEqual(3);
    })

    it('decemberToJanuarySplitsByYear', 0, () => {
      const dec = makeEntry(noon(2025, 12, 31), noon(2025, 12, 31));
      const jan = makeEntry(noon(2026, 1, 1), noon(2026, 1, 1));
      const groups = bookMonthGroups([dec, jan], 'zh-Hans');
      expect(groups.length).assertEqual(2);
      expect(groups[0].title).assertEqual('2025年12月');
      expect(groups[1].title).assertEqual('2026年1月');
    })

    it('dayTitleFollowsAppLanguage', 0, () => {
      const entry = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      const zh = bookMonthGroups([entry], 'zh-Hans');
      const en = bookMonthGroups([entry], 'en');
      expect(zh[0].items[0].dayTitle).assertEqual('8月1日');
      expect(en[0].items[0].dayTitle).assertEqual('Aug 1');
    })

    it('emptyEntriesNoGroups', 0, () => {
      expect(bookMonthGroups([], 'zh-Hans').length).assertEqual(0);
    })

    it('itemCarriesEntryForGridThumbnails', 0, () => {
      const entry = makeEntry(noon(2026, 8, 1), noon(2026, 8, 1));
      const groups = bookMonthGroups([entry], 'zh-Hans');
      const item: BookContentsItem = groups[0].items[0];
      expect(item.entry.id).assertEqual(entry.id);
    })
  })
}
