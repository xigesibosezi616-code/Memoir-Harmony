/**
 * 情绪捕捉的几张图（10_BUILD_MANUAL.md 6.3；对应 iOS `StatsView.swift` 里的
 * RangePicker / MoodDonutChart / MoodTrendChart / MoodScaleRow / LabelCountList）。
 *
 * - 范围切换用胶囊分段而不是系统分段控件——后者配色接不上四套主题
 * - 环形图中间的洞放总篇数（看比例的同时得知道样本量）；图例在 StatsView
 *   自己画（系统图例给不出百分比和篇数）
 * - 走势：每格平均愉悦度连成线（Fritsch–Carlson 单调三次插值，和 iOS
 *   Charts `.monotone` 同思路，避免过冲把低谷画得比实际更低）；中间虚线是
 *   「不悲不喜」；点的颜色是那一档的颜色
 * - 刻度行：天气 / 地点 / 星期 / 时段共用，几张卡读法一样
 *
 * 图表不追求和 iOS Charts 1:1 圆角扇区：Canvas 弧 + 1.5° 角内缩近似。
 */
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../../services/LanguageManager';
import { isChineseLanguage, monthDayNumeric } from '../../../services/AppDateFormatters';
import { StatsRange, StatsRanges } from '../../../models/StatsCalculator';
import { LabelCount } from '../../../models/MoodInsights';
import { MoodLevel, MoodLevels } from '../../../models/MoodLevel';
import { MoodLabel, MoodLabels } from '../../../models/MoodLabel';
import { moodLabelTitle, statsRangeTitle } from './StatsText';

/** 非（简繁）中文的月短名（走势按月桶的横轴：「Nov」/「11月」） */
function monthShortLabel(date: Date, appLanguage: string): string {
  if (isChineseLanguage(appLanguage)) {
    return `${date.getMonth() + 1}月`;
  }
  return new Intl.DateTimeFormat(appLanguage, { month: 'short' }).format(date);
}

// ---- 时间范围切换 ----

/**
 * 近 7 天 / 近 30 天 / 今年 / 全部。情绪捕捉那一段的范围（走势、分布、
 * 情绪词、天气、地点、星期时段一起跟着变）；上方三张数字卡和写作日历仍是全期。
 */
