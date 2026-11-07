/**
 * 情绪捕捉（U14；对应 iOS `Services/MoodInsights.swift`）：写作统计里免费的
 * 那几张图，**全在本机算，不联网**。
 *
 * 规则（U14 照抄）：
 * - 只算**记了心情**的日记（moodValence 为空的都不进分母）
 * - 时间范围跟着页面上的「近 7 天 / 近 30 天 / 今年 / 全部」走（StatsRange）
 * - 天气、地点、星期、时段：**一组不到 minimumSample 篇不显示** ——
 *   两三篇看不出规律，硬画出来会误导
 * - 「心情」一律用愉悦度（-1…1）的平均值，再落回九档取颜色和名字
 */
import { JournalEntry } from './JournalEntry';
import { MoodLevel, MoodLevels } from './MoodLevel';
import { MoodLabel, MoodLabels } from './MoodLabel';
import { StatsRange, StatsRanges } from './StatsCalculator';

/** 记了心情的一篇：日记和它的愉悦度 */
export class MoodItem {
  readonly entry: JournalEntry;
  readonly valence: number;

  constructor(entry: JournalEntry, valence: number) {
    this.entry = entry;
    this.valence = valence;
  }
}

/** 一组日记的平均心情（天气 / 地点 / 星期 / 时段共用） */
export class MoodGroup {
  readonly id: string;
  readonly valence: number;
  readonly count: number;

  constructor(id: string, valence: number, count: number) {
    this.id = id;
    this.valence = valence;
    this.count = count;
  }

  get level(): MoodLevel {
    return MoodLevels.fromValence(this.valence);
  }
}

/** 走势的一格：这一格的起点（某天 0 点或某月 1 号 0 点）+ 平均心情 + 篇数 */
export class TrendPoint {
  readonly startMs: number;
  readonly valence: number;
  readonly count: number;

  constructor(startMs: number, valence: number, count: number) {
    this.startMs = startMs;
    this.valence = valence;
    this.count = count;
  }

  get level(): MoodLevel {
    return MoodLevels.fromValence(this.valence);
  }
}

/** 最常出现的情绪的一项 */
export class LabelCount {
  readonly label: MoodLabel;
  readonly count: number;

  constructor(label: MoodLabel, count: number) {
    this.label = label;
    this.count = count;
  }
}

/** 天气归成六类。认不出的（如「酷寒」）不归类、不进统计 */
export enum WeatherKind {
  clear = 0,
  cloudy = 1,
  rain = 2,
  snow = 3,
  fog = 4,
  wind = 5
}

/** 一天里的四段：早上 5–11 点、下午 11–17 点、晚上 17–23 点、深夜 23–5 点 */
export enum DayPart {
  morning = 0,
  afternoon = 1,
  evening = 2,
  night = 3
}

/** 走势一格多长：近 7 天 / 近 30 天按天，今年 / 全部按自然月（U14 R-MOOD-03） */
export enum TrendBucket {
  day = 0,
  month = 1
}

export class MoodInsights {
  /** 一组至少几篇才显示 */
  static readonly minimumSample: number = 3;
  /** 地点最多列几处（按篇数从多到少） */
  static readonly placeLimit: number = 5;
  /** 情绪词最多列几个 */
  static readonly labelLimit: number = 5;

  /** 页面上选的范围里记了心情的日记 */
  static moodEntries(entries: JournalEntry[], range: StatsRange, nowMs: number): MoodItem[] {
    const items: MoodItem[] = [];
    for (const entry of entries) {
      if (entry.moodValence !== undefined && StatsRanges.containsMs(range, entry.date, nowMs)) {
        items.push(new MoodItem(entry, entry.moodValence));
      }
    }
    return items;
  }

  static averageValence(items: MoodItem[]): number | null {
    if (items.length === 0) {
      return null;
    }
    let sum = 0;
    for (const item of items) {
      sum += item.valence;
    }
    return sum / items.length;
  }

  /** 页面上：近 7 天、近 30 天按天；今年、全部按月 */
  static bucket(range: StatsRange): TrendBucket {
    return range === StatsRange.year || range === StatsRange.all ? TrendBucket.month : TrendBucket.day;
  }

