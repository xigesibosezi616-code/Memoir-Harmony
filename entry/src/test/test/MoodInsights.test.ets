/**
 * 情绪捕捉（U14-1）纯计算单测：造 60 篇带心情 / 天气 / 地点的合成日记，
 * 验证每一张图的分组、平均心情落档、≥ 3 篇门槛、排序与上限 ——
 * 和 iOS `MoodInsights` 同样的数据必须得出同样的组（U14-1 验收）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { JournalEntry } from '../../main/ets/models/JournalEntry';
import { MoodLevel, MoodLevels } from '../../main/ets/models/MoodLevel';
import { MoodLabel, MoodLabels } from '../../main/ets/models/MoodLabel';
import { StatsRange, StatsRanges } from '../../main/ets/models/StatsCalculator';
import { MoodInsights, MoodItem, TrendBucket, WeatherKind, DayPart } from '../../main/ets/models/MoodInsights';

function localDay(year: number, month: number, day: number, hour: number = 12): number {
  return new Date(year, month - 1, day, hour).getTime();
}

/** 造一篇带心情 / 天气 / 地点 / 情绪词的日记 */
function makeMoodEntry(id: string, dateMs: number, valence: number,
  weatherCode?: string, locationInfo?: string, moodLabel?: string): JournalEntry {
  const entry = new JournalEntry(id, dateMs, dateMs, dateMs);
  entry.moodValence = valence;
  if (weatherCode !== undefined) {
    entry.weatherCode = weatherCode;
  }
  if (locationInfo !== undefined) {
    entry.locationInfo = locationInfo;
  }
  if (moodLabel !== undefined) {
    entry.moodLabels = [moodLabel];
  }
  return entry;
}

