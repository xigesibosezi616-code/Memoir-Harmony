/**
 * 一次性迁移框架单测（10_BUILD_MANUAL.md 1.5）。
 * 对应 iOS `MemoirApp.swift` 的 `TagMigrationRunner`（标记 key 守卫 + 幂等重跑）。
 *
 * 任务表当前为空（v1 库没有历史包袱，iOS 的两个迁移是它自己版本演进攒出来的），
 * 这里测框架本身的纯函数：标记 key 拼接（`didMigrate_<key>`）、
 * 待跑任务的筛选（保序、跳过已置位）。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  MigrationTask,
  migrationPrefKey,
  pendingMigrationKeys,
  allMigrationTasks
} from '../../main/ets/services/MigrationRunner';

function noopRun(): (context: Context) => Promise<void> {
  return (_context: Context): Promise<void> => {
    return Promise.resolve();
  };
}

export default function migrationRunnerTest() {
  describe('MigrationRunnerTest', () => {
    it('prefKeyPrefixesDidMigrate', 0, () => {
      expect(migrationPrefKey('LinenOnly')).assertEqual('didMigrate_LinenOnly');
      expect(migrationPrefKey('V21Colors')).assertEqual('didMigrate_V21Colors');
    })

    it('pendingKeysKeepTaskOrderAndSkipDone', 0, () => {
      const tasks = [
        new MigrationTask('first', noopRun()),
        new MigrationTask('second', noopRun()),
        new MigrationTask('third', noopRun())
      ];
      const done = new Set<string>(['second']);
      expect(pendingMigrationKeys(tasks, done).join(',')).assertEqual('first,third');
    })

    it('emptyDoneSetKeepsAllTasksInOrder', 0, () => {
      const tasks = [
        new MigrationTask('a', noopRun()),
        new MigrationTask('b', noopRun())
      ];
      expect(pendingMigrationKeys(tasks, new Set<string>()).join(',')).assertEqual('a,b');
    })

    it('allDoneYieldsNoPendingKeys', 0, () => {
      const tasks = [new MigrationTask('only', noopRun())];
      const done = new Set<string>(['only']);
      expect(pendingMigrationKeys(tasks, done).length).assertEqual(0);
    })

    it('noTasksYieldNoPendingKeys', 0, () => {
      expect(pendingMigrationKeys([], new Set<string>()).length).assertEqual(0);
    })

    it('taskTableCurrentlyEmptyForV1', 0, () => {
      // v1 无历史包袱。DATABASE_VERSION 升版、下架数据清理这类活来了
      // 往 allMigrationTasks 里加；⚠️ 给任务 run 加新逻辑要换新 key
      expect(allMigrationTasks().length).assertEqual(0);
    })
  })
}
