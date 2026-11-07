/**
 * 写作统计纯计算单测（10_BUILD_MANUAL.md 6.3 验收 + U16）。
 *
 * - 范围起点：近 7 天**含今天**（-6）、近 30 天（-29）、今年（1 月 1 日）、全部（null）
 * - 环形图：只画有数据的心情、从心花怒放排到跌入谷底、分母只算记了心情的
 * - 最长连续：断了不归零、同一天多篇算一天、只升不降、没写过 = 0
 */
import { describe, it, expect } from '@ohos/hypium';
import { JournalEntry } from '../../main/ets/models/JournalEntry';
import { StatsRange, StatsRanges, StatsCalculator } from '../../main/ets/models/StatsCalculator';
import { WritingStreak } from '../../main/ets/models/WritingStreak';
import { MoodLevel } from '../../main/ets/models/MoodLevel';

/** 本地某天 0 点毫秒 */
function localDay(year: number, month: number, day: number): number {
  return new Date(year, month - 1, day).getTime();
}

/** 造一篇（date 毫秒；wordCount / moodValence 可选） */
function makeEntry(id: string, dateMs: number, wordCount: number, moodValence?: number): JournalEntry {
  const entry = new JournalEntry(id, dateMs, dateMs, dateMs);
  entry.wordCount = wordCount;
  if (moodValence !== undefined) {
    entry.moodValence = moodValence;
  }
  return entry;
}

export function statsCalculatorTest() {
  describe('StatsCalculatorTest', () => {
    // ---- 范围起点（6.3 验收：近 7 天含今天） ----

    it('weekStartsSixDaysAgoInclusiveToday', 0, () => {
      const now = localDay(2026, 11, 7) + 15 * 3600000; // 周六下午
      const start = StatsRanges.startDateMs(StatsRange.week, now);
      expect(start).assertEqual(localDay(2026, 11, 1));
    });

    it('monthStarts29DaysAgo', 0, () => {
      const now = localDay(2026, 11, 7);
      const start = StatsRanges.startDateMs(StatsRange.month, now);
      expect(start).assertEqual(localDay(2026, 10, 9));
    });

    it('yearStartsAtJanuaryFirst', 0, () => {
      const now = localDay(2026, 11, 7);
      const start = StatsRanges.startDateMs(StatsRange.year, now);
      expect(start).assertEqual(localDay(2026, 1, 1));
    });

    it('allHasNoStart', 0, () => {
      expect(StatsRanges.startDateMs(StatsRange.all, Date.now())).assertNull();
    });

    it('rangeContainsIsStartInclusive', 0, () => {
      const now = localDay(2026, 11, 7);
      const start = StatsRanges.startDateMs(StatsRange.week, now);
      expect(start !== null).assertTrue();
      if (start !== null) {
        expect(StatsRanges.containsMs(StatsRange.week, start, now)).assertTrue();
        expect(StatsRanges.containsMs(StatsRange.week, start - 1, now)).assertFalse();
      }
      // 全部：什么时候都算在范围内
      expect(StatsRanges.containsMs(StatsRange.all, 0, now)).assertTrue();
    });

    // ---- 总篇数 / 总字数 ----

    it('calculateTotals', 0, () => {
      const entries = [
        makeEntry('a', localDay(2026, 11, 1), 120),
        makeEntry('b', localDay(2026, 11, 2), 80),
        makeEntry('c', localDay(2026, 10, 5), 300)
      ];
      const stats = StatsCalculator.calculate(entries);
      expect(stats.totalEntries).assertEqual(3);
      expect(stats.totalWords).assertEqual(500);
    });

    // ---- 心情分布环形图 ----

    it('moodChartOnlySlicesWithDataFromOverjoyedDown', 0, () => {
      const now = localDay(2026, 11, 7);
      const entries = [
        makeEntry('a', localDay(2026, 11, 6), 10, 0.9),   // 心花怒放
        makeEntry('b', localDay(2026, 11, 5), 10, 0.95),  // 心花怒放
        makeEntry('c', localDay(2026, 11, 4), 10, 0),     // 不悲不喜
        makeEntry('d', localDay(2026, 11, 3), 10)         // 没记心情：不进分母
      ];
      const data = StatsCalculator.moodChartData(entries, StatsRange.month, now);
      expect(data.total).assertEqual(3);
      expect(data.isEmpty).assertFalse();
      expect(data.slices.length).assertEqual(2);
      // 第一瓣是心花怒放（从高往低排）；百分比是浮点，留容差
      expect(data.slices[0].level).assertEqual(MoodLevel.overjoyed);
      expect(data.slices[0].count).assertEqual(2);
      expect(Math.abs(data.slices[0].percentage - 200 / 3) < 1e-9).assertTrue();
      expect(data.slices[1].level).assertEqual(MoodLevel.even);
      expect(Math.abs(data.slices[1].percentage - 100 / 3) < 1e-9).assertTrue();
    });

    it('moodChartEmptyWhenNobodyRecordedMood', 0, () => {
      const now = localDay(2026, 11, 7);
      const entries = [
        makeEntry('a', localDay(2026, 11, 6), 10),
        makeEntry('b', localDay(2026, 11, 1), 10, -0.5)
      ];
      // 近 7 天（11/1 起）：11/1 那篇在范围内但没记心情的另一篇不算
      const data = StatsCalculator.moodChartData(entries.slice(0, 1), StatsRange.week, now);
      expect(data.isEmpty).assertTrue();
      expect(data.total).assertEqual(0);
    });

    it('moodChartRespectsRange', 0, () => {
      const now = localDay(2026, 11, 7);
      const entries = [
        makeEntry('in', localDay(2026, 11, 2), 10, 0.5),
        makeEntry('out', localDay(2026, 10, 20), 10, 0.5) // 近 30 天之外
      ];
      const week = StatsCalculator.moodChartData(entries, StatsRange.week, now);
      expect(week.total).assertEqual(1);
      const all = StatsCalculator.moodChartData(entries, StatsRange.all, now);
      expect(all.total).assertEqual(2);
    });
  });
}

