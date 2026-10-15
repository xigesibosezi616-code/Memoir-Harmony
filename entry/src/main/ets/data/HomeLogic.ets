/**
 * 记录页列表模式的纯逻辑（10_BUILD_MANUAL.md 2.2）。对应 iOS `HomeView` 的
 * `monthRecordDays` / `groupedEntries` 计算属性。
 *
 * 全部做成「数据进、数据出」的纯函数（时间参数可注入，CLAUDE.md 调试方法约定），
 * 单测跑穿多天 / 多月 / 跨年；UI 层只管渲染。
 */
import { JournalEntry } from '../models/JournalEntry';
import { yearMonthKey } from '../services/AppDateFormatters';

/** 一个年月分组（组头 key 本地化由调用方传 appLanguage） */
export class EntryGroup {
  readonly key: string;
  readonly entries: JournalEntry[];

  constructor(key: string, entries: JournalEntry[]) {
    this.key = key;
    this.entries = entries;
  }
}

/**
 * 主页重查信号（AppStorage）：RDB 没有观察机制，用显式 tick 补齐 iOS
 * `@Query` 的自动响应。Index 页面（@Entry）`onPageShow` 时 +1 ——
 * 路由返回（保存日记回来）、冷启动、后台回前台都会触发；
 * 此时页面可见，重查后 @State 赋值立即渲染。
 * 🔴 不能在写入侧（ComposeView 保存时）bump：主页此时被全屏页盖住，
 * @Watch 里赋的 @State 不会触发重渲染（2026-10-15 真机实测），
 * 回来还是旧列表；必须等页面重新可见再查。
 */
export const STORAGE_KEY_HOME_RELOAD_TICK = 'homeReloadTick';

/** 本月记录天数（R-HOME-01）：entries 里落在 now 同年同月的**不同日**数 */
export function monthRecordDays(entries: JournalEntry[], now: Date): number {
  const year = now.getFullYear();
  const month = now.getMonth();
  const days = new Set<number>();
  for (const entry of entries) {
    const date = new Date(entry.date);
    if (date.getFullYear() === year && date.getMonth() === month) {
      days.add(date.getDate());
    }
  }
  return days.size;
}

/**
 * 按年月分组（R-HOME-02 列表模式）：最近月在最前、组内倒序。
 * 前置条件：entries 已按 date 倒序（fetchAllEntries ORDER BY date DESC）——
 * 同月必相邻，一趟线性扫描即可；iOS 的 `Dictionary(grouping:)` + 按
 * 首篇日期排序在结果上与此一致（排序键相同）。
 */
export function groupedEntries(entries: JournalEntry[], appLanguage: string): EntryGroup[] {
  const groups: EntryGroup[] = [];
  let current: EntryGroup | undefined = undefined;
  for (const entry of entries) {
    const key = yearMonthKey(new Date(entry.date), appLanguage);
    if (current === undefined || current.key !== key) {
      current = new EntryGroup(key, []);
      groups.push(current);
    }
    current.entries.push(entry);
  }
  return groups;
}
