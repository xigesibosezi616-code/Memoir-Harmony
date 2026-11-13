/**
 * 笔友手记纯函数单测（U01 B3；docs/harmony-updates/U01_world_penpals.md R-NOTEBOOK-03/04）。
 *
 * - snapshot：画像在前 + 大事按 touched 升序取尾部 recentLimit 条；不认识 kind 当大事；
 *   date = updatedAtMs ?? notedAtMs；没有手记带空数组
 * - apply：画像有则改最新删重复、无则新建；remove 优先于 update；update 只认本位
 *   recent 的 id（画像 / 别的 id 对上不动）；add 新建（notedAtMs = atMs）
 * - 空 edits（null / isEmpty）由调用方挡，这里只测 isEmpty 分支
 */
import { describe, it, expect } from '@ohos/hypium';
import { PenPalNote, PenPalNoteKind } from '../../main/ets/models/PenPalNote';
import { PenPalNotebook, NotebookApplyPlan } from '../../main/ets/models/PenPalNotebook';
import { NotebookEdits, NotebookItem, NotebookRewrite } from '../../main/ets/models/Api';

/** 造一条手记：id / kind / 可选 updatedAt 直接覆写（仓库 rowToNote 同款构造后覆写） */
function makeNote(id: string, text: string, kind: string, notedAt: number,
  updatedAt?: number): PenPalNote {
  const note = new PenPalNote('aki', text, notedAt);
  note.id = id;
  note.kind = kind;
  if (updatedAt !== undefined) {
    note.updatedAtMs = updatedAt;
  }
  return note;
}