@Component
export struct StatsRangePicker {
  @Prop selected: StatsRange = StatsRange.month;
  onPicked: (range: StatsRange) => void = (): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Row({ space: 6 }) {
      ForEach(StatsRanges.all, (range: StatsRange) => {
        Text(statsRangeTitle(range))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(range === this.selected ? this.theme.background : this.theme.textSecondary)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(range === this.selected ? this.theme.accent : Color.Transparent)
          .borderRadius(999)
          .border({
            width: 0.5,
            color: range === this.selected ? Color.Transparent : this.theme.border
          })
          .onClick((): void => {
            this.onPicked(range);
          })
      }, (range: StatsRange): string => `${range}`)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

// ---- 心情分布环形图 ----

/**
 * 九档环形（innerRatio 0.62）。只画环，中间的总篇数和图例由 StatsView 叠。
 * 环上从心花怒放排到跌入谷底，颜色顺着九档走，一眼看得出偏哪一边。
 */
@Component
export struct MoodDonutChart {
  /** 每瓣的颜色（九档 tint）与篇数，同序 */
  @Prop @Watch('onDataChanged') tints: string[] = [];
  @Prop @Watch('onDataChanged') counts: number[] = [];
  private chartCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Canvas(this.chartCtx)
      .width('100%')
      .height(180)
      .onReady((): void => {
        this.drawChart();
      })
  }

  private onDataChanged(): void {
    this.drawChart();
  }

  private drawChart(): void {
    const ctx = this.chartCtx;
    const width = ctx.width;
    const height = ctx.height;
    ctx.clearRect(0, 0, width, height);
    const total = this.totalCount();
    if (total === 0) {
      return;
    }
    const cx = width / 2;
    const cy = height / 2;
    const outer = Math.min(width, height) / 2 - 4;
    const inner = outer * 0.62;
    const inset = 1.5 * Math.PI / 180;
    let angle = -Math.PI / 2;
    for (let i = 0; i < this.counts.length && i < this.tints.length; i++) {
      const count = this.counts[i];
      if (count <= 0) {
        continue;
      }
      const sweep = count / total * Math.PI * 2;
      // 角内缩不盖过相邻瓣（小瓣缩一半防消失）
      const gap = Math.min(inset, sweep * 0.25);
      ctx.beginPath();
      ctx.arc(cx, cy, outer, angle + gap, angle + sweep - gap);
      ctx.arc(cx, cy, inner, angle + sweep - gap, angle + gap, true);
      ctx.closePath();
      ctx.fillStyle = this.tints[i];
      ctx.fill();
      angle += sweep;
    }
  }

  private totalCount(): number {
    let total = 0;
    for (const count of this.counts) {
      total += count;
    }
    return total;
  }
}

// ---- 心情走势 ----

/**
 * 每一格的平均愉悦度连成线，点的颜色是那一档的颜色；中间虚线是「不悲不喜」。
 * 没记心情的那一格不画（「没写」不等于「不悲不喜」）。少于两格时父组件
 * 显示「再写几篇，就能看出走势」，这个组件不被创建。
 */
@Component
export struct MoodTrendChart {
  /** 每格起点（本地 0 点或月 1 号 0 点）、平均愉悦度、那一档的颜色，同序 */
  @Prop @Watch('onDataChanged') xs: number[] = [];
  @Prop @Watch('onDataChanged') ys: number[] = [];
  @Prop @Watch('onDataChanged') tints: string[] = [];
  /** 今年 / 全部按月桶（横轴标签用月名而不是月/日） */
  @Prop byMonth: boolean = false;
  private chartCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';

  build() {
    Canvas(this.chartCtx)
      .width('100%')
      .height(150)
      .onReady((): void => {
        this.drawChart();
      })
  }

  private onDataChanged(): void {
    this.drawChart();
  }

  private drawChart(): void {
    const ctx = this.chartCtx;
    const width = ctx.width;
    const height = ctx.height;
    ctx.clearRect(0, 0, width, height);
    const n = Math.min(this.xs.length, this.ys.length, this.tints.length);
    if (n < 2) {
      return;
    }
    const padLeft = 8;
    const padRight = 20;
    const padTop = 6;
    const padBottom = 20;
    const x0 = this.xs[0];
    const x1 = this.xs[n - 1];
    const span = x1 > x0 ? x1 - x0 : 1;
    const plotW = width - padLeft - padRight;
    const plotH = height - padTop - padBottom;

    const xAt = (ms: number): number => padLeft + (ms - x0) / span * plotW;
    const yAt = (v: number): number => padTop + (1 - (v + 1) / 2) * plotH;
    const axisColor = this.canvasTextColor();

    // 中线：「不悲不喜」虚线
    ctx.strokeStyle = axisColor;
    ctx.globalAlpha = 0.5;
    ctx.lineWidth = 0.6;
    ctx.setLineDash([3, 3]);
    ctx.beginPath();
    ctx.moveTo(padLeft, yAt(0));
    ctx.lineTo(width - padRight, yAt(0));
    ctx.stroke();
    ctx.setLineDash([]);

    // 曲线：单调三次（防过冲，节点斜率在像素域算）
    const px: number[] = [];
    const py: number[] = [];
    for (let i = 0; i < n; i++) {
      px.push(xAt(this.xs[i]));
      py.push(yAt(this.ys[i]));
    }
    const slopes = this.monotoneSlopes(px, py);
    ctx.globalAlpha = 0.55;
    ctx.lineWidth = 1.2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(px[0], py[0]);
    for (let i = 0; i < n - 1; i++) {
      const dx = px[i + 1] - px[i];
      ctx.bezierCurveTo(
        px[i] + dx / 3, py[i] + slopes[i] * dx / 3,
        px[i + 1] - dx / 3, py[i + 1] - slopes[i + 1] * dx / 3,
        px[i + 1], py[i + 1]);
    }
    ctx.stroke();

    // 点：那一档的颜色
    for (let i = 0; i < n; i++) {
      ctx.globalAlpha = 1;
      ctx.fillStyle = this.tints[i];
      ctx.beginPath();
      ctx.arc(xAt(this.xs[i]), yAt(this.ys[i]), 3.2, 0, Math.PI * 2);
      ctx.fill();
    }

    // 纵轴不画，只在图里左上、左下各写一个字：上面是愉快、下面是低落
    ctx.fillStyle = axisColor;
    ctx.globalAlpha = 0.8;
    ctx.font = '10px sans-serif';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.fillText(this.axisText($r('app.string.s_a6b3821680')), padLeft, padTop + 2);
    ctx.fillText(this.axisText($r('app.string.s_dab4f23d78')), padLeft, height - padBottom - 13);

    // 横轴：约 4 个日期标签（按 App 语言）
    ctx.globalAlpha = 0.9;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    const picks: number[] = [];
    const candidates = [0, Math.floor((n - 1) / 3), Math.floor((n - 1) * 2 / 3), n - 1];
    for (const index of candidates) {
      if (picks.indexOf(index) < 0) {
        picks.push(index);
      }
    }
    for (const index of picks) {
      const date = new Date(this.xs[index]);
      const label = this.byMonth
        ? monthShortLabel(date, this.appLanguage)
        : monthDayNumeric(date, this.appLanguage);
      ctx.fillText(label, xAt(this.xs[index]), height - padBottom + 3);
    }
    ctx.globalAlpha = 1;
  }

