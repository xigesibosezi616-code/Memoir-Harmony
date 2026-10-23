/**
 * 大屏模式的纯逻辑（10_BUILD_MANUAL.md 3.6 + U06 R-HOME-08/09/10）。
 * 对应 iOS `Views/Home/Overview/` 的 ShowcaseZoom / EntryDigest / OverviewLayout /
 * ShowcaseQuadPager 里的计算部分 + `ShowcaseView` 的图文配比。
 *
 * 全部「数据进、数据出」：级别几何、digest 缓存、四宫格分页、总览按月分组、
 * 「手指底下是哪篇」的版式换算，单测跑穿；UI 层只管渲染。
 *
 * 🔴 不卡铁律（U06 R-HOME-10）：digest 按「日记 id + 改过时间 + 日期 + App 语言」
 * 算一次记下来；正文 JSON 不在画格子时反复解。
 */
import { JournalEntry } from './JournalEntry';
import { presetMoodColorHex } from './Mood';
import { dayAndWeekday, dayShortWithWeekday, yearMonthKey } from '../services/AppDateFormatters';

/** 大屏一屏放几篇（U06 R-HOME-08）。0=一屏一篇（原大卡片）→ 3=六十四篇 */
export enum ShowcaseZoomLevel {
  One = 0,
  Four = 1,
  Sixteen = 2,
  SixtyFour = 3
}

/** 宫格每格宽高比（宽 / 高，U06 R-HOME-08） */
export const SHOWCASE_CELL_ASPECT: number = 0.66;
/** 宫格两边留白（与大卡片同款） */
export const SHOWCASE_GRID_MARGIN: number = 18;
/** 总览月份标题行高（定死，版式换算要用） */
export const SHOWCASE_MONTH_HEADER_HEIGHT: number = 34;
/** 四宫格一页几篇 */
export const QUAD_PAGE_SIZE: number = 4;
/** 翻页两级卡片距屏幕边（左右各 18 / 上下各 8，iOS cardSize 同款） */
export const SHOWCASE_CARD_SIDE_MARGIN: number = 18;
export const SHOWCASE_CARD_TOP_MARGIN: number = 8;

/** 一行几篇：1 / 2 / 4 / 8（列数翻倍） */
export function zoomColumns(zoom: number): number {
  return 1 << zoom;
}

/** 占位 digest（id=''）：总览尾行不满时补位，与真格同尺寸、不渲染内容 */
export function overviewFillerDigest(): EntryDigest {
  return new EntryDigest('', '', '', '', '', '', '', 0, '', '', 0);
}

/**
 * 总览一行补满到 `cols` 列（2026-10-23 真机反馈「第三档尾行拉成大卡」）。
 * 相册逻辑：尾行不满就**留空**，格子保持同尺寸——行内 layoutWeight(1) 会把
 * 不满的行里唯一那格拉成全宽大卡（本月 5 篇 → 第二行 1 格全宽，实锤）。
 * 满行原样返回（length === cols 无占位）。
 */
export function padOverviewRow(row: EntryDigest[], cols: number): EntryDigest[] {
  const padded: EntryDigest[] = [];
  for (const digest of row) {
    padded.push(digest);
  }
  while (padded.length < cols) {
    padded.push(overviewFillerDigest());
  }
  return padded;
}

/** 格间空隙：越密越窄（12 / 8 / 4；一屏一篇由卡片自身留白，无格间距） */
export function zoomSpacing(zoom: number): number {
  if (zoom === ShowcaseZoomLevel.Four) {
    return 12;
  }
  if (zoom === ShowcaseZoomLevel.Sixteen) {
    return 8;
  }
  if (zoom === ShowcaseZoomLevel.SixtyFour) {
    return 4;
  }
  return 0;
}

/** 格子圆角：跟着格子一起缩（四篇 16 / 十六篇 10 / 六十四篇 6；大卡片 26） */
export function zoomCornerRadius(zoom: number): number {
  if (zoom === ShowcaseZoomLevel.One) {
    return 26;
  }
  if (zoom === ShowcaseZoomLevel.Four) {
    return 16;
  }
  if (zoom === ShowcaseZoomLevel.Sixteen) {
    return 10;
  }
  return 6;
}

