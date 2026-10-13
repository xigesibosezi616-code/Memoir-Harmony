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
  dayOnes
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
  })
}
