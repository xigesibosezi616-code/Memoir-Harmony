/**
 * 一次性数据迁移框架（10_BUILD_MANUAL.md 1.5）。
 * 对应 iOS `MemoirApp.swift` 的 `TagMigrationRunner`（隐藏触发器 + `@AppStorage`
 * 守卫保证幂等，每个迁移各用各的标记 key）。
 *
 * 框架化：每个迁移 = `MigrationTask`（key + run）。
 * - key 的偏好标记（`didMigrate_<key>`）**只在成功后置位**，下次启动直接跳过；
 *   run 抛错 = 没成功：不置位，下次启动重试，也不拦其他任务
 * - ⚠️ **给某个任务的 run 加了新逻辑就要换新 key**，否则老用户早已置位，
 *   新加的那步永远不会执行（iOS 同款警告：封面迁移 key 从 V21Colors 换到 LinenOnly）
 * - 迁移函数本身要写成幂等的，重跑一次是安全（iOS 同约定）
 * - 🔴 **当前任务表为空**：v1 库没有历史包袱，iOS 的两个迁移
 *   （12 色收敛、单本整理）是它自己版本演进攒出来的，不是鸿蒙版的起点。
 *   框架先立着，DATABASE_VERSION 升版、下架色清理这类活来了往表里加
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPrefs } from './AppPrefs';

/** 一个一次性迁移：key（标记名）+ run（幂等，抛错 = 未完成，下次重试） */
export class MigrationTask {
  readonly key: string;
  readonly run: (context: common.Context) => Promise<void>;

  constructor(key: string, run: (context: common.Context) => Promise<void>) {
    this.key = key;
    this.run = run;
  }
}

/** 迁移标记在偏好里的完整 key：`didMigrate_<key>` */
export function migrationPrefKey(taskKey: string): string {
  return `didMigrate_${taskKey}`;
}

/** 还没成功跑过的任务 key（纯函数，单测覆盖）。保持任务表顺序 */
export function pendingMigrationKeys(tasks: MigrationTask[], doneKeys: Set<string>): string[] {
  const pending: string[] = [];
  for (const task of tasks) {
    if (!doneKeys.has(task.key)) {
      pending.push(task.key);
    }
  }
  return pending;
}

/**
 * 全部迁移任务（当前为空，见文件头说明）。
 * 加任务时在这里按执行顺序追加，run 的第一个参数就是启动上下文。
 */
export function allMigrationTasks(): MigrationTask[] {
  const tasks: MigrationTask[] = [];
  return tasks;
}

/** 启动时跑一次：逐个执行未完成任务，成功一个置位一个 */
export class MigrationRunner {
  static async runPendingMigrations(context: common.Context): Promise<void> {
    const tasks: MigrationTask[] = allMigrationTasks();
    if (tasks.length === 0) {
      return;
    }
    for (const task of tasks) {
      const prefKey = migrationPrefKey(task.key);
      if (AppPrefs.getBool(prefKey, false)) {
        continue;
      }
      try {
        await task.run(context);
        AppPrefs.putBool(prefKey, true);
      } catch (err) {
        // 不置位：下次启动重试；也不拦后面的任务
        hilog.error(0x0000, 'MigrationRunner', 'migration %{public}s failed: %{public}s',
          task.key, JSON.stringify(err));
      }
    }
  }
}
