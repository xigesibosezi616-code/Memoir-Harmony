/**
 * AppDateFormatters 纯逻辑单测（10_BUILD_MANUAL.md 1.2）。
 * 对应 iOS `Extensions/Date+Formatting.swift` 的行为，日期跟 App 语言（R-LANG-08）。
 *
 * 固定样例日期：2026-09-27（星期日）、2026-01-05（星期一）、2026-04-10（星期五）。
 * 非 zh 断言依赖标准 Intl（设备与开发机同 CLDR 数据）。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  isChineseLanguage,
  yearMonthKey,
  dayAndWeekday,
  shortDate,
  monthYearUppercased,
  dayString,
  weekdayString,
  dayTens,
  dayOnes,
  fullDate,
  monthDayNumeric,
  firstWeekdayIndex,
  weekdayNarrowSymbols,
  weekdayNarrow,
  relativeNamed
} from '../../main/ets/services/AppDateFormatters';

/** 2026-09-27 是星期日（本地时区构造，字段取本地值，断言与跑测时区无关） */
const SEP27: Date = new Date(2026, 8, 27);
/** 2026-01-05 是星期一 */
const JAN5: Date = new Date(2026, 0, 5);
/** 2026-04-10 是星期五 */
const APR10: Date = new Date(2026, 3, 10);

