/**
 * 写作日历（10_BUILD_MANUAL.md 6.3；对应 iOS `StatsView.swift` 里的
 * `WritingCalendar`）—— **真实月历排布**，不是 1→31 的平铺网格。
 *
 * - 按星期对齐：1 号落在它真正的星期列上，前面补空格
 * - 可翻月（不给看未来的月份，那里不可能有日记）
 * - 可点：有日记的那天点进去弹当天列表（弹层由 StatsView 出，这里只回调）
 * - 星期表头与首日跟随 App 语言（zh/en 周日起，fr/es 周一起；
 *   AppDateFormatters.weekdayNarrowSymbols 已按首日轮转好）
 *
 * 布局：7 列手动 Row 分行（不用 Grid——嵌套在页面 Scroll 里滚动手势易打架）。
 */
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../../services/LanguageManager';
import { firstWeekdayIndex, weekdayNarrowSymbols, yearMonthKey } from '../../../services/AppDateFormatters';

/** 一天的篇数（父组件把日记按本地 0 点分好组再喂进来，日历格子和当天列表共用一份） */
export class CalendarDayCount {
  readonly dayMs: number;
  readonly count: number;

  constructor(dayMs: number, count: number) {
    this.dayMs = dayMs;
    this.count = count;
  }
}

/** 一格：dayMs < 0 表示当月外的占位格（把 1 号顶到正确的星期列上） */
class CalendarCell {
  readonly key: string;
  readonly dayMs: number;
  readonly dayNum: number;
  readonly count: number;
  readonly isToday: boolean;

  constructor(key: string, dayMs: number, dayNum: number, count: number, isToday: boolean) {
    this.key = key;
    this.dayMs = dayMs;
    this.dayNum = dayNum;
    this.count = count;
    this.isToday = isToday;
  }
}

@Component
export struct WritingCalendarView {
  /** 每天各写了几篇（本地 0 点毫秒 → 篇数） */
  @Prop dayCounts: CalendarDayCount[] = [];
  /** 点了有日记的那天（dayMs = 本地 0 点毫秒） */
  onPickDay: (dayMs: number) => void = (): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';

  /** 正在看的月份（取该月任意一天即可，翻月时整体 ±1 月） */
  @State private monthAnchorMs: number = Date.now();

  build() {
    Column({ space: 10 }) {
      // 月份导航：翻月按钮 + 居中月标题
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.textSecondary])
          .width(32)
          .height(28)
          .onClick((): void => {
            this.shiftMonth(-1);
          })
        Blank()
        Text(yearMonthKey(new Date(this.monthAnchorMs), this.appLanguage))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textSecondary)
        Blank()
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.canGoForward() ? this.theme.textSecondary : this.theme.textTertiary])
          .opacity(this.canGoForward() ? 1 : 0.35)
          .width(32)
          .height(28)
          .onClick((): void => {
            if (this.canGoForward()) {
              this.shiftMonth(1);
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 星期表头（已按语言首日轮转）
      Row({ space: 4 }) {
        ForEach(weekdayNarrowSymbols(this.appLanguage), (symbol: string) => {
          Text(symbol)
            .fontSize(10)
            .fontColor(this.theme.textTertiary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        }, (symbol: string, index: number): string => `${index}-${symbol}`)
      }
      .width('100%')

      // 日期格：按星期分行
      Column({ space: 4 }) {
        ForEach(this.monthRows(), (row: CalendarCell[]) => {
          Row({ space: 4 }) {
            ForEach(row, (cell: CalendarCell) => {
              this.dayCell(cell)
            }, (cell: CalendarCell): string => cell.key)
          }
          .width('100%')
          // key 必须含月份和各行篇数：ForEach 同 key 不重渲染，
          // 翻月 / dayCounts 变化时 key 变了才会重建格子（否则停在旧渲染）
        }, (row: CalendarCell[], index: number): string =>
        `row-${this.monthAnchorMs}-${index}-${row.map((c: CalendarCell): string => `${c.count}`).join('_')}`)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 一格日期：有日记 accent 底可点；今天描一圈（没写也能定位「今天在哪」）----

  @Builder
  private dayCell(cell: CalendarCell) {
    if (cell.dayMs < 0) {
      // 占位格：撑住列宽
      Column()
        .layoutWeight(1)
        .aspectRatio(1)
    } else {
      Column() {
        Text(`${cell.dayNum}`)
          .fontSize(11)
          .fontWeight(cell.count > 0 ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(cell.count > 0 ? this.theme.background : this.theme.textTertiary)
      }
      .layoutWeight(1)
      .aspectRatio(1)
      .justifyContent(FlexAlign.Center)
      .borderRadius(5)
      .backgroundColor(cell.count > 0 ? this.theme.accent : this.theme.surfaceBackground)
      .border({
        width: cell.isToday ? 1.2 : 0,
        color: cell.isToday ? this.theme.textPrimary : Color.Transparent
      })
      .onClick((): void => {
        if (cell.count > 0) {
          this.onPickDay(cell.dayMs);
        }
      })
    }
  }

  // ---- 数据 ----

  /** 当月格子（前置占位 + 实际日期），按 7 个一行切好 */
  private monthRows(): CalendarCell[][] {
    const anchor = new Date(this.monthAnchorMs);
    const year = anchor.getFullYear();
    const month = anchor.getMonth();
    const first = new Date(year, month, 1);
    // 1 号是星期几 → 前面空几格（首日随语言：周日起 or 周一起）
    const leading = (first.getDay() - firstWeekdayIndex(this.appLanguage) + 7) % 7;
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const today = new Date();
    const todayMs = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();

    const cells: CalendarCell[] = [];
    for (let i = 0; i < leading; i++) {
      cells.push(new CalendarCell(`blank-${i}`, -1, 0, 0, false));
    }
    for (let day = 1; day <= daysInMonth; day++) {
      const dayMs = new Date(year, month, day).getTime();
      const count = this.countForDay(dayMs);
      cells.push(new CalendarCell(`d-${dayMs}-c${count}`, dayMs, day, count, dayMs === todayMs));
    }
    // 行尾补占位：否则不满 7 格的末行会被 layoutWeight 拉宽、aspectRatio 撑成大方块
    const trailing = (7 - cells.length % 7) % 7;
    for (let i = 0; i < trailing; i++) {
      cells.push(new CalendarCell(`blank-t-${i}`, -1, 0, 0, false));
    }

    const rows: CalendarCell[][] = [];
    for (let i = 0; i < cells.length; i += 7) {
      const row: CalendarCell[] = [];
      for (let j = i; j < Math.min(i + 7, cells.length); j++) {
        row.push(cells[j]);
      }
      rows.push(row);
    }
    return rows;
  }

  /** 这天写了几篇（dayCounts 里查；几十项线性扫足够） */
  private countForDay(dayMs: number): number {
    for (const day of this.dayCounts) {
      if (day.dayMs === dayMs) {
        return day.count;
      }
    }
    return 0;
  }

  /** 能不能再往后翻——不给看未来的月份 */
  private canGoForward(): boolean {
    const anchor = new Date(this.monthAnchorMs);
    const now = new Date();
    const shown = anchor.getFullYear() * 12 + anchor.getMonth();
    const current = now.getFullYear() * 12 + now.getMonth();
    return shown < current;
  }

  /** 翻月（±1 自然月） */
  private shiftMonth(delta: number): void {
    const anchor = new Date(this.monthAnchorMs);
    this.monthAnchorMs = new Date(anchor.getFullYear(), anchor.getMonth() + delta, 1).getTime();
  }
}
