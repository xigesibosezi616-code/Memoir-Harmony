/**
 * 写作统计的纯计算（10_BUILD_MANUAL.md 6.3；对应 iOS
 * `Services/StatsCalculator.swift` + `Services/WritingStreak.swift` 的纯函数部分）。
 *
 * - 时间范围粒度：短期看波动、长期看基线 —— 近 7 天看这周起伏，今年 / 全部看情绪底色
 * - 环形图只画**真的有数据**的心情（0 篇的档画不出扇区）
 * - 一切日期按设备时区（new Date 的本地语义），毫秒时间戳进、毫秒时间戳出
 */
import { JournalEntry } from './JournalEntry';
import { MoodLevel, MoodLevels } from './MoodLevel';

/** 统计的时间范围（近 7 天 / 近 30 天 / 今年 / 全部） */
export enum StatsRange {
  week = 0,
  month = 1,
  year = 2,
  all = 3
}

export class StatsRanges {
  static readonly all: StatsRange[] = [StatsRange.week, StatsRange.month, StatsRange.year, StatsRange.all];

  /**
   * 这个范围的起点（当天 0 点毫秒）；null = 不限（全部）。
   * nowMs 做参数是为了单测里喂假日期跑穿多个区间。
   */
  static startDateMs(range: StatsRange, nowMs: number): number | null {
    const now = new Date(nowMs);
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    switch (range) {
      case StatsRange.week:
        // 含今天在内的 7 天，所以是 -6
        return today - 6 * 86400000;
      case StatsRange.month:
        return today - 29 * 86400000;
      case StatsRange.year:
        return new Date(now.getFullYear(), 0, 1).getTime();
      case StatsRange.all:
        return null;
      default:
        return null;
    }
  }

  static containsMs(range: StatsRange, dateMs: number, nowMs: number): boolean {
    const start = StatsRanges.startDateMs(range, nowMs);
    if (start === null) {
      return true;
    }
    return dateMs >= start;
  }
}

/** 饼图的一瓣：九档里的一档。只有真的有数据的心情才会成为一瓣 */
export class MoodSlice {
  readonly level: MoodLevel;
  readonly count: number;
  /** 0…100 */
  readonly percentage: number;

  constructor(level: MoodLevel, count: number, percentage: number) {
    this.level = level;
    this.count = count;
    this.percentage = percentage;
  }
}

export class MoodChartData {
  /** 从心花怒放排到跌入谷底（环上颜色顺着九档走，一眼看得出偏哪一边） */
  readonly slices: MoodSlice[];
  /** 这个区间记了心情的篇数 */
  readonly total: number;

  constructor(slices: MoodSlice[], total: number) {
    this.slices = slices;
    this.total = total;
  }

  get isEmpty(): boolean {
    return this.slices.length === 0;
  }
}

export class WritingStats {
  readonly totalEntries: number;
  readonly totalWords: number;

  constructor(totalEntries: number, totalWords: number) {
    this.totalEntries = totalEntries;
    this.totalWords = totalWords;
  }
}

export class StatsCalculator {
  /** 总篇数 / 总字数（三张数字卡里的两张；写作日历用的日期集合在 UI 层按天分组） */
  static calculate(entries: JournalEntry[]): WritingStats {
    let totalWords = 0;
    for (const entry of entries) {
      totalWords += entry.wordCount;
    }
    return new WritingStats(entries.length, totalWords);
  }

  /**
   * 按时间范围算心情分布（九档），供环形图用。
   * - 只统计**记了心情**的日记（moodValence 为空的都不进分母）——
   *   把「没记」混进百分比会让所有比例失真
   * - 从心花怒放排到跌入谷底
   */
  static moodChartData(entries: JournalEntry[], range: StatsRange, nowMs: number): MoodChartData {
    const counts: number[] = [];
    for (let i = 0; i < MoodLevels.count; i++) {
      counts.push(0);
    }
    let total = 0;
    for (const entry of entries) {
      if (entry.moodValence === undefined || !StatsRanges.containsMs(range, entry.date, nowMs)) {
        continue;
      }
      counts[MoodLevels.fromValence(entry.moodValence)] += 1;
      total += 1;
    }
    if (total === 0) {
      return new MoodChartData([], 0);
    }
    const slices: MoodSlice[] = [];
    // 反着走：overjoyed → rockBottom
    for (let i = MoodLevels.all.length - 1; i >= 0; i--) {
      const level = MoodLevels.all[i];
      const count = counts[level];
      if (count > 0) {
        slices.push(new MoodSlice(level, count, count / total * 100));
      }
    }
    return new MoodChartData(slices, total);
  }
}