export default function penPalNotebookTest() {
  describe('PenPalNotebookTest', () => {
    // ---- snapshot（寄信带哪几条；R-NOTEBOOK-03） ----

    it('snapshotPutsProfileFirstThenRecentsSortedAsc', 0, () => {
      const notes = [
        makeNote('R1', '面试', PenPalNoteKind.Recent, 300),
        makeNote('P1', '画像', PenPalNoteKind.Profile, 100),
        makeNote('R2', '搬家', PenPalNoteKind.Recent, 200)
      ];
      const items = PenPalNotebook.snapshot(notes);
      expect(items.length).assertEqual(3);
      expect(items[0].id).assertEqual('P1');
      expect(items[0].kind).assertEqual('profile');
      expect(items[1].id).assertEqual('R2'); // 大事按记下时刻升序
      expect(items[2].id).assertEqual('R1');
      expect(items[1].dateMs).assertEqual(200);
      expect(items[2].dateMs).assertEqual(300);
    })

    it('snapshotKeepsLatestProfileWhenDuplicated', 0, () => {
      const notes = [
        makeNote('P1', '旧画像', PenPalNoteKind.Profile, 100),
        makeNote('P2', '新画像', PenPalNoteKind.Profile, 500)
      ];
      const items = PenPalNotebook.snapshot(notes);
      expect(items.length).assertEqual(1);
      expect(items[0].id).assertEqual('P2');
      expect(items[0].text).assertEqual('新画像');
    })

    it('snapshotUsesUpdatedAtWhenPresent', 0, () => {
      // date = updatedAtMs ?? notedAtMs；改过的按改写时刻排
      const notes = [
        makeNote('R1', '旧事新写', PenPalNoteKind.Recent, 100, 900),
        makeNote('R2', '没改过的', PenPalNoteKind.Recent, 400)
      ];
      const items = PenPalNotebook.snapshot(notes);
      expect(items[0].id).assertEqual('R2');
      expect(items[0].dateMs).assertEqual(400);
      expect(items[1].id).assertEqual('R1');
      expect(items[1].dateMs).assertEqual(900);
    })

    it('snapshotTakesLastRecentLimit', 0, () => {
      // 大事超过 recentLimit 只带最近的；画像不计入限额
      const notes: PenPalNote[] = [
        makeNote('P1', '画像', PenPalNoteKind.Profile, 0)
      ];
      for (let i = 0; i < PenPalNote.recentLimit + 2; i++) {
        notes.push(makeNote(`R${i}`, `大事${i}`, PenPalNoteKind.Recent, i + 1));
      }
      const items = PenPalNotebook.snapshot(notes);
      expect(items.length).assertEqual(PenPalNote.recentLimit + 1);
      expect(items[0].id).assertEqual('P1');
      // 最旧的两条被挤掉
      expect(items[1].id).assertEqual('R2');
      expect(items[items.length - 1].id).assertEqual(`R${PenPalNote.recentLimit + 1}`);
    })

    it('snapshotTreatsUnknownKindAsRecent', 0, () => {
      // 不认识的 kind（更新版本加的）原样保留、按大事带
      const notes = [
        makeNote('X1', '未来种类', 'mood_summary', 100),
        makeNote('P1', '画像', PenPalNoteKind.Profile, 50)
      ];
      const items = PenPalNotebook.snapshot(notes);
      expect(items.length).assertEqual(2);
      expect(items[0].id).assertEqual('P1');
      expect(items[1].id).assertEqual('X1');
      expect(items[1].kind).assertEqual('recent'); // 线格式归一成 recent
    })

    it('snapshotReturnsEmptyWhenNoNotes', 0, () => {
      const items = PenPalNotebook.snapshot([]);
      expect(items instanceof Array).assertTrue();
      expect(items.length).assertEqual(0);
    })

    // ---- apply（回执落到这本上；R-NOTEBOOK-04） ----

    it('applyReturnsEmptyPlanForEmptyEdits', 0, () => {
      const notes = [makeNote('R1', '大事', PenPalNoteKind.Recent, 100)];
      const plan = PenPalNotebook.apply(notes, 'aki',
        new NotebookEdits(undefined, [], [], []), 900);
      expect(plan.toUpsert.length).assertEqual(0);
      expect(plan.toDeleteIds.length).assertEqual(0);
      expect(notes[0].text).assertEqual('大事'); // 原样没动
    })

    it('applyRewritesLatestProfileAndDeletesDuplicates', 0, () => {
      const notes = [
        makeNote('P1', '旧画像', PenPalNoteKind.Profile, 100),
        makeNote('P2', '新画像', PenPalNoteKind.Profile, 500)
      ];
      const plan = PenPalNotebook.apply(notes, 'aki',
        new NotebookEdits('改写后的画像', [], [], []), 900);
      expect(plan.toUpsert.length).assertEqual(1);
      expect(plan.toUpsert[0].id).assertEqual('P2'); // 改最新那份（就地改）
      expect(plan.toUpsert[0].text).assertEqual('改写后的画像');
      expect(plan.toUpsert[0].updatedAtMs).assertEqual(900);
      expect(plan.toDeleteIds.length).assertEqual(1);
      expect(plan.toDeleteIds[0]).assertEqual('P1'); // 重复画像删掉
    })

    it('applyCreatesProfileWhenMissing', 0, () => {
      const notes = [makeNote('R1', '大事', PenPalNoteKind.Recent, 100)];
      const plan = PenPalNotebook.apply(notes, 'aki',
        new NotebookEdits('新建的画像', [], [], []), 900);
      expect(plan.toUpsert.length).assertEqual(1);
      const created = plan.toUpsert[0];
      expect(created.kind).assertEqual('profile');
      expect(created.penPalID).assertEqual('aki');
      expect(created.text).assertEqual('新建的画像');
      expect(created.notedAtMs).assertEqual(900);
      expect(plan.toDeleteIds.length).assertEqual(0);
    })

    it('applyRemovesBeforeUpdate', 0, () => {
      // 同一条又 remove 又 update：以删为准
      const notes = [
        makeNote('R1', '要删的', PenPalNoteKind.Recent, 100),
        makeNote('R2', '要改的', PenPalNoteKind.Recent, 200)
      ];
      const plan = PenPalNotebook.apply(notes, 'aki',
        new NotebookEdits(undefined, [], [new NotebookRewrite('R1', '改过的')], ['R1']), 900);
      expect(plan.toDeleteIds.length).assertEqual(1);
      expect(plan.toDeleteIds[0]).assertEqual('R1');
      expect(plan.toUpsert.length).assertEqual(0); // R1 的 update 被跳过
      expect(notes[0].text).assertEqual('要删的'); // 没被 update 改到
    })

    it('applyUpdatesRecentById', 0, () => {
      const notes = [
        makeNote('R1', '原来的', PenPalNoteKind.Recent, 100),
        makeNote('P1', '画像', PenPalNoteKind.Profile, 50)
      ];
      const plan = PenPalNotebook.apply(notes, 'aki',
        new NotebookEdits(undefined, [], [new NotebookRewrite('R1', '改写后的大事')], []), 900);
      expect(plan.toUpsert.length).assertEqual(1);
      expect(plan.toUpsert[0].id).assertEqual('R1');
      expect(plan.toUpsert[0].text).assertEqual('改写后的大事');
      expect(plan.toUpsert[0].updatedAtMs).assertEqual(900);
      expect(notes[0].text).assertEqual('改写后的大事'); // 就地改
      expect(plan.toDeleteIds.length).assertEqual(0);
    })

    it('applyIgnoresIdsOutsideThisRecentSet', 0, () => {
      // update / remove 只认这一位最近大事的 id：
      // 画像的 id、不存在的 id、别的笔友的 id 对上都不动
      const notes = [
        makeNote('R1', '大事', PenPalNoteKind.Recent, 100),
        makeNote('P1', '画像', PenPalNoteKind.Profile, 50)
      ];
      const plan = PenPalNotebook.apply(notes, 'aki',
        new NotebookEdits(undefined, [],
          [new NotebookRewrite('P1', '想改画像'), new NotebookRewrite('NOPE', '不存在的')],
          ['P1', 'NOPE']), 900);
      expect(plan.toUpsert.length).assertEqual(0);
      expect(plan.toDeleteIds.length).assertEqual(0);
      expect(notes[1].text).assertEqual('画像'); // 画像没被当成大事改掉
    })

    it('applyAddsNewRecentNotes', 0, () => {
      const plan = PenPalNotebook.apply([], 'aki',
        new NotebookEdits(undefined, ['第一件', '第二件'], [], []), 900);
      expect(plan.toUpsert.length).assertEqual(2);
      expect(plan.toDeleteIds.length).assertEqual(0);
      const first = plan.toUpsert[0];
      expect(first.text).assertEqual('第一件');
      expect(first.penPalID).assertEqual('aki');
      expect(first.kind).assertEqual('recent');
      expect(first.notedAtMs).assertEqual(900); // 记下时刻 = 回执的写信时刻
      expect(plan.toUpsert[1].text).assertEqual('第二件');
    })
  })
}