export function moodInsightsTest() {
  describe('MoodInsightsTest', () => {
    const now = localDay(2026, 11, 7);

    // ---- 只算记了心情的 ----

    it('moodEntriesSkipsThoseWithoutValence', 0, () => {
      const entries = [
        makeMoodEntry('a', localDay(2026, 11, 6), 0.5),
        new JournalEntry('b', localDay(2026, 11, 5), 0, 0), // 没记心情
        makeMoodEntry('c', localDay(2026, 10, 1), 0.2)      // 近 7 天之外
      ];
      const items = MoodInsights.moodEntries(entries, StatsRange.week, now);
      expect(items.length).assertEqual(1);
      expect(items[0].entry.id).assertEqual('a');
      expect(items[0].valence).assertEqual(0.5);
    });

    it('averageValenceIsNullWhenEmpty', 0, () => {
      expect(MoodInsights.averageValence([])).assertNull();
      const avg = MoodInsights.averageValence(
        [new MoodItem(makeMoodEntry('a', 0, 0.2), 0.2),
          new MoodItem(makeMoodEntry('b', 0, 0.4), 0.4),
          new MoodItem(makeMoodEntry('c', 0, 0.3), 0.3)]);
      expect(avg !== null && Math.abs(avg - 0.3) < 1e-9).assertTrue();
    });

    // ---- 心情走势 ----

    it('trendBucketsByDayThenMonth', 0, () => {
      const items: MoodItem[] = [
        new MoodItem(makeMoodEntry('a', localDay(2026, 11, 5, 8), 0.2), 0.2),
        new MoodItem(makeMoodEntry('b', localDay(2026, 11, 5, 20), 0.6), 0.6), // 同一天 → 一格
        new MoodItem(makeMoodEntry('c', localDay(2026, 11, 6, 9), -0.4), -0.4)
      ];
      const byDay = MoodInsights.trend(items, TrendBucket.day);
      expect(byDay.length).assertEqual(2);
      // 格起点是当天 0 点（不是造数据用的正午）
      expect(byDay[0].startMs).assertEqual(new Date(2026, 10, 5).getTime());
      expect(byDay[0].valence).assertEqual(0.4);
      expect(byDay[0].count).assertEqual(2);
      expect(byDay[1].valence).assertEqual(-0.4);

      const oct = new MoodItem(makeMoodEntry('d', localDay(2026, 10, 2), -0.8), -0.8);
      const byMonth = MoodInsights.trend(items.concat([oct]), TrendBucket.month);
      expect(byMonth.length).assertEqual(2);
      expect(byMonth[0].startMs).assertEqual(new Date(2026, 9, 1).getTime());
      expect(byMonth[0].valence).assertEqual(-0.8);
      expect(byMonth[1].startMs).assertEqual(new Date(2026, 10, 1).getTime());
    });

    it('bucketFollowsRange', 0, () => {
      expect(MoodInsights.bucket(StatsRange.week)).assertEqual(TrendBucket.day);
      expect(MoodInsights.bucket(StatsRange.month)).assertEqual(TrendBucket.day);
      expect(MoodInsights.bucket(StatsRange.year)).assertEqual(TrendBucket.month);
      expect(MoodInsights.bucket(StatsRange.all)).assertEqual(TrendBucket.month);
    });

    it('levelCountsNineBuckets', 0, () => {
      const items: MoodItem[] = [
        new MoodItem(makeMoodEntry('a', 0, -1), -1),
        new MoodItem(makeMoodEntry('b', 0, 0), 0),
        new MoodItem(makeMoodEntry('c', 0, 1), 1),
        new MoodItem(makeMoodEntry('d', 0, 1), 1)
      ];
      const counts = MoodInsights.levelCounts(items);
      expect(counts.length).assertEqual(9);
      expect(counts[MoodLevel.rockBottom]).assertEqual(1);
      expect(counts[MoodLevel.even]).assertEqual(1);
      expect(counts[MoodLevel.overjoyed]).assertEqual(2);
    });

    // ---- 最常出现的情绪 ----

    it('topLabelsOrderTieBreakAndLimit', 0, () => {
      const entries: JournalEntry[] = [
        makeMoodEntry('a', localDay(2026, 11, 6), 0.5, undefined, undefined, 'happy'),
        makeMoodEntry('b', localDay(2026, 11, 5), 0.5, undefined, undefined, 'happy'),
        makeMoodEntry('c', localDay(2026, 11, 4), 0.5, undefined, undefined, 'happy'),
        makeMoodEntry('d', localDay(2026, 11, 3), 0.1, undefined, undefined, 'calm'),
        makeMoodEntry('e', localDay(2026, 11, 2), 0.1, undefined, undefined, 'calm'),
        makeMoodEntry('f', localDay(2026, 11, 1), -0.9, undefined, undefined, 'hopeless'),
        makeMoodEntry('g', localDay(2026, 10, 30), -0.9, undefined, undefined, 'future_unknown_label')
      ];
      const items = MoodInsights.moodEntries(entries, StatsRange.month, now);
      const labels = MoodInsights.topLabels(items);
      // 次数多的在前；不认识的 key（future_unknown_label）跳过
      expect(labels.length).assertEqual(3);
      expect(labels[0].label).assertEqual(MoodLabel.happy);
      expect(labels[0].count).assertEqual(3);
      expect(labels[1].label).assertEqual(MoodLabel.calm);
      expect(labels[2].label).assertEqual(MoodLabel.hopeless);
    });

    it('topLabelsTieBreaksByLevelAscending', 0, () => {
      const entries: JournalEntry[] = [
        makeMoodEntry('a', localDay(2026, 11, 6), 0.9, undefined, undefined, 'excited'),
        makeMoodEntry('b', localDay(2026, 11, 5), -0.9, undefined, undefined, 'scared')
      ];
      const items = MoodInsights.moodEntries(entries, StatsRange.month, now);
      const labels = MoodInsights.topLabels(items);
      // 同为 1 次：九档低的（scared < excited）在前
      expect(labels[0].label).assertEqual(MoodLabel.scared);
      expect(labels[1].label).assertEqual(MoodLabel.excited);
    });

    // ---- 天气与心情 ----

    it('weatherKindMappingMatchesIOS', 0, () => {
      // WeatherKit SF Symbol 名 + 老自定义代码都认（iOS 同款小写包含匹配）
      expect(MoodInsights.weatherKindFromCode('cloud.sun.rain')).assertEqual(WeatherKind.rain);
      expect(MoodInsights.weatherKindFromCode('sun.max')).assertEqual(WeatherKind.clear);
      expect(MoodInsights.weatherKindFromCode('cloud')).assertEqual(WeatherKind.cloudy);
      expect(MoodInsights.weatherKindFromCode('snow')).assertEqual(WeatherKind.snow);
      expect(MoodInsights.weatherKindFromCode('heavyRain')).assertEqual(WeatherKind.rain);
      expect(MoodInsights.weatherKindFromCode('wind')).assertEqual(WeatherKind.wind);
      expect(MoodInsights.weatherKindFromCode('fog')).assertEqual(WeatherKind.fog);
      // 'thermometer.snowflake' 含 snow：iOS 同款包含匹配同样归雪（以代码为准）
      expect(MoodInsights.weatherKindFromCode('thermometer.snowflake')).assertEqual(WeatherKind.snow);
      expect(MoodInsights.weatherKindFromCode('thermometer.medium')).assertUndefined();
    });

    it('byWeatherNeedsThreeAndAveragesToLevel', 0, () => {
      const entries: JournalEntry[] = [
        makeMoodEntry('a', localDay(2026, 11, 6), 0.2, 'sun.max'),
        makeMoodEntry('b', localDay(2026, 11, 5), 0.4, 'sun.max'),
        makeMoodEntry('c', localDay(2026, 11, 4), 0.3, 'sun.max'),
        makeMoodEntry('d', localDay(2026, 11, 3), -0.5, 'cloud.bolt'), // 只有 1 篇：不显示
        makeMoodEntry('e', localDay(2026, 11, 2), 0.1)                 // 没天气：不算
      ];
      const items = MoodInsights.moodEntries(entries, StatsRange.month, now);
      const weather = MoodInsights.byWeather(items);
      expect(weather.length).assertEqual(1);
      expect(weather[0].kind).assertEqual(WeatherKind.clear);
      // 平均 0.3 → 怡然自得（与 iOS 同一组数据落同一档，U14-1 验收；浮点留容差）
      expect(Math.abs(weather[0].group.valence - 0.3) < 1e-9).assertTrue();
      expect(weather[0].group.level).assertEqual(MoodLevel.content);
      expect(weather[0].group.count).assertEqual(3);
    });

    // ---- 地点与心情 ----

    it('byPlaceTrimsSortsAndLimits', 0, () => {
      const entries: JournalEntry[] = [];
      // 家 4 篇、公司 3 篇、学校 2 篇（不足 3 不显示）、地点带空白要 trim
      for (let i = 0; i < 4; i++) {
        entries.push(makeMoodEntry(`h${i}`, localDay(2026, 11, 6 - i), 0.8, undefined, ' 家 '));
      }
      for (let i = 0; i < 3; i++) {
        entries.push(makeMoodEntry(`w${i}`, localDay(2026, 11, 6 - i), -0.2, undefined, '公司'));
      }
      for (let i = 0; i < 2; i++) {
        entries.push(makeMoodEntry(`s${i}`, localDay(2026, 11, 6 - i), 0, undefined, '学校'));
      }
      const items = MoodInsights.moodEntries(entries, StatsRange.month, now);
      const places = MoodInsights.byPlace(items);
      expect(places.length).assertEqual(2);
      expect(places[0].id).assertEqual('家');
      expect(places[0].count).assertEqual(4);
      expect(places[0].level).assertEqual(MoodLevel.overjoyed); // 0.8 → 心花怒放
      expect(places[1].id).assertEqual('公司');
      expect(places[1].count).assertEqual(3);
    });

    // ---- 星期与时段 ----

    it('byWeekdayFollowsFirstDayAndFilters', 0, () => {
      // 2026-11-01 是周日，02 周一 … 07 周六
      const entries: JournalEntry[] = [
        makeMoodEntry('s1', localDay(2026, 11, 1), 0.6),
        makeMoodEntry('s2', localDay(2026, 11, 8 - 7), 0.6),
        makeMoodEntry('s3', localDay(2026, 11, 15 - 14), 0.6),
        makeMoodEntry('m1', localDay(2026, 11, 2), -0.4),
        makeMoodEntry('m2', localDay(2026, 11, 9 - 7), -0.4)
      ];
      const items = MoodInsights.moodEntries(entries, StatsRange.month, localDay(2026, 11, 20));
      const fromSunday = MoodInsights.byWeekday(items, 0);
      expect(fromSunday.length).assertEqual(1); // 周一只有 2 篇：不显示
      expect(fromSunday[0].weekday).assertEqual(0);
      expect(fromSunday[0].group.count).assertEqual(3);
      // 周一起头：周一那组（哪怕不足 3）也不会插到前面——过滤在排序后仍保序
      const fromMonday = MoodInsights.byWeekday(items, 1);
      expect(fromMonday.length).assertEqual(1);
      expect(fromMonday[0].weekday).assertEqual(0);
    });

    it('dayPartBoundariesMatchIOS', 0, () => {
      expect(MoodInsights.dayPartOfHour(5)).assertEqual(DayPart.morning);
      expect(MoodInsights.dayPartOfHour(10)).assertEqual(DayPart.morning);
      expect(MoodInsights.dayPartOfHour(11)).assertEqual(DayPart.afternoon);
      expect(MoodInsights.dayPartOfHour(16)).assertEqual(DayPart.afternoon);
      expect(MoodInsights.dayPartOfHour(17)).assertEqual(DayPart.evening);
      expect(MoodInsights.dayPartOfHour(22)).assertEqual(DayPart.evening);
      expect(MoodInsights.dayPartOfHour(23)).assertEqual(DayPart.night);
      expect(MoodInsights.dayPartOfHour(4)).assertEqual(DayPart.night);
    });

    it('byDayPartGroupsAndFilters', 0, () => {
      const entries: JournalEntry[] = [
        makeMoodEntry('n1', localDay(2026, 11, 6, 0), -0.6),
        makeMoodEntry('n2', localDay(2026, 11, 5, 1), -0.6),
        makeMoodEntry('n3', localDay(2026, 11, 4, 2), -0.6),
        makeMoodEntry('e1', localDay(2026, 11, 6, 18), 0.4),
        makeMoodEntry('e2', localDay(2026, 11, 5, 19), 0.4)
      ];
      const items = MoodInsights.moodEntries(entries, StatsRange.month, now);
      const parts = MoodInsights.byDayPart(items);
      expect(parts.length).assertEqual(1); // 晚上 2 篇不足 3
      expect(parts[0].part).assertEqual(DayPart.night);
      expect(parts[0].group.count).assertEqual(3);
      expect(parts[0].group.level).assertEqual(MoodLevel.heartsick); // -0.6 → 黯然神伤
    });

    // ---- U14-1 验收：60 篇合成日记 ----

    it('sixtySyntheticEntriesMatchExpectedGroups', 0, () => {
      const entries: JournalEntry[] = [];
      // 60 篇铺在 2026-10-09 … 2026-11-07（近 30 天全覆盖）：
      // - 逢单数篇 valence=0.6（神采飞扬），逢双数篇 valence=-0.4（郁郁寡欢）
      // - 天气轮换 sun.max / cloud.rain / cloud（各 20 篇）
      // - 地点轮换 家 / 公司 / 学校（各 20 篇）
      // - 小时轮换 8 / 14 / 20 / 1（早上 / 下午 / 晚上 / 深夜各 15 篇）
      for (let i = 0; i < 60; i++) {
        const dayOffset = i % 30;
        const dateMs = localDay(2026, 11, 7 - dayOffset, [8, 14, 20, 1][i % 4]);
        const valence = i % 2 === 0 ? 0.6 : -0.4;
        const weather = ['sun.max', 'cloud.rain', 'cloud'][i % 3];
        const place = ['家', '公司', '学校'][i % 3];
        entries.push(makeMoodEntry(`e${i}`, dateMs, valence, weather, place));
      }
      const items = MoodInsights.moodEntries(entries, StatsRange.month, now);
      expect(items.length).assertEqual(60);

      // 平均心情 = (0.6 + -0.4) × 30 / 60 = 0.1 → 怡然自得（浮点留容差）
      const avg = MoodInsights.averageValence(items);
      expect(avg !== null && Math.abs(avg - 0.1) < 1e-9).assertTrue();

      // 心情分布：神采飞扬 / 郁郁寡欢各 30 篇
      const counts = MoodInsights.levelCounts(items);
      expect(counts[MoodLevel.radiant]).assertEqual(30);
      expect(counts[MoodLevel.melancholy]).assertEqual(30);

      // 天气三组各 20 篇；单数篇（-0.4）全部落在雨天上 → 雨那组均值偏负
      const weather = MoodInsights.byWeather(items);
      expect(weather.length).assertEqual(3);
      expect(weather[0].kind).assertEqual(WeatherKind.clear);
      expect(weather[0].group.count).assertEqual(20);
      expect(weather[1].kind).assertEqual(WeatherKind.cloudy);
      expect(weather[1].group.count).assertEqual(20);
      expect(weather[2].kind).assertEqual(WeatherKind.rain);
      expect(weather[2].group.count).assertEqual(20);
      // i%3==1 的 20 篇全是雨：其中 10 篇单数（-0.4）、10 篇双数（0.6）→ 均值 0.1
      expect(Math.abs(weather[2].group.valence - 0.1) < 1e-9).assertTrue();

      // 地点三组各 20 篇
      const places = MoodInsights.byPlace(items);
      expect(places.length).assertEqual(3);
      expect(places[0].count).assertEqual(20);

      // 时段：小时按 i%4 轮换 → 早上 / 下午 / 晚上 / 深夜各 15 篇（各 ≥ 3 都显示）
      const parts = MoodInsights.byDayPart(items);
      expect(parts.length).assertEqual(4);
      expect(parts[0].part).assertEqual(DayPart.morning);
      expect(parts[0].group.count).assertEqual(15);
      expect(parts[3].part).assertEqual(DayPart.night);
      expect(parts[3].group.count).assertEqual(15);

      // 走势（近 30 天按天）：每天 2 篇且同奇偶同号（i 与 i+30）→ 30 格；
      // 最早一天（10-09）落在 i=29、59，都是 -0.4 → 郁郁寡欢
      const trend = MoodInsights.trend(items, TrendBucket.day);
      expect(trend.length).assertEqual(30);
      expect(trend[0].count).assertEqual(2);
      expect(trend[0].level).assertEqual(MoodLevel.melancholy);
    });
  });
}