export default function appDateFormattersTest() {
  describe('AppDateFormattersTest', () => {
    // ---- 语言判定 ----
    it('isChineseLanguage', 0, () => {
      expect(isChineseLanguage('zh-Hans')).assertTrue();
      expect(isChineseLanguage('zh-Hant')).assertTrue();
      expect(isChineseLanguage('en')).assertFalse();
      expect(isChineseLanguage('ja')).assertFalse();
      expect(isChineseLanguage('ko')).assertFalse();
      expect(isChineseLanguage('fr')).assertFalse();
      expect(isChineseLanguage('es')).assertFalse();
    })

    // ---- 中文分支：手动拼接，M/d 不补零（「2026年9月」「9月27日」）----
    it('chineseYearMonthKeyDoesNotPad', 0, () => {
      expect(yearMonthKey(SEP27, 'zh-Hans')).assertEqual('2026年9月');
      expect(yearMonthKey(JAN5, 'zh-Hans')).assertEqual('2026年1月');
      expect(yearMonthKey(APR10, 'zh-Hant')).assertEqual('2026年4月');
    })

    it('chineseShortDate', 0, () => {
      expect(shortDate(SEP27, 'zh-Hans')).assertEqual('9月27日');
      expect(shortDate(JAN5, 'zh-Hant')).assertEqual('1月5日');
    })

    it('chineseDayAndWeekday', 0, () => {
      expect(dayAndWeekday(SEP27, 'zh-Hans')).assertEqual('9月27日 星期日');
      expect(dayAndWeekday(JAN5, 'zh-Hans')).assertEqual('1月5日 星期一');
    })

    it('chineseWeekdayString', 0, () => {
      expect(weekdayString(SEP27, 'zh-Hans')).assertEqual('星期日');
      expect(weekdayString(APR10, 'zh-Hant')).assertEqual('星期五');
    })

    it('chineseMonthYearUppercasedUnchanged', 0, () => {
      expect(monthYearUppercased(APR10, 'zh-Hans')).assertEqual('2026年4月');
    })

    // ---- 非 zh 分支：Intl 片段 + iOS pattern 顺序拼装 ----
    it('englishYearMonthKey', 0, () => {
      expect(yearMonthKey(SEP27, 'en')).assertEqual('September 2026');
      expect(yearMonthKey(APR10, 'en')).assertEqual('April 2026');
    })

    it('englishShortDate', 0, () => {
      expect(shortDate(SEP27, 'en')).assertEqual('Sep 27');
      expect(shortDate(JAN5, 'en')).assertEqual('Jan 5');
    })

    it('englishDayAndWeekday', 0, () => {
      expect(dayAndWeekday(SEP27, 'en')).assertEqual('Sep 27, 2026 · Sunday');
      expect(dayAndWeekday(APR10, 'en')).assertEqual('Apr 10, 2026 · Friday');
    })

    it('englishMonthYearUppercased', 0, () => {
      expect(monthYearUppercased(APR10, 'en')).assertEqual('APRIL 2026');
    })

    it('japaneseShortDateAndWeekday', 0, () => {
      expect(shortDate(SEP27, 'ja')).assertEqual('9月 27');
      expect(yearMonthKey(SEP27, 'ja')).assertEqual('9月 2026');
      expect(weekdayString(SEP27, 'ja')).assertEqual('日曜日');
    })

    it('frenchYearMonthKey', 0, () => {
      expect(yearMonthKey(APR10, 'fr')).assertEqual('avril 2026');
    })

    // ---- 数字类（与语言无关）----
    it('dayStringZeroPadded', 0, () => {
      expect(dayString(JAN5)).assertEqual('05');
      expect(dayString(SEP27)).assertEqual('27');
    })

    it('dayTensAndOnes', 0, () => {
      expect(dayTens(SEP27)).assertEqual('2');
      expect(dayOnes(SEP27)).assertEqual('7');
      expect(dayTens(JAN5)).assertEqual('0');
      expect(dayOnes(JAN5)).assertEqual('5');
    })

    // ---- 6.3 写作统计 ----

    it('fullDateFollowsLanguage', 0, () => {
      expect(fullDate(SEP27, 'zh-Hans')).assertEqual('2026年9月27日');
      expect(fullDate(SEP27, 'en')).assertEqual('September 27, 2026');
    })

    it('monthDayNumericForTrendAxis', 0, () => {
      expect(monthDayNumeric(SEP27, 'zh-Hans')).assertEqual('9/27');
      expect(monthDayNumeric(SEP27, 'en')).assertEqual('9/27');
    })

    it('firstWeekdayIndexFollowsCLDR', 0, () => {
      expect(firstWeekdayIndex('zh-Hans')).assertEqual(0);
      expect(firstWeekdayIndex('zh-Hant')).assertEqual(0);
      expect(firstWeekdayIndex('en')).assertEqual(0);
      expect(firstWeekdayIndex('ja')).assertEqual(0);
      expect(firstWeekdayIndex('ko')).assertEqual(0);
      expect(firstWeekdayIndex('fr')).assertEqual(1);
      expect(firstWeekdayIndex('es')).assertEqual(1);
    })

    it('weekdayNarrowSymbolsStartFromFirstDay', 0, () => {
      const zh = weekdayNarrowSymbols('zh-Hans');
      expect(zh.length).assertEqual(7);
      expect(zh.join('')).assertEqual('日一二三四五六');
      const en = weekdayNarrowSymbols('en');
      expect(en[0]).assertEqual('S'); // Sunday 起
      const fr = weekdayNarrowSymbols('fr');
      expect(fr[0]).assertEqual('L'); // Monday 起
    })

    it('weekdayNarrowByIndex', 0, () => {
      expect(weekdayNarrow(0, 'zh-Hans')).assertEqual('日');
      expect(weekdayNarrow(3, 'zh-Hans')).assertEqual('三');
      expect(weekdayNarrow(6, 'zh-Hans')).assertEqual('六');
    })

    // ---- U01 邮票：下一包几时到的相对时间（named 语感，CLDR 出词） ----

    it('relativeNamedReturnsEmptyWhenTargetIsNow', 0, () => {
      // 已经到了 / 快到了（≤1 分钟）→ ''（调用方换「新的一包很快就到」）
      expect(relativeNamed(Date.now(), 'zh-Hans').length === 0).assertTrue();
      expect(relativeNamed(Date.now() + 30_000, 'en').length === 0).assertTrue();
      // 过去了也 ''（服务端时钟快了半分钟之类）
      expect(relativeNamed(Date.now() - 60_000, 'zh-Hans').length === 0).assertTrue();
    })

    it('relativeNamedCallsDaysAcrossCalendarDays', 0, () => {
      // 明晚到（今晚 23 点 → 明晚 20 点）说的是「明天」不是「20 小时后」：
      // 跨了日历日（差 1）就用天，叫出名字
      const tonight = new Date();
      tonight.setHours(23, 0, 0, 0);
      const tomorrowEvening = new Date(tonight.getTime());
      tomorrowEvening.setDate(tomorrowEvening.getDate() + 1);
      tomorrowEvening.setHours(20, 0, 0, 0);
      expect(relativeNamed(tomorrowEvening.getTime(), 'zh-Hans')).assertEqual('明天');
      expect(relativeNamed(tomorrowEvening.getTime(), 'en')).assertEqual('tomorrow');
      // 后天（跨 2 个日历日）
      const dayAfter = new Date(tonight.getTime());
      dayAfter.setDate(dayAfter.getDate() + 2);
      dayAfter.setHours(12, 0, 0, 0);
      expect(relativeNamed(dayAfter.getTime(), 'zh-Hans')).assertEqual('后天');
    })

    it('relativeNamedUsesMinutesWithinTheHour', 0, () => {
      // 当天且不到 1 小时：分钟（numeric:'auto' 的「N 分钟后」）。
      // 固定挑本小时内剩下的分钟（30 封顶）：临近午夜 Date.now()+30min 会跨日历日、
      // 走到「天」分支（2026-11-10 23:47 跑挂过）；本小时不够 2 分钟就跳过
      const now = new Date();
      const minutesAhead = Math.min(30, 59 - now.getMinutes());
      if (minutesAhead >= 2) {
        const target = now.getTime() + minutesAhead * 60_000;
        const text = relativeNamed(target, 'zh-Hans');
        expect(text.indexOf('分钟') >= 0).assertTrue();
      }
    })

    it('relativeNamedUsesHoursWithinTheDay', 0, () => {
      // 当天、1 小时以上：小时（只认本地时区，测试按本地日历日差 0 构造）
      const now = new Date();
      const target = new Date(now.getTime() + 3 * 3_600_000);
      if (target.getDate() === now.getDate()) {
        const text = relativeNamed(target.getTime(), 'zh-Hans');
        expect(text.indexOf('小时') >= 0).assertTrue();
        const en = relativeNamed(target.getTime(), 'en');
        expect(en.indexOf('hour') >= 0).assertTrue();
      }
    })
  })
}
