/**
 * App 内选定语言的日期格式化（10_BUILD_MANUAL.md 1.2）。
 * 对应 iOS `Extensions/Date+Formatting.swift`。
 *
 * 日期、数字格式跟 **App 语言**，不跟系统语言（R-LANG-08）。
 * 每个函数显式接受 `appLanguage`（七种之一，如 'zh-Hans' / 'en'），
 * 调用方从 `@StorageProp('appLanguage')` 取——语言一切换整页重渲染，日期当场变。
 *
 * 与 iOS 的 pattern 逐条对齐（iOS 用 DateFormatter 固定 pattern，token 顺序固定）：
 * - 中文（zh-Hans / zh-Hant）手动拼接，M/d 不补零；
 * - 其余语言用标准 `Intl.DateTimeFormat` 取片段（月名 / 星期名按 CLDR 本地化），
 *   再按同一 token 顺序拼装（en「Sep 27, 2026 · Sunday」、ja「9月 27, 2026 · 日曜日」…）。
 */

/** appLanguage 是否中文（简 / 繁）。iOS 用 locale.languageCode == 'zh' 判定 */
export function isChineseLanguage(appLanguage: string): boolean {
  return appLanguage === 'zh-Hans' || appLanguage === 'zh-Hant';
}

/** 月名片段：「September」（非中文）/ 空串（中文不用，调用方走手动拼接） */
function monthLong(date: Date, appLanguage: string): string {
  if (isChineseLanguage(appLanguage)) {
    return '';
  }
  return new Intl.DateTimeFormat(appLanguage, { month: 'long' }).format(date);
}

/** 短月名片段：「Sep」。fr 为「sept.」、ja 为「9月」（CLDR abbreviated，与 iOS MMM 一致） */
function monthShort(date: Date, appLanguage: string): string {
  if (isChineseLanguage(appLanguage)) {
    return '';
  }
  return new Intl.DateTimeFormat(appLanguage, { month: 'short' }).format(date);
}

/** 星期全名片段：「Wednesday」/「dimanche」/「日曜日」；中文「星期日」由调用方拼接 */
function weekdayLong(date: Date, appLanguage: string): string {
  if (isChineseLanguage(appLanguage)) {
    return '';
  }
  return new Intl.DateTimeFormat(appLanguage, { weekday: 'long' }).format(date);
}

/** 中文星期字：「日」…「六」（getDay() 0=周日） */
function chineseWeekdayChar(date: Date): string {
  const chars: string[] = ['日', '一', '二', '三', '四', '五', '六'];
  return chars[date.getDay()];
}

/** 「2026年9月」/「September 2026」——记录页年月分组头、日记本年月跨度 */
export function yearMonthKey(date: Date, appLanguage: string): string {
  const year = date.getFullYear();
  const month = date.getMonth() + 1; // getMonth 从 0 起
  if (isChineseLanguage(appLanguage)) {
    return `${year}年${month}月`;
  }
  return `${monthLong(date, appLanguage)} ${year}`;
}

/** 「9月27日 星期日」/「Sep 27, 2026 · Sunday」——写日记页顶部日期 + 星期 */
export function dayAndWeekday(date: Date, appLanguage: string): string {
  const month = date.getMonth() + 1;
  const day = date.getDate();
  if (isChineseLanguage(appLanguage)) {
    return `${month}月${day}日 星期${chineseWeekdayChar(date)}`;
  }
  const year = date.getFullYear();
  return `${monthShort(date, appLanguage)} ${day}, ${year} · ${weekdayLong(date, appLanguage)}`;
}

/** 「9月27日」/「Sep 27」——列表行日期、补记日期、邮戳 */
export function shortDate(date: Date, appLanguage: string): string {
  if (isChineseLanguage(appLanguage)) {
    const month = date.getMonth() + 1;
    const day = date.getDate();
    return `${month}月${day}日`;
  }
  return `${monthShort(date, appLanguage)} ${date.getDate()}`;
}

/**
 * 「10月12日」/「Oct 12」——墨迹痕迹与「补记 · 最近」的日期（2.8，iOS `InkText.day`）：
 * 不是今年的带上年份（「2025年10月12日」/「Oct 12, 2025」）。
 */
export function inkDay(date: Date, appLanguage: string): string {
  const sameYear = date.getFullYear() === new Date().getFullYear();
  if (isChineseLanguage(appLanguage)) {
    const base = shortDate(date, appLanguage);
    return sameYear ? base : `${date.getFullYear()}年${base}`;
  }
  const base = `${monthShort(date, appLanguage)} ${date.getDate()}`;
  return sameYear ? base : `${base}, ${date.getFullYear()}`;
}

/** 「APRIL 2026」/「2026年4月」——月历大标题（中文无大小写，原样返回） */
export function monthYearUppercased(date: Date, appLanguage: string): string {
  return yearMonthKey(date, appLanguage).toUpperCase();
}

/** 零填充日号："05"（和纸版式大日期数字用） */
export function dayString(date: Date): string {
  return `${date.getDate() < 10 ? '0' : ''}${date.getDate()}`;
}

/** 星期全名：「星期三」/「Wednesday」（中文与 iOS EEEE 渲染一致） */
export function weekdayString(date: Date, appLanguage: string): string {
  if (isChineseLanguage(appLanguage)) {
    return `星期${chineseWeekdayChar(date)}`;
  }
  return weekdayLong(date, appLanguage);
}

/** 日号十位："0"…"3"（和纸版式大日期前小数字） */
export function dayTens(date: Date): string {
  return `${Math.floor(date.getDate() / 10)}`;
}

/** 日号个位："0"…"9"（和纸版式大日期后大数字） */
export function dayOnes(date: Date): string {
  return `${date.getDate() % 10}`;
}