/** 照片解多大（最长边像素，U06 R-HOME-10：按要显示的大小解，不多解） */
export function zoomPhotoPixels(zoom: number): number {
  if (zoom === ShowcaseZoomLevel.One) {
    return 1400;
  }
  if (zoom === ShowcaseZoomLevel.Four) {
    return 600;
  }
  if (zoom === ShowcaseZoomLevel.Sixteen) {
    return 300;
  }
  return 160;
}

/** 捏合的换级阈值（U06 R-HOME-09：按次数不按力度） */
export const PINCH_OUT_SCALE: number = 0.8;
export const PINCH_IN_SCALE: number = 1.25;

// ---- 大卡片尺寸（2026-10-23 真机反馈「细长」修正） ----

/**
 * 大卡片宽高比钳在 [2:3, 3:2]（宽:高）。iOS 在 iPhone 上按「填满可用区」出尺寸
 * （宽−36、高−16），到了鸿蒙细长外屏（X6 折叠态 1080×2440，屏比 2.26）
 * 同一套会拉出 0.575 的竖条卡，照片下压一大块空 tint；反过来展开态/平板
 * 这种近方、宽扁容器又不能把宽也钳死（2026-10-23 真机实测：展开容器
 * 716.8×554.2vp，纯 2:3 上限把卡钳成 358.7vp 窄竖条，两侧各 179vp 空带）。
 * 所以对称钳：太细长钳高到 2:3，太宽扁钳宽到 3:2，中间（折叠展开、近方）
 * 填满可用区。
 */
export const SHOWCASE_CARD_ASPECT: number = 2 / 3;

/**
 * 大卡片尺寸：以「填满可用区」（宽−36、高−16）为基线，宽高比只许在
 * [2:3, 3:2] 之间——细长屏（折叠手机）上高被比例掐住，宽扁容器上宽被
 * 掐住，其余填满。
 */
export function showcaseCardSize(containerWidth: number, containerHeight: number):
  [number, number] {
  let width = Math.max(0, containerWidth - 36);
  let height = Math.max(0, containerHeight - 16);
  if (width > height * 1.5) {
    width = height * 1.5;
  } else if (width * 1.5 < height) {
    height = width * 1.5;
  }
  return [width, height];
}

// ---- 图文配比（R-HOME-06：字越多照片让位越多） ----

/** 大卡片照片区高度占比（0.86 / 0.70 / 0.60 / 0.52 / 0.46） */
export function cardImageRatio(previewLength: number): number {
  if (previewLength <= 0) {
    return 0.86;
  }
  if (previewLength < 40) {
    return 0.70;
  }
  if (previewLength < 120) {
    return 0.60;
  }
  if (previewLength < 240) {
    return 0.52;
  }
  return 0.46;
}

/** 大卡片正文行数上限（0 / 3 / 5 / 8 / 11），超出以 … 截断 */
export function cardTextLines(previewLength: number): number {
  if (previewLength <= 0) {
    return 0;
  }
  if (previewLength < 40) {
    return 3;
  }
  if (previewLength < 120) {
    return 5;
  }
  if (previewLength < 240) {
    return 8;
  }
  return 11;
}

// ---- digest（一屏格子要显示的东西，算一次记下来） ----

/**
 * 一篇日记在总览 / 四宫格里的显示数据（iOS `EntryDigest`）。
 * title 空串 = 没标题也没正文首行（显示方走「无题」）。
 */
export class EntryDigest {
  /** 日记 id */
  readonly id: string;
  /** 标题；没写标题用正文第一行（≤30 字）；都空是 '' */
  readonly title: string;
  /** 正文纯文字预览（文本块 `\n` 连接、去首尾空白） */
  readonly preview: string;
  /** 封面照片文件名；'' = 没照片 */
  readonly cover: string;
  /** 心情 key；'' = 没选 */
  readonly moodKey: string;
  /** 心情色 '#RRGGBB'（entry.moodColorHex，缺时按预设 key 兜底）；'' = 没有 */
  readonly moodColorHex: string;
  /** 「2026年10月」/「October 2026」：总览按它分组 */
  readonly monthKey: string;
  /** 年 × 100 + 月：分组比字符串快 */
  readonly month: number;
  /** 「10月19日 星期一」 */
  readonly dayAndWeekday: string;
  /** 「19日 周一」/「Mon 19」（十六篇格子的小字日期） */
  readonly dayWithWeekday: string;
  /** 几号（六十四篇格子左下角的数字） */
  readonly day: number;

