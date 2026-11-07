/**
 * 最长连续写作（U16；对应 iOS `Services/WritingStreak.swift`）。
 * 2026-10-28 用户定，取代原来的「连续写作」（从今天往回数、一断就归零）。
 *
 * 规则（U16 照抄）：
 * - **连续** = 按日历（设备时区）连着的日子里，每天至少写了一篇
 * - **最长** = 「记下的」和「现在这些日记里最长的那一段」取大的，**只升不降**：
 *   连着写了 30 天就是 30，断了还是 30，直到哪天新的一段写到 31 天才变；删了日记也不往下掉
 * - 记在本机偏好（`writingStats.bestStreakDays`，AppPrefs 读写），**跟备份包导出**；
 *   导入时取「本机」和「包里」大的那个（6.4 / 6.5 接）
 * - 什么时候记：打开写作统计、导出、导入时各算一次（6.3 只做「打开写作统计」）
 */

/** 一天的毫秒数（本地日历天，不用夏令时安全减法——起点都是当天 0 点再 +1 天构造） */
const DAY_MS = 86400000;

export class WritingStreak {
  /**
   * 这些日子里最长的一段连续天数（同一天写几篇算一天）。
   * datesMs 是日记的 date 毫秒；内部按本地 0 点去重排序。
   */
  static longestRun(datesMs: number[]): number {
    const days = new Set<number>();
    for (const ms of datesMs) {
      const d = new Date(ms);
      days.add(new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime());
    }
    const sorted = Array.from(days).sort((a, b) => a - b);
    let best = 0;
    let run = 0;
    let previous: number | null = null;
    for (const day of sorted) {
      if (previous !== null && day - previous === DAY_MS) {
        run += 1;
      } else {
        run = 1;
      }
      best = Math.max(best, run);
      previous = day;
    }
    return best;
  }

  /**
   * 显示用：记下的和算出来的取大的（不写入，界面里随便调）。
   * 没记过、也没写过 → 0
   */
  static best(recordedDays: number, datesMs: number[]): number {
    return Math.max(recordedDays, WritingStreak.longestRun(datesMs));
  }

  /** 只升不降：比记下的大才返回新值，否则返回记下的（调用方据此决定写不写） */
  static raisedValue(recordedDays: number, days: number): number {
    return days > recordedDays ? days : recordedDays;
  }
}
