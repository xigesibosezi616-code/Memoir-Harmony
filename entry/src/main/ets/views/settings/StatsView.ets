/**
 * 设置 →「写作统计」二级页（10_BUILD_MANUAL.md 6.3）。对应 iOS
 * `Views/Settings/StatsView.swift`（情绪小结会员卡除外——U14-2 依赖
 * Stage 7 IAP，本批不做）。
 *
 * - 三张数字卡：最长连续（U16，只升不降，打开本页记一次）/ 总篇数 / 总字数
 * - 写作日历：真实月历排布，点有日记的那天弹当天列表（sheet，不 push——
 *   统计页是「看数据」的地方，看完该回到统计页）
 * - 情绪捕捉（U14-1）：走势 / 分布 / 情绪词 / 天气 / 地点 / 星期时段，
 *   全在本机算，范围四档一起跟着变；三张数字卡和日历仍是全期
 *
 * 路由：系统路由表（router_map.json → name `Stats`），设置页第二组推入。
 */
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AppDatabase } from '../../data/Database';
import { EntryRepository } from '../../data/EntryRepository';
import { AppPrefs } from '../../services/AppPrefs';
import { fullDate, weekdayNarrow, firstWeekdayIndex } from '../../services/AppDateFormatters';
import { JournalEntry } from '../../models/JournalEntry';
import { WritingStreak } from '../../models/WritingStreak';
import { StatsRange, MoodChartData, MoodSlice,
  StatsCalculator } from '../../models/StatsCalculator';
import { MoodItem, TrendPoint, LabelCount, MoodGroup,
  WeatherGroup, WeekdayGroup, DayPartGroup, MoodInsights, TrendBucket } from '../../models/MoodInsights';
import { MoodLevels } from '../../models/MoodLevel';
import { ThemedCard } from '../components/ThemedCard';
import { EntryRowView } from '../home/EntryRowView';
import { CalendarDayCount, WritingCalendarView } from './stats/WritingCalendarView';
import { StatsRangePicker, MoodDonutChart, MoodTrendChart, MoodScaleRow,
  LabelCountList } from './stats/MoodInsightCards';
import { moodLevelTitle, weatherKindTitle, dayPartTitle } from './stats/StatsText';

const DOMAIN = 0x0000;
const TAG = 'StatsView';

@Builder
function emptyInsightContent() {
}

/** 三张数字卡之一：数值 + 标题（卡片样式内联：保证 layoutWeight 等宽，不走
 * ThemedCard——尾随闭包后链不上属性，百分比宽度冒泡也不可靠） */
@Component
struct StatCard {
  title: Resource = $r('app.string.s_9392c3c977');
  @Prop value: string = '';
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Column({ space: 4 }) {
      Text(this.value)
        .fontSize(this.theme.titleFont.size)
        .fontWeight(this.theme.titleFont.weight)
        .fontFamily(this.theme.titleFont.family)
        .fontColor(this.theme.textPrimary)
      Text(this.title)
        .fontSize(this.theme.labelFont.size)
        .fontWeight(this.theme.labelFont.weight)
        .fontFamily(this.theme.labelFont.family)
        .fontColor(this.theme.textTertiary)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.theme.cardBackground)
    .borderRadius(12)
    .border({ width: 0.5, color: this.theme.border })
    .alignItems(HorizontalAlign.Start)
  }
}

/** 情绪捕捉的卡片壳：小标题 + 内容（与 iOS insightCard 同款；内容走尾随闭包） */
@Component
struct InsightCard {
  title: Resource = $r('app.string.s_9392c3c977');
  @BuilderParam content: () => void = emptyInsightContent;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    ThemedCard() {
      Column({ space: 12 }) {
        Text(this.title)
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textTertiary)
          .letterSpacing(this.theme.letterSpacingWide)
        this.content()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}

@Builder
export function StatsBuilder() {
  StatsView()
}

@Component
export struct StatsView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  @State private entries: JournalEntry[] = [];
  @State private streakDays: number = 0;
  /** 情绪捕捉那一段的时间范围（三张数字卡和写作日历仍是全期） */
  @State private moodRange: StatsRange = StatsRange.month;
  /** 点了日历上有日记的一天 → 弹当天列表 */
  @State private showDaySheet: boolean = false;
  @State private pickedDayMs: number = 0;