  /** 每一格的平均心情。没记心情的那一格不画（不补 0 ——「没写」不等于「不悲不喜」） */
  static trend(items: MoodItem[], bucketKind: TrendBucket): TrendPoint[] {
    const groups = new Map<number, number[]>();
    for (const item of items) {
      const d = new Date(item.entry.date);
      let start: number;
      if (bucketKind === TrendBucket.month) {
        start = new Date(d.getFullYear(), d.getMonth(), 1).getTime();
      } else {
        start = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
      }
      const bucketVals = groups.get(start);
      if (bucketVals === undefined) {
        groups.set(start, [item.valence]);
      } else {
        bucketVals.push(item.valence);
      }
    }
    const starts = Array.from(groups.keys()).sort((a, b) => a - b);
    const points: TrendPoint[] = [];
    for (const start of starts) {
      const vals = groups.get(start);
      if (vals === undefined) {
        continue;
      }
      let sum = 0;
      for (const v of vals) {
        sum += v;
      }
      points.push(new TrendPoint(start, sum / vals.length, vals.length));
    }
    return points;
  }

  /** 九档各几篇，从「跌入谷底」到「心花怒放」 */
  static levelCounts(items: MoodItem[]): number[] {
    const counts: number[] = [];
    for (let i = 0; i < MoodLevels.count; i++) {
      counts.push(0);
    }
    for (const item of items) {
      counts[MoodLevels.fromValence(item.valence)] += 1;
    }
    return counts;
  }

  /** 选过的情绪词，按次数从多到少；次数一样按九档从低到高排（先看到需要照顾的那些） */
  static topLabels(items: MoodItem[]): LabelCount[] {
    const counts = new Map<MoodLabel, number>();
    for (const item of items) {
      if (item.entry.moodLabels === undefined) {
        continue;
      }
      for (const key of item.entry.moodLabels) {
        const label = MoodLabels.fromKey(key);
        if (label === undefined) {
          continue;
        }
        const prev = counts.get(label);
        counts.set(label, prev === undefined ? 1 : prev + 1);
      }
    }
    const result: LabelCount[] = [];
    counts.forEach((count: number, label: MoodLabel): void => {
      result.push(new LabelCount(label, count));
    });
    result.sort((a: LabelCount, b: LabelCount): number => {
      if (a.count !== b.count) {
        return b.count - a.count;
      }
      return a.label - b.label;
    });
    return result.slice(0, MoodInsights.labelLimit);
  }

  /** 天气归类的关键词（与 iOS `WeatherKind.init(code:)` 同款，小写包含匹配） */
  static weatherKindFromCode(code: string): WeatherKind | undefined {
    const c = code.toLowerCase();
    if (MoodInsights.codeHasAny(c, 'snow', 'sleet', 'hail', 'flurries', 'blizzard')) {
      return WeatherKind.snow;
    }
    if (MoodInsights.codeHasAny(c, 'rain', 'drizzle', 'bolt', 'thunder')) {
      return WeatherKind.rain;
    }
    if (MoodInsights.codeHasAny(c, 'fog', 'haze', 'smoke', 'dust')) {
      return WeatherKind.fog;
    }
    if (MoodInsights.codeHasAny(c, 'wind', 'tornado', 'hurricane', 'tropicalstorm')) {
      return WeatherKind.wind;
    }
    if (c.includes('cloud')) {
      return WeatherKind.cloudy;
    }
    if (MoodInsights.codeHasAny(c, 'sun', 'moon', 'clear', 'hot')) {
      return WeatherKind.clear;
    }
    return undefined;
  }

  /** 天气与心情（六类各一组，一组 ≥ minimumSample 篇才返回） */
  static byWeather(items: MoodItem[]): WeatherGroup[] {
    const buckets = new Map<WeatherKind, number[]>();
    for (const item of items) {
      const code = item.entry.weatherCode;
      if (code === undefined) {
        continue;
      }
      const kind = MoodInsights.weatherKindFromCode(code);
      if (kind === undefined) {
        continue;
      }
      MoodInsights.pushValence(buckets, kind, item.valence);
    }
    const result: WeatherGroup[] = [];
    const kinds: WeatherKind[] = [WeatherKind.clear, WeatherKind.cloudy, WeatherKind.rain,
      WeatherKind.snow, WeatherKind.fog, WeatherKind.wind];
    for (const kind of kinds) {
      const vals = buckets.get(kind);
      if (vals === undefined || vals.length < MoodInsights.minimumSample) {
        continue;
      }
      result.push(new WeatherGroup(kind,
        new MoodGroup(`${kind}`, MoodInsights.averageOf(vals), vals.length)));
    }
    return result;
  }

