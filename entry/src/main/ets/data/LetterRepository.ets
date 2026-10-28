/**
 * 信件表的读写（10_BUILD_MANUAL.md 5.1）。对应 iOS SwiftData `Letter` 的自动持久化。
 *
 * - 全量查回（generated_at 倒序，对齐 iOS @Query），「已到达 / 在路上」过滤
 *   与按到达时刻排序由调用方用 LetterDelivery 在内存里做（两端判定逐字一致，05 §6.1）
 * - saveLetter 是 upsert：调试插信（LetterDebug 页）与标已读（打开即已读，R-BOX-04）共用
 * - status / triggerKind 原样存取字符串，不过枚举（05 §6：导入时可能有不认识的值）
 * - 信永久保留、无删信入口（R-BOX-09）；deleteAllLetters 仅供调试页清场
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Letter } from '../models/Letter';

const DOMAIN = 0x0000;
const TAG = 'LetterRepository';

const LETTER_COLUMNS: string[] = [
  'id', 'status', 'body', 'from_character', 'to_name', 'stationery', 'trigger_kind',
  'error_message', 'generated_at', 'delivered_at', 'read_at', 'updated_at'
];

/** 结果集行 → Letter（库列蛇形 → 模型驼峰；可空列判 null 再取） */
function rowToLetter(result: relationalStore.ResultSet): Letter {
  const letter = new Letter(
    result.getString(result.getColumnIndex('id')),
    result.getLong(result.getColumnIndex('generated_at')),
    result.getLong(result.getColumnIndex('updated_at'))
  );
  letter.status = result.getString(result.getColumnIndex('status'));
  letter.body = result.getString(result.getColumnIndex('body'));
  letter.fromCharacter = result.getString(result.getColumnIndex('from_character'));
  if (!result.isColumnNull(result.getColumnIndex('to_name'))) {
    letter.toName = result.getString(result.getColumnIndex('to_name'));
  }
  if (!result.isColumnNull(result.getColumnIndex('stationery'))) {
    letter.stationery = result.getString(result.getColumnIndex('stationery'));
  }
  letter.triggerKind = result.getString(result.getColumnIndex('trigger_kind'));
  if (!result.isColumnNull(result.getColumnIndex('error_message'))) {
    letter.errorMessage = result.getString(result.getColumnIndex('error_message'));
  }
  if (!result.isColumnNull(result.getColumnIndex('delivered_at'))) {
    letter.deliveredAt = result.getLong(result.getColumnIndex('delivered_at'));
  }
  if (!result.isColumnNull(result.getColumnIndex('read_at'))) {
    letter.readAt = result.getLong(result.getColumnIndex('read_at'));
  }
  return letter;
}

/** Letter → 列值（插入 / 更新共用）。可空字段 undefined → null */
export function letterToValues(letter: Letter): relationalStore.ValuesBucket {
  return {
    'id': letter.id,
    'status': letter.status,
    'body': letter.body,
    'from_character': letter.fromCharacter,
    'to_name': letter.toName ?? null,
    'stationery': letter.stationery ?? null,
    'trigger_kind': letter.triggerKind,
    'error_message': letter.errorMessage ?? null,
    'generated_at': letter.generatedAt,
    'delivered_at': letter.deliveredAt ?? null,
    'read_at': letter.readAt ?? null,
    'updated_at': letter.updatedAt
  };
}

export class LetterRepository {
  /** 全量信件（generated_at 倒序）。「已到达」过滤、到达排序交给调用方（R-BOX-01） */
  static async listLetters(store: relationalStore.RdbStore): Promise<Letter[]> {
    let result: relationalStore.ResultSet;
    try {
      result = await store.querySql(
        `SELECT ${LETTER_COLUMNS.join(', ')} FROM letter ORDER BY generated_at DESC`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'query letters failed: %{public}s', JSON.stringify(err));
      throw new Error('LetterRepository.listLetters: 查询失败');
    }
    const letters: Letter[] = [];
    try {
      while (result.goToNextRow()) {
        letters.push(rowToLetter(result));
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read letter rows failed: %{public}s', JSON.stringify(err));
      throw new Error('LetterRepository.listLetters: 读行失败');
    } finally {
      try {
        result.close();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'close resultSet failed: %{public}s', JSON.stringify(err));
      }
    }
    return letters;
  }