  /** Fritsch–Carlson 单调插值的节点斜率（像素域；同 iOS Charts `.monotone` 的思路） */
  private monotoneSlopes(px: number[], py: number[]): number[] {
    const n = px.length;
    const slopes: number[] = [];
    const secants: number[] = [];
    for (let i = 0; i < n - 1; i++) {
      const dx = px[i + 1] - px[i];
      secants.push(dx !== 0 ? (py[i + 1] - py[i]) / dx : 0);
    }
    for (let i = 0; i < n; i++) {
      if (i === 0) {
        slopes.push(secants[0]);
      } else if (i === n - 1) {
        slopes.push(secants[secants.length - 1]);
      } else if (secants[i - 1] * secants[i] <= 0) {
        slopes.push(0);
      } else {
        slopes.push(2 / (1 / secants[i - 1] + 1 / secants[i]));
      }
    }
    return slopes;
  }

  /** 坐标轴文字颜色（textTertiary 是 hex 串才能进 Canvas，否则中灰兜底） */
  private canvasTextColor(): string {
    const color = this.theme.textTertiary;
    return typeof color === 'string' ? color : '#888888';
  }

  /** Resource → string（resourceManager 同步取，给 Canvas 用） */
  private axisText(res: Resource): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringSync(res.id);
  }
}

// ---- 刻度行 ----

/**
 * 一行「这一组的平均心情落在哪」：左边是组名，中间一条从低落到愉快的
 * 刻度（颜色顺着九档），点在平均值上，右边是那一档的名字和篇数。
 * 天气、地点、星期、时段共用，几张卡片读法一样。
 */
