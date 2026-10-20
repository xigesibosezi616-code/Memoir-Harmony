/**
 * Notebook 名字规则与封面颜色单测（10_BUILD_MANUAL.md 1.3）。
 *
 * 覆盖验收要求的全部边界：同名不同大小写（nameKey）、全角折叠（NFKC）、
 * uniqueName / singleNotebook / nextSortOrder、下架颜色映射（含 getter 兜底）、
 * 封面标题折行。
 */
import { describe, it, expect } from '@ohos/hypium';
import { BookColor, Notebook, nameKey, cleanedName, isNameTaken,
  uniqueName, singleNotebook, nextSortOrder, retiredColorReplacement,
  bookColorFromRaw, DEFAULT_NOTEBOOK_NAMES, coverDisplayName, quietestColor,
  BOOK_COLOR_ORDER } from '../../main/ets/models/Notebook';
import { countNotebookUsage, ShelfEntryCounts } from '../../main/ets/data/NotebookRepository';

function makeNotebook(id: string, name: string): Notebook {
  return new Notebook(id, name, 100, 100);
}

export default function notebookTest() {
  describe('NotebookTest', () => {
    // ---- 判重键：忽略大小写与全半角，只去首尾空白 ----

    it('nameKeyFoldsCaseWidthAndTrims', 0, () => {
      expect(nameKey('Travel')).assertEqual('travel');
      expect(nameKey('Ｔｒａｖｅｌ')).assertEqual('travel'); // 全角拉丁
      expect(nameKey(' 旅行 ')).assertEqual('旅行');
      expect(nameKey('Travel') === nameKey('ｔｒａｖｅｌ')).assertTrue();
    })

    it('cleanedNameOnlyTrimsEnds', 0, () => {
      expect(cleanedName('  内 空格  ')).assertEqual('内 空格');
    })

    // 边界：同名不同大小写算同一本
    it('isNameTakenMatchesCaseAndWidthInsensitively', 0, () => {
      expect(isNameTaken('TRAVEL', ['travel'])).assertTrue();
      expect(isNameTaken(' 旅行', ['旅行'])).assertTrue();
      expect(isNameTaken('trip', ['travel'])).assertFalse();
    })

    // ---- 起名 ----

    it('uniqueNameReturnsCleanedWhenFree', 0, () => {
      expect(uniqueName(' 旅行 ', ['生活'])).assertEqual('旅行');
    })

    it('uniqueNameAppendsNumberOnCollision', 0, () => {
      expect(uniqueName('旅行', ['旅行'])).assertEqual('旅行 2');
      expect(uniqueName('旅行', ['旅行', '旅行 2'])).assertEqual('旅行 3');
    })

    it('uniqueNameCollisionIgnoresCase', 0, () => {
      expect(uniqueName('Travel', ['TRAVEL'])).assertEqual('Travel 2');
    })

    // ---- 单本规则（R-BOOK-01：多于一本不猜，退回全部日记） ----

    it('singleNotebookKeepsOnlyUniqueOne', 0, () => {
      expect(singleNotebook(['旅行']).length).assertEqual(1);
      expect(singleNotebook(['旅行', '旅行']).length).assertEqual(1);
      expect(singleNotebook([]).length).assertEqual(0);
      expect(singleNotebook(['旅行', '工作']).length).assertEqual(0);
    })

    // ---- 书架顺序：新建的排最后 ----

    it('nextSortOrderIsMaxPlusOne', 0, () => {
      expect(nextSortOrder([])).assertEqual(0);
      expect(nextSortOrder([0])).assertEqual(1);
      expect(nextSortOrder([0, 3, 1])).assertEqual(4);
      expect(nextSortOrder([5, 2])).assertEqual(6);
    })

    // ---- 颜色：下架映射 + getter 三级兜底 ----

    it('retiredColorsMapToNearestKept', 0, () => {
      expect(retiredColorReplacement('RustRed')).assertEqual(BookColor.WineRed);
      expect(retiredColorReplacement('OliveBrown')).assertEqual(BookColor.PineGreen);
      expect(retiredColorReplacement('BronzeBrown')).assertEqual(BookColor.AmberBrown);
      expect(retiredColorReplacement('Camel')).assertEqual(BookColor.AmberBrown);
      expect(retiredColorReplacement('WineRed')).assertUndefined();
    })

    it('bookColorGetterResolvesRetiredThenFallsBack', 0, () => {
      const notebook = makeNotebook('n1', '生活');
      expect(notebook.bookColor).assertEqual(BookColor.WineRed); // 默认酒红
      notebook.colorId = 'Slate';
      expect(notebook.bookColor).assertEqual(BookColor.Slate);
      notebook.colorId = 'RustRed'; // 下架色 → 就近映射
      expect(notebook.bookColor).assertEqual(BookColor.WineRed);
      notebook.colorId = 'FutureColor'; // 更新版本加的色 → 不猜，回落酒红
      expect(notebook.bookColor).assertEqual(BookColor.WineRed);
    })

    it('bookColorFromRawRoundTripsAllKeptColors', 0, () => {
      const all: string[] = ['WineRed', 'PineGreen', 'PrussianBlue', 'Eggplant',
        'AmberBrown', 'Charcoal', 'Slate', 'Ivory'];
      for (const raw of all) {
        expect(bookColorFromRaw(raw) !== undefined).assertTrue();
      }
      expect(bookColorFromRaw('Nope')).assertUndefined();
    })

    // ---- 封面标题：每行最多 4 字自动折行 ----

    it('displayNameFoldsAtFourChars', 0, () => {
      expect(makeNotebook('n1', '旅行').displayName).assertEqual('旅行');
      expect(makeNotebook('n2', '读书笔记').displayName).assertEqual('读书笔记');
      expect(makeNotebook('n3', '读书笔记本').displayName).assertEqual('读书笔记\n本');
    })

    it('defaultNotebookNamesAreUserData', 0, () => {
      expect(DEFAULT_NOTEBOOK_NAMES.length).assertEqual(4);
      expect(DEFAULT_NOTEBOOK_NAMES[0]).assertEqual('生活');
    })

    // ---- 3.1 书架：封面标题折行（coverDisplayName） ----

    it('coverDisplayNameKeepsShortNamesUnfolded', 0, () => {
      expect(coverDisplayName('旅行')).assertEqual('旅行');
      expect(coverDisplayName('读书笔记')).assertEqual('读书笔记'); // 恰好 4 字不折
      expect(coverDisplayName('')).assertEqual('');
    })

    it('coverDisplayNameFoldsCjkEveryFourChars', 0, () => {
      expect(coverDisplayName('读书笔记本')).assertEqual('读书笔记\n本'); // 5 字
      expect(coverDisplayName('一二三四五六七八')).assertEqual('一二三四\n五六七八'); // 恰 8 字
      expect(coverDisplayName('一二三四五六七八九')).assertEqual('一二三四\n五六七八\n九'); // 9 字
    })

    it('coverDisplayNameLeavesLatinNamesToSystemWrap', 0, () => {
      expect(coverDisplayName('All Entries')).assertEqual('All Entries'); // 拉丁字母不硬折
      expect(coverDisplayName('读书abc本')).assertEqual('读书abc本'); // 混排含字母整体交给系统
    })

    // ---- 3.1 书架：顺手新建取色（quietestColor，iOS TagSelector） ----

    it('quietestColorReturnsFirstDeclaredWhenShelfEmpty', 0, () => {
      // 一本都没有：并列全 0，按声明序取第一个（酒红）；iOS 的 ?? .pineGreen 永不触发
      expect(quietestColor([])).assertEqual(BookColor.WineRed);
    })

    it('quietestColorPicksLeastUsed', 0, () => {
      const first = makeNotebook('n1', '生活'); // 默认酒红
      const second = makeNotebook('n2', '工作');
      second.colorId = BookColor.WineRed;
      const third = makeNotebook('n3', '旅行');
      third.colorId = BookColor.PineGreen;
      // 酒红 2 本、墨绿 1 本 → 下一个最少用且并列取声明序：普鲁士蓝
      expect(quietestColor([first, second, third])).assertEqual(BookColor.PrussianBlue);
    })

    it('quietestColorTieBreaksByDeclarationOrder', 0, () => {
      const only = makeNotebook('n1', '生活');
      only.colorId = BookColor.PineGreen;
      // 墨绿 1 本，其余全 0 → 并列取声明序第一个：酒红
      expect(quietestColor([only])).assertEqual(BookColor.WineRed);
    })

    it('quietestColorNeverReturnsIvory', 0, () => {
      const books: Notebook[] = [];
      const order: BookColor[] = [BookColor.WineRed, BookColor.PineGreen,
        BookColor.PrussianBlue, BookColor.Eggplant, BookColor.AmberBrown,
        BookColor.Charcoal, BookColor.Slate];
      for (let i = 0; i < order.length; i++) {
        const nb = makeNotebook(`n${i}`, `本${i}`);
        nb.colorId = order[i];
        books.push(nb);
      }
      // 象牙白以外全用过 1 次 → 并列取声明序第一个非象牙白 = 酒红，绝不给象牙白
      expect(quietestColor(books)).assertEqual(BookColor.WineRed);
      expect(order.indexOf(BookColor.Ivory) < 0).assertTrue();
    })

    it('bookColorOrderMatchesIosAllCases', 0, () => {
      expect(BOOK_COLOR_ORDER.length).assertEqual(8);
      expect(BOOK_COLOR_ORDER[0]).assertEqual(BookColor.WineRed);
      expect(BOOK_COLOR_ORDER[BOOK_COLOR_ORDER.length - 1]).assertEqual(BookColor.Ivory);
    })

    // ---- 3.1 书架：篇数汇总（countNotebookUsage / ShelfEntryCounts） ----

    it('countNotebookUsageAggregatesByNotebookName', 0, () => {
      const counts = countNotebookUsage([['生活'], [], ['旅行'], ['生活'], []]);
      expect(counts['生活']).assertEqual(2);
      expect(counts['旅行']).assertEqual(1);
      expect(counts['工作']).assertUndefined();
    })

    it('shelfEntryCountsCountForFallsBackToZero', 0, () => {
      const counts = new ShelfEntryCounts({ '生活': 3 }, 5);
      expect(counts.countFor('生活')).assertEqual(3);
      expect(counts.countFor('没有的本')).assertEqual(0);
      expect(counts.total).assertEqual(5);
    })
  })
}