export function moodLevelTest() {
  describe('MoodLevelTest', () => {
    it('valenceMapsToNineSegments', 0, () => {
      expect(MoodLevels.fromValence(-1)).assertEqual(MoodLevel.rockBottom);
      expect(MoodLevels.fromValence(-0.9)).assertEqual(MoodLevel.rockBottom);
      expect(MoodLevels.fromValence(-0.7)).assertEqual(MoodLevel.heartsick);
      expect(MoodLevels.fromValence(-0.45)).assertEqual(MoodLevel.melancholy);
      expect(MoodLevels.fromValence(-0.2)).assertEqual(MoodLevel.glum);
      expect(MoodLevels.fromValence(0)).assertEqual(MoodLevel.even);
      expect(MoodLevels.fromValence(0.25)).assertEqual(MoodLevel.content);
      expect(MoodLevels.fromValence(0.5)).assertEqual(MoodLevel.joyful);
      expect(MoodLevels.fromValence(0.75)).assertEqual(MoodLevel.radiant);
      expect(MoodLevels.fromValence(1)).assertEqual(MoodLevel.overjoyed);
    });

    it('valenceIsClampedToRange', 0, () => {
      expect(MoodLevels.fromValence(-2)).assertEqual(MoodLevel.rockBottom);
      expect(MoodLevels.fromValence(1.5)).assertEqual(MoodLevel.overjoyed);
    });

    it('centerValenceOfEvenIsZero', 0, () => {
      expect(MoodLevels.centerValence(MoodLevel.even)).assertEqual(0);
    });

    it('tintsAreNineDistinctHexes', 0, () => {
      const set = new Set<string>();
      for (const level of MoodLevels.all) {
        set.add(MoodLevels.tintHex(level));
      }
      expect(set.size).assertEqual(9);
    });

    it('englishNamesStableForBackend', 0, () => {
      expect(MoodLevels.englishName(MoodLevel.glum)).assertEqual('a little glum');
      expect(MoodLevels.englishName(MoodLevel.overjoyed)).assertEqual('over the moon');
    });
  });
}