  constructor(id: string, title: string, preview: string, cover: string,
    moodKey: string, moodColorHex: string, monthKey: string, month: number,
    dayAndWeekday: string, dayWithWeekday: string, day: number) {
    this.id = id;
    this.title = title;
    this.preview = preview;
    this.cover = cover;
    this.moodKey = moodKey;
    this.moodColorHex = moodColorHex;
    this.monthKey = monthKey;
    this.month = month;
    this.dayAndWeekday = dayAndWeekday;
    this.dayWithWeekday = dayWithWeekday;
    this.day = day;
  }
}

/** 缓存签名：改过时间 / 日期 / App 语言任一变化就重算 */
class DigestStamp {
  readonly updatedAt: number;
  readonly date: number;
  readonly locale: string;

  constructor(updatedAt: number, date: number, locale: string) {
    this.updatedAt = updatedAt;
    this.date = date;
    this.locale = locale;
  }

  same(other: DigestStamp): boolean {
    return this.updatedAt === other.updatedAt
      && this.date === other.date && this.locale === other.locale;
  }
}

const digestCache: Map<string, EntryDigest> = new Map();
const digestStamps: Map<string, DigestStamp> = new Map();

/** 清空 digest 缓存（测试用） */
export function clearDigestCache(): void {
  digestCache.clear();
  digestStamps.clear();
}

/** 无标题时的正文首行截断（iOS `prefix(30)`） */
const TITLE_FALLBACK_LIMIT: number = 30;

/**
 * 一篇日记的显示 digest（带缓存，iOS `EntryDigest.of`）。
 * 正文 JSON 只在 miss 时解一次；日期写法、月份 key 同步算好。
 */
export function digestOf(entry: JournalEntry, appLanguage: string): EntryDigest {
  const stamp = new DigestStamp(entry.updatedAt, entry.date, appLanguage);
  const cached = digestCache.get(entry.id);
  const cachedStamp = cached !== undefined ? digestStamps.get(entry.id) : undefined;
  if (cached !== undefined && cachedStamp !== undefined && cachedStamp.same(stamp)) {
    return cached;
  }

  const date = new Date(entry.date);
  const preview = entry.textPreview;
  const trimmedTitle = entry.title.trim();
  let title = trimmedTitle;
  if (title.length === 0 && preview.length > 0) {
    const firstLine = preview.split('\n')[0].trim();
    title = firstLine.length > TITLE_FALLBACK_LIMIT
      ? firstLine.substring(0, TITLE_FALLBACK_LIMIT) : firstLine;
  }
  const coverName = entry.coverPhotoFilename;
  let moodColor = entry.moodColorHex ?? '';
  if (moodColor.length === 0 && entry.mood.length > 0) {
    moodColor = presetMoodColorHex(entry.mood) ?? '';
  }
  const digest = new EntryDigest(
    entry.id,
    title,
    preview,
    coverName ?? '',
    entry.mood,
    moodColor,
    yearMonthKey(date, appLanguage),
    date.getFullYear() * 100 + (date.getMonth() + 1),
    dayAndWeekday(date, appLanguage),
    dayShortWithWeekday(date, appLanguage),
    date.getDate()
  );
  digestCache.set(entry.id, digest);
  digestStamps.set(entry.id, stamp);
  return digest;
}

// ---- 四宫格分页（U06 第 1 级：一页 2 × 2，左右翻） ----

/** 每 4 篇一页：篇数 → 页数（不满一页算一页） */
export function quadPageCount(entryCount: number): number {
  if (entryCount <= 0) {
    return 0;
  }
  return Math.ceil(entryCount / QUAD_PAGE_SIZE);
}

/** 这一页第一篇的下标 */
export function quadPageStart(page: number): number {
  return page * QUAD_PAGE_SIZE;
}

/** 某篇在第几页 */
export function quadPageOf(entryIndex: number): number {
  return Math.floor(entryIndex / QUAD_PAGE_SIZE);
}

/** 手指落在这一页的哪一格（0 左上、1 右上、2 左下、3 右下；以页面中线分） */
export function quadSlotAt(localX: number, localY: number, pageWidth: number,
  pageHeight: number): number {
  const slotX = localX > pageWidth / 2 ? 1 : 0;
  const slotY = localY > pageHeight / 2 ? 2 : 0;
  return slotX + slotY;
}

/** 手指那一格是哪篇（下标，clamp 到最后一篇；pageStart = 该页第一篇下标） */
export function quadEntryIndexAtSlot(pageStart: number, slot: number,
  entryCount: number): number {
  return Math.min(pageStart + slot, entryCount - 1);
}