  /** 按 id 取一封（读信页路由参数 → 信）。没有返回 null */
  static async findLetter(store: relationalStore.RdbStore, id: string): Promise<Letter | null> {
    const predicates = new relationalStore.RdbPredicates('letter');
    predicates.equalTo('id', id);
    try {
      const result = await store.query(predicates, LETTER_COLUMNS);
      let letter: Letter | null = null;
      try {
        if (result.goToNextRow()) {
          letter = rowToLetter(result);
        }
      } finally {
        try {
          result.close();
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'close resultSet failed: %{public}s', JSON.stringify(err));
        }
      }
      return letter;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'query letter failed id=%{public}s: %{public}s', id, JSON.stringify(err));
      throw new Error('LetterRepository.findLetter: 查询失败');
    }
  }

  /** 存信：已有（同 id）就地更新，没有才插入 —— 调试插信、标已读共用 */
  static async saveLetter(store: relationalStore.RdbStore, letter: Letter): Promise<void> {
    const values = letterToValues(letter);
    try {
      const predicates = new relationalStore.RdbPredicates('letter');
      predicates.equalTo('id', letter.id);
      const updated = await store.update(values, predicates);
      if (updated > 0) {
        return;
      }
      await store.insert('letter', values);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'save letter failed id=%{public}s: %{public}s', letter.id, JSON.stringify(err));
      throw new Error('LetterRepository.saveLetter: 保存失败');
    }
  }

  /** 清空信件表（仅调试页清场用；产品内信永久保留，R-BOX-09） */
  static async deleteAllLetters(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.executeSql('DELETE FROM letter');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'delete letters failed: %{public}s', JSON.stringify(err));
      throw new Error('LetterRepository.deleteAllLetters: 清空失败');
    }
  }

  /** 这几封信各自关联的日记 id 并集（letter_entry 关联表，多对多）。
   *  邮筒页拿退回信关联的日记，让它们不重新出现在候选里（R-POST-03） */
  static async entryIdsForLetters(store: relationalStore.RdbStore,
    letterIds: string[]): Promise<Set<string>> {
    const ids = new Set<string>();
    if (letterIds.length === 0) {
      return ids;
    }
    const predicates = new relationalStore.RdbPredicates('letter_entry');
    predicates.in('letter_id', letterIds);
    try {
      const result = await store.query(predicates, ['entry_id']);
      try {
        while (result.goToNextRow()) {
          ids.add(result.getString(result.getColumnIndex('entry_id')));
        }
      } finally {
        try {
          result.close();
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'close resultSet failed: %{public}s', JSON.stringify(err));
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'query letter_entry failed: %{public}s', JSON.stringify(err));
      throw new Error('LetterRepository.entryIdsForLetters: 查询失败');
    }
    return ids;
  }

  /** 投信那一刻写关联：这封信勾上的日记（R-POST-07；已存在的关联跳过不重插） */
  static async linkLetterEntries(store: relationalStore.RdbStore,
    letterId: string, entryIds: string[]): Promise<void> {
    for (const entryId of entryIds) {
      try {
        const values: relationalStore.ValuesBucket = {
          'letter_id': letterId,
          'entry_id': entryId
        };
        await store.insert('letter_entry', values);
      } catch (err) {
        // 已有同对关联（PRIMARY KEY 冲突）不算错；真插不进去只损失关联，信照寄
        hilog.warn(DOMAIN, TAG, 'link letter_entry failed letter=%{public}s entry=%{public}s: %{public}s',
          letterId, entryId, JSON.stringify(err));
      }
    }
  }

  /** 不寄了：清掉这封信的日记关联（R-POST-11，日记回到「要寄的日记」候选里） */
  static async clearLetterEntries(store: relationalStore.RdbStore,
    letterId: string): Promise<void> {
    try {
      const predicates = new relationalStore.RdbPredicates('letter_entry');
      predicates.equalTo('letter_id', letterId);
      await store.delete(predicates);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'clear letter_entry failed letter=%{public}s: %{public}s',
        letterId, JSON.stringify(err));
      throw new Error('LetterRepository.clearLetterEntries: 清空失败');
    }
  }
}
