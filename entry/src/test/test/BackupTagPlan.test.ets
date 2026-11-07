/**
 * 同名日记本改写计划单测（6.4；08_backup_package.md §4.4、iOS `planTagNames`）。
 *
 * 合并 / 分开的区别全在名字改写：Merge 把包里的名字并到本机同名本上，
 * KeepSeparate 起一个没人用过的新名。「同名」按 nameKey 比，且要两边都挂着
 * 日记才打扰用户——空本子合并不混任何东西，重导同一个包全跳过。
 */
import { describe, it, expect } from '@ohos/hypium';
import { Notebook } from '../../main/ets/models/Notebook';
import { JournalEntry } from '../../main/ets/models/JournalEntry';
import { BackupEntryDto } from '../../main/ets/services/backup/BackupFormat';
import { TagConflictPolicy, planTagNames }
  from '../../main/ets/services/backup/BackupImportService';

function makeLocalEntry(id: string, tags: string[]): JournalEntry {
  const entry = new JournalEntry(id, 1000, 1000, 1000);
  entry.tags = tags;
  return entry;
}

function makeIncoming(id: string, tags: string[]): BackupEntryDto {
  const dto = new BackupEntryDto();
  dto.id = id;
  dto.tags = tags;
  return dto;
}

export default function backupTagPlanTest() {
  describe('BackupTagPlanTest', () => {
    // 两边都挂着日记的同名本：要问用户，合并 = 改写到本机写法
    it('mergePolicyRewritesIncomingToLocalName', 0, () => {
      const plan = planTagNames(
        [makeIncoming('X1', ['travel'])],
        ['travel'],
        [new Notebook('N1', 'Travel', 10, 10)],
        [makeLocalEntry('E1', ['Travel'])],
        TagConflictPolicy.Merge);
      expect(plan.conflicts.length).assertEqual(1);
      expect(plan.conflicts[0]).assertEqual('travel');
      expect(plan.rename.get('travel') === 'Travel').assertTrue();
    })

    // 分开 = 起一个没人用过的新名（包里的写法 + 序号）
    it('keepSeparatePolicyAppendsNumber', 0, () => {
      const plan = planTagNames(
        [makeIncoming('X1', ['travel'])],
        ['travel'],
        [new Notebook('N1', 'Travel', 10, 10)],
        [makeLocalEntry('E1', ['Travel'])],
        TagConflictPolicy.KeepSeparate);
      expect(plan.conflicts.length).assertEqual(1);
      expect(plan.rename.get('travel') === 'travel 2').assertTrue();
    })

    // 本机同名本是空本子：合并不会混任何东西，不必打扰用户
    it('emptyLocalNotebookDoesNotConflict', 0, () => {
      const plan = planTagNames(
        [makeIncoming('X1', ['travel'])],
        ['travel'],
        [new Notebook('N1', 'Travel', 10, 10)],
        [],
        TagConflictPolicy.Merge);
      expect(plan.conflicts.length).assertEqual(0);
      expect(plan.rename.get('travel') === 'Travel').assertTrue();
    })

    // 重导同一个包：日记 id 全部已存在，全会跳过 → 不算冲突
    it('reImportedPackageSkipsConflicts', 0, () => {
      const plan = planTagNames(
        [makeIncoming('X1', ['Travel'])],
        ['travel'],
        [new Notebook('N1', 'Travel', 10, 10)],
        [makeLocalEntry('X1', ['Travel'])],
        TagConflictPolicy.Merge);
      expect(plan.conflicts.length).assertEqual(0);
    })

    // 同时挂几本的日记按单本规则会退回「全部日记」，不进任何一本 → 不算冲突
    it('multiNotebookIncomingEntryDoesNotConflict', 0, () => {
      const plan = planTagNames(
        [makeIncoming('X1', ['travel', 'trip'])],
        ['travel'],
        [new Notebook('N1', 'Travel', 10, 10)],
        [makeLocalEntry('E1', ['Travel'])],
        TagConflictPolicy.Merge);
      expect(plan.conflicts.length).assertEqual(0);
    })

    // 本机没有的名字原样用，不改写也不冲突
    it('unseenIncomingNameKeptAsIs', 0, () => {
      const plan = planTagNames(
        [makeIncoming('X1', ['trip'])],
        ['trip'],
        [new Notebook('N1', 'Travel', 10, 10)],
        [],
        TagConflictPolicy.Merge);
      expect(plan.conflicts.length).assertEqual(0);
      expect(plan.rename.get('trip') === 'trip').assertTrue();
    })

    // 包里同时有「Travel」「travel」两种写法：并成第一次见到的那种
    it('caseVariantsInsidePackageCollapseToOneName', 0, () => {
      const plan = planTagNames(
        [makeIncoming('X1', ['travel'])],
        ['Travel'],
        [],
        [],
        TagConflictPolicy.Merge);
      expect(plan.conflicts.length).assertEqual(0);
      expect(plan.rename.get('Travel') === 'Travel').assertTrue();
      expect(plan.rename.get('travel') === 'Travel').assertTrue();
    })
  })
}