/**
 * 某篇在它那一页哪一格的中心（页面比例坐标，U06 R-HOME-09：
 * 翻页两级换级转场以这一格为缩放中心）。
 */
export function quadSlotAnchor(entryIndex: number): number[] {
  const slot = entryIndex % QUAD_PAGE_SIZE;
  const x = slot % 2 === 0 ? 0.27 : 0.73;
  const y = slot < 2 ? 0.27 : 0.73;
  return [x, y];
}

// ---- 总览按月分组（第 2 / 3 级） ----

/** 总览的一个月份段：版式换算只认 count / startIndex，不持引用 */
export class DigestMonth {
  /** 年 × 100 + 月 */
  readonly month: number;
  /** 「2026年10月」/「October 2026」 */
  readonly title: string;
  /** 这个月第一篇在 entries 数组里的下标 */
  readonly startIndex: number;
  /** 这个月几篇 */
  readonly count: number;

  constructor(month: number, title: string, startIndex: number, count: number) {
    this.month = month;
    this.title = title;
    this.startIndex = startIndex;
    this.count = count;
  }
}

/**
 * 按月切段（entries 已新的在前、同月必相邻——fetchAllEntries ORDER BY date DESC
 * 保证），文字用 digest 里算好的，这里只做比较。
 */
export function overviewMonths(entries: JournalEntry[], appLanguage: string): DigestMonth[] {
  const months: DigestMonth[] = [];
  for (let i = 0; i < entries.length; i++) {
    const digest = digestOf(entries[i], appLanguage);
    const last = months.length > 0 ? months[months.length - 1] : undefined;
    if (last !== undefined && last.month === digest.month) {
      months[months.length - 1] = new DigestMonth(last.month, last.title,
        last.startIndex, last.count + 1);
    } else {
      months.push(new DigestMonth(digest.month, digest.monthKey, i, 1));
    }
  }
  return months;
}

/** 一格多大：一行 columns 格、两边留白、格间空隙扣掉，宽高比定死 */
export function overviewCellSize(pageWidth: number, zoom: number): number[] {
  const columns = zoomColumns(zoom);
  const spacing = zoomSpacing(zoom);
  const width = Math.max(1, (pageWidth - SHOWCASE_GRID_MARGIN * 2
    - spacing * (columns - 1)) / columns);
  return [width, width / SHOWCASE_CELL_ASPECT];
}

/**
 * 手指底下是哪篇（U06 R-HOME-09：月份标题、行高、间距都定死，按版式算，
 * 不靠格子上报位置）。落在月份标题上算那个月第一篇，落在缝里算最近的一格。
 *
 * - pageWidth：宫格容器宽（vp），格子大小照它算
 * - localX：手指相对**宫格容器左上角**的横坐标（vp）
 * - contentY：相对宫格内容顶部的**内容空间**纵坐标 = localY + scrollOffset
 *   （宫格在滚动容器里，滚动偏移由调用方注入）
 * - 返回 entries 下标；宫格为空返回 -1
 */
export function overviewEntryIndexAt(months: DigestMonth[], zoom: number,
  pageWidth: number, localX: number, contentY: number): number {
  if (months.length === 0) {
    return -1;
  }
  const columns = zoomColumns(zoom);
  const spacing = zoomSpacing(zoom);
  const cell = overviewCellSize(pageWidth, zoom);
  const cellWidth = cell[0];
  const cellHeight = cell[1];
  const rowStride = cellHeight + spacing;
  // 容器含两边留白：先扣左边留白再算第几列；缝里算最近的一格
  const column = Math.min(Math.max(
    Math.floor((localX - SHOWCASE_GRID_MARGIN) / (cellWidth + spacing)), 0), columns - 1);
  let y = contentY;
  for (const month of months) {
    const rows = Math.ceil(month.count / columns);
    const height = SHOWCASE_MONTH_HEADER_HEIGHT + rows * rowStride;
    if (y < height) {
      const inRows = y - SHOWCASE_MONTH_HEADER_HEIGHT;
      if (inRows < 0) {
        return month.startIndex;
      }
      const row = Math.min(Math.floor(inRows / rowStride), rows - 1);
      const index = Math.min(row * columns + column, month.count - 1);
      return month.startIndex + index;
    }
    y -= height;
  }
  const last = months[months.length - 1];
  return last.startIndex + last.count - 1;
}