  /**
   * 常写日记的几处地方（地名按日记上存的原样），按篇数从多到少；
   * 一组 ≥ minimumSample 篇才显示，最多 placeLimit 处
   */
  static byPlace(items: MoodItem[]): MoodGroup[] {
    const buckets = new Map<string, number[]>();
    for (const item of items) {
      const place = (item.entry.locationInfo ?? '').trim();
      if (place.length === 0) {
        continue;
      }
      MoodInsights.pushValence(buckets, place, item.valence);
    }
    const result: MoodGroup[] = [];
    buckets.forEach((vals: number[], place: string): void => {
      if (vals.length >= MoodInsights.minimumSample) {
        result.push(new MoodGroup(place, MoodInsights.averageOf(vals), vals.length));
      }
    });
    result.sort((a: MoodGroup, b: MoodGroup): number => {
      if (a.count !== b.count) {
        return b.count - a.count;
      }
      return a.id < b.id ? -1 : 1;
    });
    return result.slice(0, MoodInsights.placeLimit);
  }

  /**
   * 按星期几（0 = 周日 … 6 = 周六，同 Date.getDay()），顺序从
   * firstDayIndex（0 = 周日起、1 = 一起）开始轮转；一组 ≥ minimumSample 篇才显示
   */
  static byWeekday(items: MoodItem[], firstDayIndex: number): WeekdayGroup[] {
    const buckets = new Map<number, number[]>();
    for (const item of items) {
      const weekday = new Date(item.entry.date).getDay();
      MoodInsights.pushValence(buckets, weekday, item.valence);
    }
    const result: WeekdayGroup[] = [];
    for (let i = 0; i < 7; i++) {
      const weekday = (firstDayIndex + i) % 7;
      const vals = buckets.get(weekday);
      if (vals === undefined || vals.length < MoodInsights.minimumSample) {
        continue;
      }
      result.push(new WeekdayGroup(weekday,
        new MoodGroup(`${weekday}`, MoodInsights.averageOf(vals), vals.length)));
    }
    return result;
  }

  /** 一天里的四段（按写日记那一刻的小时）；一组 ≥ minimumSample 篇才显示 */
  static byDayPart(items: MoodItem[]): DayPartGroup[] {
    const buckets = new Map<DayPart, number[]>();
    for (const item of items) {
      const part = MoodInsights.dayPartOfHour(new Date(item.entry.date).getHours());
      MoodInsights.pushValence(buckets, part, item.valence);
    }
    const result: DayPartGroup[] = [];
    const parts: DayPart[] = [DayPart.morning, DayPart.afternoon, DayPart.evening, DayPart.night];
    for (const part of parts) {
      const vals = buckets.get(part);
      if (vals === undefined || vals.length < MoodInsights.minimumSample) {
        continue;
      }
      result.push(new DayPartGroup(part,
        new MoodGroup(`${part}`, MoodInsights.averageOf(vals), vals.length)));
    }
    return result;
  }

  /** 小时 → 时段：5–11 早上、11–17 下午、17–23 晚上、其余深夜（与 iOS 同款边界） */
  static dayPartOfHour(hour: number): DayPart {
    if (hour >= 5 && hour < 11) {
      return DayPart.morning;
    }
    if (hour >= 11 && hour < 17) {
      return DayPart.afternoon;
    }
    if (hour >= 17 && hour < 23) {
      return DayPart.evening;
    }
    return DayPart.night;
  }

  private static codeHasAny(code: string, ...words: string[]): boolean {
    for (const word of words) {
      if (code.includes(word)) {
        return true;
      }
    }
    return false;
  }

  private static pushValence<K>(buckets: Map<K, number[]>, key: K, valence: number): void {
    const vals = buckets.get(key);
    if (vals === undefined) {
      buckets.set(key, [valence]);
    } else {
      vals.push(valence);
    }
  }

  private static averageOf(values: number[]): number {
    let sum = 0;
    for (const v of values) {
      sum += v;
    }
    return values.length === 0 ? 0 : sum / values.length;
  }
}

/** 天气一组（kind + 那一组的平均心情） */
export class WeatherGroup {
  readonly kind: WeatherKind;
  readonly group: MoodGroup;

  constructor(kind: WeatherKind, group: MoodGroup) {
    this.kind = kind;
    this.group = group;
  }
}

/** 星期一组（weekday 0 = 周日 … 6 = 周六） */
export class WeekdayGroup {
  readonly weekday: number;
  readonly group: MoodGroup;

  constructor(weekday: number, group: MoodGroup) {
    this.weekday = weekday;
    this.group = group;
  }
}

/** 时段一组 */
export class DayPartGroup {
  readonly part: DayPart;
  readonly group: MoodGroup;

  constructor(part: DayPart, group: MoodGroup) {
    this.part = part;
    this.group = group;
  }
}