@Component
export struct MoodScaleRow {
  /** 组名（天气六类 / 时段四段是词条；地名是数据不翻译） */
  @Prop title: ResourceStr = '';
  /** 这组的平均愉悦度 -1…1 */
  @Prop valence: number = 0;
  /** 这组的篇数 */
  @Prop count: number = 0;
  /** 平均心情落档的颜色（MoodLevels.tintHex） */
  @Prop tint: string = '#61BFD1';
  /** 落档档名 */
  @Prop levelTitle: ResourceStr = '';
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Row({ space: 10 }) {
      Text(this.title)
        .fontSize(this.theme.labelFont.size)
        .fontWeight(this.theme.labelFont.weight)
        .fontFamily(this.theme.labelFont.family)
        .fontColor(this.theme.textSecondary)
        .maxLines(1)
        .width(64)

      // 刻度：九档渐变胶囊 + 正中「不悲不喜」刻度 + 平均值圆点
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .height(4)
          .width('100%')
          .borderRadius(2)
          .linearGradient({
            direction: GradientDirection.Right,
            colors: this.scaleGradientColors()
          })
        Row()
          .width(1)
          .height(10)
          .backgroundColor(this.theme.textTertiary)
          .opacity(0.4)
          .margin({ left: '50%' })
          .translate({ x: -0.5 })
        Row()
          .width(12)
          .height(12)
          .borderRadius(6)
          .backgroundColor(this.tint)
          .border({ width: 2, color: this.theme.cardBackground })
          .margin({ left: `${this.dotPercent()}%` })
          .translate({ x: -6 })
      }
      .layoutWeight(1)
      .height(14)

      Text(this.levelTitle)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .maxLines(2)
        .textAlign(TextAlign.End)
        .width(76)

      Text(`${this.count}`)
        .fontSize(this.theme.labelFont.size)
        .fontWeight(this.theme.labelFont.weight)
        .fontFamily(this.theme.labelFont.family)
        .fontColor(this.theme.textTertiary)
        .width(24)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 九档渐变（30% 透明度），从跌入谷底到心花怒放 */
  private scaleGradientColors(): Array<[ResourceColor, number]> {
    const colors: Array<[ResourceColor, number]> = [];
    for (let i = 0; i < MoodLevels.count; i++) {
      colors.push([`${MoodLevels.tintHex(i as MoodLevel)}4D`, i / (MoodLevels.count - 1)]);
    }
    return colors;
  }

  /** 圆点位置（百分比）：愉悦度 -1…1 → 0…100 */
  private dotPercent(): number {
    const clamped = Math.min(Math.max(this.valence, -1), 1);
    return (clamped + 1) / 2 * 100;
  }
}

// ---- 最常出现的情绪 ----

/**
 * 情绪词列表：圆点是这个词所在那一档的颜色，条的长短按次数。
 */
@Component
export struct LabelCountList {
  @Prop items: LabelCount[] = [];
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Column({ space: 10 }) {
      ForEach(this.items, (item: LabelCount) => {
        Row({ space: 10 }) {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.tintOf(item.label))
          Text(moodLabelTitle(item.label))
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.textSecondary)
            .maxLines(1)
            .width(64)
          Row() {
            Row()
              .width(`${this.barPercent(item)}%`)
              .height(6)
              .borderRadius(3)
              .backgroundColor(this.tintOf(item.label))
              .opacity(0.55)
          }
          .layoutWeight(1)
          .height(14)
          .alignItems(VerticalAlign.Center)

          Text(`${item.count}`)
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.textTertiary)
            .width(24)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      // key 带上最高次数：条长按 top 占比，只带 label-count 的话
      // 换范围后 top 变了、同键行不重渲染，条长会停在旧比例
      }, (item: LabelCount): string => `${item.label}-${item.count}-t${this.topCount()}`)
    }
    .width('100%')
  }

  /** 出现最多的那个词的次数（条长按它归一） */
  private topCount(): number {
    let top = 1;
    for (const other of this.items) {
      if (other.count > top) {
        top = other.count;
      }
    }
    return top;
  }

  /** 这个词所在那一档的颜色 */
  private tintOf(label: MoodLabel): string {
    return MoodLevels.tintHex(MoodLabels.levelOf(label));
  }

  /** 条长：按次数占最高次数的百分比，最短 3% 不消失 */
  private barPercent(item: LabelCount): number {
    return Math.max(3, item.count / this.topCount() * 100);
  }
}
