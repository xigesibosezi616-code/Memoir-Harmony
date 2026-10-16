/**
 * 记录页列表模式纯逻辑单测（10_BUILD_MANUAL.md 2.2）。
 * 对应 iOS `HomeView` 的 monthRecordDays / groupedEntries：
 * 本月天数（同日去重 / 跨月 / 跨年边界）、年月分组（倒序相邻成组、组内倒序）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { JournalEntry } from '../../main/ets/models/JournalEntry';
import {
  EntryGroup,
  groupedEntries,
  monthRecordDays
} from '../../main/ets/data/HomeLogic';

let idCounter = 0;
function makeEntry(date: Date): JournalEntry {
  idCounter++;
  const t = date.getTime();
  return new JournalEntry(`home-test-${idCounter}`, t, t, t);
}

/** 本地某天的 12:00（避开午夜边界） */
function noon(year: number, month: number, day: number): Date {
  return new Date(year, month, day, 12, 0, 0);
}

export default function homeLogicTest() {
  describe('HomeLogicTest', () => {

    // ---- monthRecordDays（R-HOME-01「本月记录 N 天」） ----

    it('emptyEntriesCountZeroDays', 0, () => {
      expect(monthRecordDays([], noon(2026, 9, 15))).assertEqual(0);
    })

    it('sameDayEntriesCountOnce', 0, () => {
      // 同一天写两篇只算一天
      const entries = [makeEntry(noon(2026, 9, 15)), makeEntry(noon(2026, 9, 15))];
      expect(monthRecordDays(entries, noon(2026, 9, 20))).assertEqual(1);
    })

    it('countsDistinctDaysInCurrentMonth', 0, () => {
      const entries = [
        makeEntry(noon(2026, 9, 1)),
        makeEntry(noon(2026, 9, 15)),
        makeEntry(noon(2026, 9, 30))
      ];
      expect(monthRecordDays(entries, noon(2026, 9, 20))).assertEqual(3);
    })

    it('ignoresOtherMonthsAndYears', 0, () => {
      const entries = [
        makeEntry(noon(2026, 9, 15)),
        makeEntry(noon(2026, 8, 15)),  // 上月同日
        makeEntry(noon(2025, 9, 15))   // 去年同月同日
      ];
      expect(monthRecordDays(entries, noon(2026, 9, 20))).assertEqual(1);
    })

    it('monthBoundaryIsLocalCalendar', 0, () => {
      // 10-31 / 11-01 分属两个月（本地日历，不按 30 天窗）
      const entries = [makeEntry(noon(2026, 9, 31)), makeEntry(noon(2026, 10, 1))];
      expect(monthRecordDays(entries, noon(2026, 9, 31))).assertEqual(1);
      expect(monthRecordDays(entries, noon(2026, 10, 2))).assertEqual(1);
    })

    // ---- groupedEntries（R-HOME-02 列表分组吸顶） ----

    it('emptyEntriesMakeNoGroups', 0, () => {
      expect(groupedEntries([], 'zh-Hans').length).assertEqual(0);
    })

    it('adjacentMonthsBecomeGroupsInOrder', 0, () => {
      // 已按 date 倒序：10 月组在前、9 月组在后（最近月在最前）
      // （month 参数 0 基：9=10 月、8=9 月；8 月 31 日不存在会滚进 10 月，用 30）
      const entries = [
        makeEntry(noon(2026, 9, 30)),
        makeEntry(noon(2026, 9, 2)),
        makeEntry(noon(2026, 8, 30)),
        makeEntry(noon(2026, 8, 1))
      ];
      const groups = groupedEntries(entries, 'zh-Hans');
      expect(groups.length).assertEqual(2);
      expect(groups[0].key).assertEqual('2026年10月');
      expect(groups[0].entries.length).assertEqual(2);
      expect(groups[1].key).assertEqual('2026年9月');
      expect(groups[1].entries.length).assertEqual(2);
    })

    it('entriesInsideGroupKeepDescendingOrder', 0, () => {
      const entries = [
        makeEntry(noon(2026, 9, 30)),
        makeEntry(noon(2026, 9, 15)),
        makeEntry(noon(2026, 9, 1))
      ];
      const groups = groupedEntries(entries, 'zh-Hans');
      expect(groups.length).assertEqual(1);
      const dates = groups[0].entries.map((e: JournalEntry): number => e.date);
      expect(dates[0] > dates[1]).assertTrue();
      expect(dates[1] > dates[2]).assertTrue();
    })

    it('yearBoundarySplitsGroups', 0, () => {
      // 跨年：2027-01 与 2026-12 各成一组，且 2027 在前
      const entries = [
        makeEntry(noon(2027, 0, 3)),
        makeEntry(noon(2026, 11, 30))
      ];
      const groups = groupedEntries(entries, 'zh-Hans');
      expect(groups.length).assertEqual(2);
      expect(groups[0].key).assertEqual('2027年1月');
      expect(groups[1].key).assertEqual('2026年12月');
    })

    it('nonZhLanguageUsesLocalizedHeader', 0, () => {
      // 非中文组头交给 yearMonthKey（"MMMM yyyy"），分组结构不变
      const entries = [makeEntry(noon(2026, 9, 15))];
      const groups = groupedEntries(entries, 'en');
      expect(groups.length).assertEqual(1);
      expect(groups[0].key !== '2026年10月').assertTrue();
      expect(groups[0].key.length > 0).assertTrue();
    })

    it('sameMonthNonAdjacentStillOneGroup', 0, () => {
      // 前置条件是倒序相邻；这里验证结果正确性 —— iOS
      // Dictionary(grouping:) 的结果与此一致（排序键相同）
      const entries = [
        makeEntry(noon(2026, 9, 20)),
        makeEntry(noon(2026, 9, 10))
      ];
      const groups: EntryGroup[] = groupedEntries(entries, 'zh-Hans');
      expect(groups.length).assertEqual(1);
      expect(groups[0].entries.length).assertEqual(2);
    })
  })
}
