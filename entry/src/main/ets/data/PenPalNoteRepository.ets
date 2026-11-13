/**
 * 笔友手记表的读写（U01 B3，R-NOTEBOOK-01/02；表 pen_pal_note，库 v4 加）。
 * 对应 iOS SwiftData `PenPalNote` 的自动持久化。
 *
 * - kind 原样存取字符串（备份包可能带未来版本的新值，寄信 / 应用改法时按 recent）
 * - saveNote 是 upsert（与 LetterRepository.saveLetter 同款）：回执改写已有条、
 *   新建条共用一个入口
 * - 🔴 用户看不到也删不了手记（R-NOTEBOOK-02 隐形）：没有全清、没有单删的 UI 入口；
 *   deleteNotes 只被回执改法（合并大事、清理重复画像）调用
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PenPalNote } from '../models/PenPalNote';

const DOMAIN = 0x0000;
const TAG = 'PenPalNoteRepository';

const NOTE_COLUMNS: string[] = [
  'id', 'pen_pal_id', 'text', 'kind', 'noted_at', 'created_at', 'updated_at'
];

/** 结果集行 → PenPalNote（库列蛇形 → 模型驼峰；updated_at 可空判 null 再取） */
function rowToNote(result: relationalStore.ResultSet): PenPalNote {
  const note = new PenPalNote(
    result.getString(result.getColumnIndex('pen_pal_id')),
    result.getString(result.getColumnIndex('text')),
    result.getLong(result.getColumnIndex('noted_at'))
  );
  note.id = result.getString(result.getColumnIndex('id'));
  note.kind = result.getString(result.getColumnIndex('kind'));
  note.createdAtMs = result.getLong(result.getColumnIndex('created_at'));
  if (!result.isColumnNull(result.getColumnIndex('updated_at'))) {
    note.updatedAtMs = result.getLong(result.getColumnIndex('updated_at'));
  }
  return note;
}

/** PenPalNote → 列值（插入 / 更新共用）。updated_at undefined → null */
export function noteToValues(note: PenPalNote): relationalStore.ValuesBucket {
  return {
    'id': note.id,
    'pen_pal_id': note.penPalID,
    'text': note.text,
    'kind': note.kind,
    'noted_at': note.notedAtMs,
    'created_at': note.createdAtMs,
    'updated_at': note.updatedAtMs ?? null
  };
}

export class PenPalNoteRepository {
  /** 全量手记（备份导出用；一个用户几十条，全量不心疼） */
  static async listNotes(store: relationalStore.RdbStore): Promise<PenPalNote[]> {
    let result: relationalStore.ResultSet;
    try {
      result = await store.querySql(
        `SELECT ${NOTE_COLUMNS.join(', ')} FROM pen_pal_note ORDER BY noted_at ASC`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'query notes failed: %{public}s', JSON.stringify(err));
      throw new Error('PenPalNoteRepository.listNotes: 查询失败');
    }
    const notes: PenPalNote[] = [];
    try {
      while (result.goToNextRow()) {
        notes.push(rowToNote(result));
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read note rows failed: %{public}s', JSON.stringify(err));
      throw new Error('PenPalNoteRepository.listNotes: 读行失败');
    } finally {
      try {
        result.close();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'close resultSet failed: %{public}s', JSON.stringify(err));
      }
    }
    return notes;
  }

  /** 这位笔友的一本（寄信随带、回执改法用）。世界笔友传他的 id，own 传 PenPalNote.ownID */
  static async listForPenPal(store: relationalStore.RdbStore,
    penPalID: string): Promise<PenPalNote[]> {
    const predicates = new relationalStore.RdbPredicates('pen_pal_note');
    predicates.equalTo('pen_pal_id', penPalID);
    predicates.orderByAsc('noted_at');
    try {
      const result = await store.query(predicates, NOTE_COLUMNS);
      const notes: PenPalNote[] = [];
      try {
        while (result.goToNextRow()) {
          notes.push(rowToNote(result));
        }
      } finally {
        try {
          result.close();
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'close resultSet failed: %{public}s', JSON.stringify(err));
        }
      }
      return notes;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'query notes failed penPal=%{public}s: %{public}s',
        penPalID, JSON.stringify(err));
      throw new Error('PenPalNoteRepository.listForPenPal: 查询失败');
    }
  }

  /** 存一条：已有（同 id）就地更新，没有才插入（回执改写 + 新建共用） */
  static async saveNote(store: relationalStore.RdbStore, note: PenPalNote): Promise<void> {
    const values = noteToValues(note);
    try {
      const predicates = new relationalStore.RdbPredicates('pen_pal_note');
      predicates.equalTo('id', note.id);
      const updated = await store.update(values, predicates);
      if (updated > 0) {
        return;
      }
      await store.insert('pen_pal_note', values);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'save note failed id=%{public}s: %{public}s',
        note.id, JSON.stringify(err));
      throw new Error('PenPalNoteRepository.saveNote: 保存失败');
    }
  }

  /** 按一批 id 删（回执合并大事、清理重复画像）。id 批空直接返回 */
  static async deleteNotes(store: relationalStore.RdbStore, ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    try {
      const predicates = new relationalStore.RdbPredicates('pen_pal_note');
      predicates.in('id', ids);
      await store.delete(predicates);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'delete notes failed: %{public}s', JSON.stringify(err));
      throw new Error('PenPalNoteRepository.deleteNotes: 删除失败');
    }
  }
}