export function writingStreakTest() {
  describe('WritingStreakTest', () => {
    it('noEntriesMeansZero', 0, () => {
      // U16：没写过、也没记过 → 0（6.3 验收「今天没写 = 0」的 U16 语义）
      expect(WritingStreak.best(0, [])).assertEqual(0);
      expect(WritingStreak.longestRun([])).assertEqual(0);
    });

    it('consecutiveDaysCount', 0, () => {
      const dates = [localDay(2026, 11, 1), localDay(2026, 11, 2), localDay(2026, 11, 3)];
      expect(WritingStreak.longestRun(dates)).assertEqual(3);
    });

    it('gapResetsRunButKeepsBest', 0, () => {
      const dates = [
        localDay(2026, 11, 1), localDay(2026, 11, 2), localDay(2026, 11, 3),
        localDay(2026, 11, 10), localDay(2026, 11, 11)
      ];
      // 最长的一段是 3 天，中间断了不归零、也不清零另一段
      expect(WritingStreak.longestRun(dates)).assertEqual(3);
    });

    it('sameDayMultipleEntriesCountOnce', 0, () => {
      const day1 = localDay(2026, 11, 1);
      const day2 = localDay(2026, 11, 2);
      const dates = [day1 + 3600000, day1 + 7200000, day2 + 3600000];
      expect(WritingStreak.longestRun(dates)).assertEqual(2);
    });

    it('runSpansMonthBoundary', 0, () => {
      const dates = [localDay(2026, 10, 31), localDay(2026, 11, 1)];
      expect(WritingStreak.longestRun(dates)).assertEqual(2);
    });

    it('bestTakesMaxOfRecordedAndComputed', 0, () => {
      // 记下的 30 天比现在日记里的 2 天长：显示 30（断了也不往下掉）
      const dates = [localDay(2026, 11, 1), localDay(2026, 11, 2)];
      expect(WritingStreak.best(30, dates)).assertEqual(30);
      expect(WritingStreak.best(1, dates)).assertEqual(2);
    });

    it('raiseOnlyGoesUp', 0, () => {
      // 只升不降（U16）：新算的更小不降级
      expect(WritingStreak.raisedValue(30, 5)).assertEqual(30);
      expect(WritingStreak.raisedValue(5, 31)).assertEqual(31);
      expect(WritingStreak.raisedValue(0, 0)).assertEqual(0);
    });
  });
}

/** 默认聚合：一次注册本文件全部套件 */
export default function statsCalculatorBundle() {
  statsCalculatorTest();
  writingStreakTest();
}