  private navPathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 16 }) {
            // 三张数字卡：最长连续 / 总篇数 / 总字数
            Row({ space: 12 }) {
              StatCard({ title: $r('app.string.s_d6389cc426'), value: `${this.streakDays}` })
                .layoutWeight(1)
              StatCard({ title: $r('app.string.s_282ab93d10'), value: `${this.entries.length}` })
                .layoutWeight(1)
              StatCard({ title: $r('app.string.s_b869f3199c'), value: `${this.totalWords()}` })
                .layoutWeight(1)
            }
            .width('100%')

            // 写作日历
            ThemedCard() {
              Column({ space: 12 }) {
                Text($r('app.string.s_39bd23b773'))
                  .fontSize(this.theme.captionFont.size)
                  .fontWeight(this.theme.captionFont.weight)
                  .fontFamily(this.theme.captionFont.family)
                  .fontColor(this.theme.textTertiary)
                  .letterSpacing(this.theme.letterSpacingWide)
                WritingCalendarView({
                  dayCounts: this.dayCounts(),
                  onPickDay: (dayMs: number): void => {
                    this.pickedDayMs = dayMs;
                    this.showDaySheet = true;
                  }
                })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            // 情绪捕捉（2026-10-27）：免费的这几张图全在本机算，规则见 MoodInsights
            Text($r('app.string.s_efce771fc5'))
              .fontSize(this.theme.labelFont.size)
              .fontWeight(this.theme.labelFont.weight)
              .fontFamily(this.theme.labelFont.family)
              .fontColor(this.theme.textSecondary)
              .letterSpacing(this.theme.letterSpacingWide)
              .margin({ top: 8 })

            StatsRangePicker({
              selected: this.moodRange,
              onPicked: (range: StatsRange): void => {
                this.moodRange = range;
              }
            })

            this.trendCard()
            this.donutCard()

            if (this.topLabels().length > 0) {
              InsightCard({ title: $r('app.string.s_3c76ec910a') }) {
                LabelCountList({ items: this.topLabels() })
              }
            }

            if (this.weatherRows().length > 0) {
              InsightCard({ title: $r('app.string.s_85a1088852') }) {
                Column({ space: 12 }) {
                  ForEach(this.weatherRows(), (item: WeatherGroup) => {
                    this.scaleRow(weatherKindTitle(item.kind), item.group)
                  }, (item: WeatherGroup): string => `${item.kind}-${item.group.count}-${item.group.valence}`)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }

            if (this.placeRows().length > 0) {
              InsightCard({ title: $r('app.string.s_67ad407dba') }) {
                Column({ space: 12 }) {
                  ForEach(this.placeRows(), (group: MoodGroup) => {
                    // 地名是日记上存的原样数据，不翻译
                    this.scaleRow(group.id, group)
                  }, (group: MoodGroup): string => `${group.id}-${group.count}-${group.valence}`)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }

            if (this.weekdayRows().length > 0 || this.dayPartRows().length > 0) {
              this.weekdayDayPartCard()
            }

            // 天气 / 地点 / 星期时段至少有一张没出来：说一句为什么，免得以为坏了
            if (this.needsFootnote()) {
              Text($r('app.string.s_05a978d5cb'))
                .fontSize(this.theme.captionFont.size)
                .fontWeight(this.theme.captionFont.weight)
                .fontFamily(this.theme.captionFont.family)
                .fontColor(this.theme.textTertiary)
                .padding({ left: 4, right: 4 })
            }

            Column()
              .width('100%')
              .height(this.safeAreaBottomVp + 88)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 20, right: 20, top: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        // Scroll 设高度限制后内容小于视口默认居中（官方 FAQ）——必须显式顶对齐
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.safeAreaTopVp })
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.settingsPageBackground)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      this.load();
    })
    .bindSheet($$this.showDaySheet, this.daySheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      showClose: false,
      backgroundColor: this.theme.settingsPageBackground
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题（二级页统一结构） ----

  @Builder
  private topBar() {
    Stack() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textPrimary])
        }
        .width(34)
        .height(34)
        .padding(0)
        .backgroundColor(this.theme.glassBackground)
        .border({ width: 0.5, color: this.theme.glassBorder })
        .onClick((): void => {
          this.navPathStack.pop();
        })
        Blank()
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text($r('app.string.s_9392c3c977'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textSecondary)
          .letterSpacing(this.theme.letterSpacingWide)
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(TOP_BAR_ROW_HEIGHT_VP)
    .margin({ bottom: TOP_BAR_CONTENT_GAP_VP })
  }

  // ---- 三张数字卡（StatCard 组件在上；@Builder 方法收不了尾随闭包）----

  // ---- 情绪捕捉的卡（壳是上面的 InsightCard 组件：同因）----

  // ---- 心情走势 ----

  @Builder
  private trendCard() {
    InsightCard({ title: $r('app.string.s_26825deedb') }) {
      if (this.trendPoints().length < 2) {
        Text($r('app.string.s_791054f6b1'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 32, bottom: 32 })
      } else {
        MoodTrendChart({
          xs: this.trendXs(),
          ys: this.trendYs(),
          tints: this.trendTints(),
          byMonth: this.trendByMonth()
        })
      }
    }
  }

  // ---- 心情分布（环形图 + 中心总篇数 + 图例）----

  @Builder
  private donutCard() {
    InsightCard({ title: $r('app.string.s_49fcec9454') }) {
      if (this.donutData().isEmpty) {
        Text($r('app.string.s_50f87ef514'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 40, bottom: 40 })
      } else {
        Column({ space: 16 }) {
          Stack({ alignContent: Alignment.Center }) {
            MoodDonutChart({
              tints: this.donutTints(),
              counts: this.donutCounts()
            })
            Column({ space: 2 }) {
              Text(`${this.donutData().total}`)
                .fontSize(28)
                .fontWeight(FontWeight.Lighter)
                .fontFamily(this.theme.titleFont.family)
                .fontColor(this.theme.textPrimary)
              Text($r('app.string.s_69007df2b7'))
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textTertiary)
            }
            .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')

          // 图例：系统图例给不出百分比和篇数，自己画
          Column({ space: 8 }) {
            ForEach(this.donutData().slices, (slice: MoodSlice) => {
              Row({ space: 8 }) {
                Column()
                  .width(8)
                  .height(8)
                  .borderRadius(4)
                  .backgroundColor(MoodLevels.tintHex(slice.level))
                Text(moodLevelTitle(slice.level))
                  .fontSize(this.theme.labelFont.size)
                  .fontWeight(this.theme.labelFont.weight)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textSecondary)
                Blank()
                Text(`${Math.round(slice.percentage)}%`)
                  .fontSize(this.theme.labelFont.size)
                  .fontWeight(this.theme.labelFont.weight)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textPrimary)
                Text(`${slice.count}`)
                  .fontSize(this.theme.labelFont.size)
                  .fontWeight(this.theme.labelFont.weight)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textTertiary)
                  .width(28)
                  .textAlign(TextAlign.End)
              }
              .width('100%')
            }, (slice: MoodSlice): string => `${slice.level}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
  }

  // ---- 星期与时段（一卡两段，中间细分隔）----

  @Builder
  private weekdayDayPartCard() {
    InsightCard({ title: $r('app.string.s_09f515b893') }) {
      Column({ space: 12 }) {
        ForEach(this.weekdayRows(), (item: WeekdayGroup) => {
          this.scaleRow(weekdayNarrow(item.weekday, this.appLanguage), item.group)
        }, (item: WeekdayGroup): string => `${item.weekday}-${item.group.count}-${item.group.valence}`)
        if (this.weekdayRows().length > 0 && this.dayPartRows().length > 0) {
          Divider()
            .color(this.theme.border)
            .strokeWidth(0.5)
            .margin({ top: 2, bottom: 2 })
        }
        ForEach(this.dayPartRows(), (item: DayPartGroup) => {
          this.scaleRow(dayPartTitle(item.part), item.group)
        }, (item: DayPartGroup): string => `${item.part}-${item.group.count}-${item.group.valence}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 刻度行（天气 / 地点 / 星期 / 时段共用） */
  @Builder
  private scaleRow(title: ResourceStr, group: MoodGroup) {
    MoodScaleRow({
      title: title,
      valence: group.valence,
      count: group.count,
      tint: MoodLevels.tintHex(group.level),
      levelTitle: moodLevelTitle(group.level)
    })
  }

  // ---- 点日历某天弹出的列表（sheet：看完该回到统计页，不陷进日记的导航栈）----

  @Builder
  private daySheetBuilder() {
    Column() {
      Stack() {
        Row() {
          Blank()
          Text($r('app.string.s_33246f6a5e'))
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.accent)
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick((): void => {
              this.showDaySheet = false;
            })
        }
        .width('100%')
        .height(TOP_BAR_ROW_HEIGHT_VP)
        .alignItems(VerticalAlign.Center)

        Row() {
          Text(fullDate(new Date(this.pickedDayMs), this.appLanguage))
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.textSecondary)
            .letterSpacing(this.theme.letterSpacingWide)
            .maxLines(1)
        }
        .width('100%')
        .height(TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')

      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.dayEntries(), (entry: JournalEntry) => {
            EntryRowView({
              entry: entry,
              onTap: (): void => {
                this.openEntryFromSheet(entry.id);
              }
            })
          }, (entry: JournalEntry): string => entry.id)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 20, right: 20, top: 12, bottom: this.safeAreaBottomVp + 20 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
  }

  // ---- 数据 ----

  /** 打开本页算一次：总篇数 / 总字数 / 最长连续（只升不降，升了才记） */
  private async load(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      const store = await AppDatabase.open(context);
      const entries = await EntryRepository.fetchAllEntries(store);
      this.entries = entries;
      const dates: number[] = [];
      for (const entry of entries) {
        dates.push(entry.date);
      }
      const recorded = AppPrefs.recordedBestStreakDays();
      const best = WritingStreak.best(recorded, dates);
      if (best > recorded) {
        AppPrefs.setRecordedBestStreakDays(best);
      }
      this.streakDays = best;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load stats failed: %{public}s', JSON.stringify(e));
    }
  }

  private totalWords(): number {
    let total = 0;
    for (const entry of this.entries) {
      total += entry.wordCount;
    }
    return total;
  }

  /** 每天各写了几篇（本地 0 点毫秒 → 篇数；日历格子和当天列表共用同一份） */
  private dayCounts(): CalendarDayCount[] {
    const counts = new Map<number, number>();
    for (const entry of this.entries) {
      const d = new Date(entry.date);
      const dayMs = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
      const prev = counts.get(dayMs);
      counts.set(dayMs, prev === undefined ? 1 : prev + 1);
    }
    const result: CalendarDayCount[] = [];
    counts.forEach((count: number, dayMs: number): void => {
      result.push(new CalendarDayCount(dayMs, count));
    });
    return result;
  }

  /** 被点开的那天的日记，新的在前 */
  private dayEntries(): JournalEntry[] {
    const result: JournalEntry[] = [];
    for (const entry of this.entries) {
      const d = new Date(entry.date);
      const dayMs = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
      if (dayMs === this.pickedDayMs) {
        result.push(entry);
      }
    }
    result.sort((a: JournalEntry, b: JournalEntry): number => b.date - a.date);
    return result;
  }

  /** 点当天列表里的一篇：先收 sheet 再进详情（详情是主栈上的目的地） */
  private openEntryFromSheet(entryId: string): void {
    this.showDaySheet = false;
    this.navPathStack.pushPathByName('EntryDetail', entryId);
  }

  // ---- 情绪捕捉（范围跟着 moodRange 走）----

  private moodItems(): MoodItem[] {
    return MoodInsights.moodEntries(this.entries, this.moodRange, Date.now());
  }

  private trendPoints(): TrendPoint[] {
    return MoodInsights.trend(this.moodItems(), MoodInsights.bucket(this.moodRange));
  }

  private trendByMonth(): boolean {
    return MoodInsights.bucket(this.moodRange) === TrendBucket.month;
  }

  private trendXs(): number[] {
    const xs: number[] = [];
    for (const point of this.trendPoints()) {
      xs.push(point.startMs);
    }
    return xs;
  }

  private trendYs(): number[] {
    const ys: number[] = [];
    for (const point of this.trendPoints()) {
      ys.push(point.valence);
    }
    return ys;
  }

  private trendTints(): string[] {
    const tints: string[] = [];
    for (const point of this.trendPoints()) {
      tints.push(MoodLevels.tintHex(point.level));
    }
    return tints;
  }

  private donutData(): MoodChartData {
    return StatsCalculator.moodChartData(this.entries, this.moodRange, Date.now());
  }

  private donutTints(): string[] {
    const tints: string[] = [];
    for (const slice of this.donutData().slices) {
      tints.push(MoodLevels.tintHex(slice.level));
    }
    return tints;
  }

  private donutCounts(): number[] {
    const counts: number[] = [];
    for (const slice of this.donutData().slices) {
      counts.push(slice.count);
    }
    return counts;
  }

  private topLabels(): LabelCount[] {
    return MoodInsights.topLabels(this.moodItems());
  }

  private weatherRows(): WeatherGroup[] {
    return MoodInsights.byWeather(this.moodItems());
  }

  private placeRows(): MoodGroup[] {
    return MoodInsights.byPlace(this.moodItems());
  }

  private weekdayRows(): WeekdayGroup[] {
    // 星期按 App 语言排（一周从哪天开始跟着语言走：fr/es 周一起，其余周日起）
    return MoodInsights.byWeekday(this.moodItems(), firstWeekdayIndex(this.appLanguage));
  }

  private dayPartRows(): DayPartGroup[] {
    return MoodInsights.byDayPart(this.moodItems());
  }

  /** 天气 / 地点 / 星期时段至少有一张没出来：说一句为什么（iOS 同款条件） */
  private needsFootnote(): boolean {
    return this.weatherRows().length === 0 || this.placeRows().length === 0 ||
      (this.weekdayRows().length === 0 && this.dayPartRows().length === 0);
  }
}