export function moodLabelTest() {
  describe('MoodLabelTest', () => {
    it('thirtyEightLabelsEachInExactlyOneLevel', 0, () => {
      const seen = new Set<MoodLabel>();
      let total = 0;
      for (const level of MoodLevels.all) {
        const choices = MoodLabels.choices(level);
        for (const label of choices) {
          expect(seen.has(label)).assertFalse();
          seen.add(label);
          total += 1;
        }
      }
      expect(total).assertEqual(38);
    });

    it('keyRoundTrip', 0, () => {
      for (const label of MoodLabels.all) {
        const key = MoodLabels.keyOf(label);
        const back = MoodLabels.fromKey(key);
        expect(back).assertEqual(label);
      }
    });

    it('unknownKeyIsUndefined', 0, () => {
      expect(MoodLabels.fromKey('no_such_label')).assertUndefined();
    });

    it('levelOfMatchesChoices', 0, () => {
      expect(MoodLabels.levelOf(MoodLabel.anxious)).assertEqual(MoodLevel.melancholy);
      expect(MoodLabels.levelOf(MoodLabel.calm)).assertEqual(MoodLevel.even);
      expect(MoodLabels.levelOf(MoodLabel.excited)).assertEqual(MoodLevel.overjoyed);
    });
  });
}

/** 默认聚合：一次注册本文件全部套件 */
export default function moodInsightsBundle() {
  moodInsightsTest();
  moodLevelTest();
  moodLabelTest();
}
