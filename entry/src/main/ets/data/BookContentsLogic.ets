/**
 * 日记本主页的纯逻辑（10_BUILD_MANUAL.md 3.3）。对应 iOS
 * `Views/Home/BookDetailView.swift` 的 `readingEntries` / `heroSubtitle`
 * + `BookHome/BookContentsView.swift` 的 `monthGroups` / `titleText`
 * + `Reader/PageDataSource.swift` 的 `readingOrder`。
 *
 * 全部纯函数：阅读顺序过滤排序、标题回退链、年月跨度副标题、按月分组。
 * 目录的渲染在 `views/shelf/BookContentsView`，数据形状在这里，单测见
 * BookContentsLogic.test.ets。
 */
import { JournalEntry } from '../models/JournalEntry';
import { shortDate, yearMonthKey } from '../services/AppDateFormatters';

/** 目录里的一篇：编号（全书第几篇）+ 行文案（标题 / 日期）+ 日记本体（宫格缩略用） */
export class BookContentsItem {
  /** 全书第几篇（1 起，和翻页阅读器往后翻的方向一致，R-BOOK-10） */
  readonly number: number;
  /** 「9月27日」/「Sep 27」 */
  readonly dayTitle: string;
  /** 回退后的标题；'' = 无题（渲染层显示「无题」资源） */
  readonly title: string;
  readonly entry: JournalEntry;

  constructor(number: number, dayTitle: string, title: string, entry: JournalEntry) {
    this.number = number;
    this.dayTitle = dayTitle;
    this.title = title;
    this.entry = entry;
  }
}

/** 目录的一个月分组（沿用阅读顺序，组内不重排） */
export class BookMonthGroup {
  /** 组键「2026-9」（非显示文案） */
  readonly id: string;
  /** 「2026年9月」/「September 2026」 */
  readonly title: string;
  items: BookContentsItem[] = [];

  constructor(id: string, title: string) {
    this.id = id;
    this.title = title;
  }
}

/**
 * 阅读顺序（R-READ-01 / R-BOOK-10）：`date` 升序、同一天按 `createdAt` 升序。
 * 不改入参（拷贝再排）。
 */
export function readingOrderSort(entries: JournalEntry[]): JournalEntry[] {
  const sorted = entries.slice();
  sorted.sort((a: JournalEntry, b: JournalEntry): number =>
    a.date !== b.date ? a.date - b.date : a.createdAt - b.createdAt);
  return sorted;
}

/**
 * 这本里的日记，按阅读顺序排好（iOS `BookDetailView.readingEntries`）。
 * `notebookName` 空 = 全部日记（一篇不落）。
 */
export function bookReadingEntries(allEntries: JournalEntry[], notebookName: string): JournalEntry[] {
  const belongs = notebookName.length === 0
    ? allEntries.slice()
    : allEntries.filter((entry: JournalEntry): boolean => entry.tags.includes(notebookName));
  return readingOrderSort(belongs);
}

/**
 * 目录标题回退链（iOS `BookContentsView.titleText`）：
 * 标题（去首尾空白）→ 正文第一行（去首尾空白，截前 30 字）→ ''（渲染层显示「无题」）。
 */
export function contentsTitle(entry: JournalEntry): string {
  const title = entry.title.trim();
  if (title.length > 0) {
    return title;
  }
  const lines = entry.textPreview.split('\n');
  const firstLine = lines.length > 0 ? lines[0].trim() : '';
  return firstLine.length > 30 ? firstLine.substring(0, 30) : firstLine;
}

/**
 * 大图上的副标题（iOS `heroSubtitle`）：用户写了副标题就用它（去首尾空白），
 * 没写就是这本日记跨越的年月（同月只写一个）；本子是空的 / 也没有副标题 → ''。
 */
export function heroSubtitle(customSubtitle: string | undefined,
  entries: JournalEntry[], appLanguage: string): string {
  const custom = (customSubtitle ?? '').trim();
  if (custom.length > 0) {
    return custom;
  }
  if (entries.length === 0) {
    return '';
  }
  const start = yearMonthKey(new Date(entries[0].date), appLanguage);
  const end = yearMonthKey(new Date(entries[entries.length - 1].date), appLanguage);
  return start === end ? start : `${start} — ${end}`;
}

/** 目录按月分组（沿用阅读顺序切段），编号全书连续（1 起） */
export function bookMonthGroups(entries: JournalEntry[], appLanguage: string): BookMonthGroup[] {
  const groups: BookMonthGroup[] = [];
  let number = 0;
  for (const entry of entries) {
    number++;
    const date = new Date(entry.date);
    const id = `${date.getFullYear()}-${date.getMonth() + 1}`;
    const item = new BookContentsItem(number, shortDate(date, appLanguage),
      contentsTitle(entry), entry);
    const last = groups.length > 0 ? groups[groups.length - 1] : undefined;
    if (last !== undefined && last.id === id) {
      last.items.push(item);
    } else {
      const group = new BookMonthGroup(id, yearMonthKey(date, appLanguage));
      group.items.push(item);
      groups.push(group);
    }
  }
  return groups;
}
