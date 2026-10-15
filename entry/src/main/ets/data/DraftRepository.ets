/**
 * 草稿表的读写（10_BUILD_MANUAL.md 2.1）。对应 iOS `Models/DraftEntry.swift` 的
 * `current(in:)` / `discardCurrent(in:)` 与 SwiftData 的自动持久化。
 *
 * - 草稿全局只留一份：读时取 `updated_at` 最新的一条，多余旧记录顺手删掉
 *   （R-ENTRY-04；v1 草稿没有媒体，旧记录清理不涉及文件）
 * - 「不保存」丢弃 = 先删媒体（调用方调 MediaStorageService.deleteDraftMedia）再删记录；
 *   转正 = **只删记录，绝不删媒体**（R-ENTRY-03，新日记接着用）
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DraftEntry, PlaceMode } from '../models/Draft';
import { parseStringArray } from './ColumnCodec';

const DOMAIN = 0x0000;
const TAG = 'DraftRepository';

const DRAFT_COLUMNS: string[] = [
  'id', 'title', 'content_blocks', 'mood', 'mood_color_hex', 'tags', 'audio_urls',
  'weather_code', 'weather_info', 'location_info', 'place_mode', 'manual_place_name',
  'created_at', 'updated_at'
];

/** 结果集行 → DraftEntry */
function rowToDraft(result: relationalStore.ResultSet): DraftEntry {
  const draft = new DraftEntry(
    result.getString(result.getColumnIndex('id')),
    result.getLong(result.getColumnIndex('created_at')),
    result.getLong(result.getColumnIndex('updated_at'))
  );
  draft.title = result.getString(result.getColumnIndex('title'));
  if (!result.isColumnNull(result.getColumnIndex('content_blocks'))) {
    draft.contentBlocksData = result.getString(result.getColumnIndex('content_blocks'));
  }
  draft.mood = result.getString(result.getColumnIndex('mood'));
  if (!result.isColumnNull(result.getColumnIndex('mood_color_hex'))) {
    draft.moodColorHex = result.getString(result.getColumnIndex('mood_color_hex'));
  }
  draft.tags = parseStringArray(
    result.isColumnNull(result.getColumnIndex('tags')) ? null : result.getString(result.getColumnIndex('tags')));
  draft.audioURLs = parseStringArray(
    result.isColumnNull(result.getColumnIndex('audio_urls')) ? null : result.getString(result.getColumnIndex('audio_urls')));
  if (!result.isColumnNull(result.getColumnIndex('weather_code'))) {
    draft.weatherCode = result.getString(result.getColumnIndex('weather_code'));
  }
  if (!result.isColumnNull(result.getColumnIndex('weather_info'))) {
    draft.weatherInfo = result.getString(result.getColumnIndex('weather_info'));
  }
  if (!result.isColumnNull(result.getColumnIndex('location_info'))) {
    draft.locationInfo = result.getString(result.getColumnIndex('location_info'));
  }
  if (!result.isColumnNull(result.getColumnIndex('place_mode'))) {
    draft.placeMode = result.getString(result.getColumnIndex('place_mode'));
  } else {
    draft.placeMode = PlaceMode.Auto;
  }
  if (!result.isColumnNull(result.getColumnIndex('manual_place_name'))) {
    draft.manualPlaceName = result.getString(result.getColumnIndex('manual_place_name'));
  }
  return draft;
}

/** DraftEntry → 列值（insert / update 共用） */
function draftToValues(draft: DraftEntry): relationalStore.ValuesBucket {
  return {
    'id': draft.id,
    'title': draft.title,
    'content_blocks': draft.contentBlocksData ?? null,
    'mood': draft.mood,
    'mood_color_hex': draft.moodColorHex ?? null,
    'tags': JSON.stringify(draft.tags),
    'audio_urls': JSON.stringify(draft.audioURLs),
    'weather_code': draft.weatherCode ?? null,
    'weather_info': draft.weatherInfo ?? null,
    'location_info': draft.locationInfo ?? null,
    'place_mode': draft.placeMode,
    'manual_place_name': draft.manualPlaceName ?? null,
    'created_at': draft.createdAt,
    'updated_at': draft.updatedAt
  };
}

export class DraftRepository {
  /**
   * 取当前草稿（约定只有一份；真出现多条就取 `updated_at` 最新的，
   * 其余旧记录顺手删掉，R-ENTRY-04）。没有草稿返回 null。
   */
  static async loadCurrentDraft(store: relationalStore.RdbStore): Promise<DraftEntry | null> {
    let result: relationalStore.ResultSet;
    try {
      result = await store.querySql(
        `SELECT ${DRAFT_COLUMNS.join(', ')} FROM draft ORDER BY updated_at DESC LIMIT 10`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'query drafts failed: %{public}s', JSON.stringify(err));
      throw new Error('DraftRepository.loadCurrentDraft: 查询失败');
    }
    const drafts: DraftEntry[] = [];
    try {
      while (result.goToNextRow()) {
        drafts.push(rowToDraft(result));
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read draft rows failed: %{public}s', JSON.stringify(err));
      throw new Error('DraftRepository.loadCurrentDraft: 读行失败');
    } finally {
      try {
        result.close();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'close resultSet failed: %{public}s', JSON.stringify(err));
      }
    }
    if (drafts.length === 0) {
      return null;
    }
    // 多余的旧草稿直接删记录（v1 草稿无媒体；有媒体的版本须先清各自媒体再删）
    for (let i = 1; i < drafts.length; i++) {
      await DraftRepository.deleteDraftRecord(store, drafts[i].id);
      hilog.warn(DOMAIN, TAG, 'removed stale draft %{public}s', drafts[i].id);
    }
    return drafts[0];
  }

  /** 存草稿：已有（同 id）就地更新，没有才插入 —— 保证全局只有一份 */
  static async saveDraft(store: relationalStore.RdbStore, draft: DraftEntry): Promise<void> {
    const values = draftToValues(draft);
    try {
      const predicates = new relationalStore.RdbPredicates('draft');
      predicates.equalTo('id', draft.id);
      const updated = await store.update(values, predicates);
      if (updated > 0) {
        return;
      }
      await store.insert('draft', values);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'save draft failed: %{public}s', JSON.stringify(err));
      throw new Error('DraftRepository.saveDraft: 保存失败');
    }
  }

  /** 只删草稿记录。转正用它（媒体留给新日记）；「不保存」先删媒体再用它 */
  static async deleteDraftRecord(store: relationalStore.RdbStore, id: string): Promise<void> {
    try {
      const predicates = new relationalStore.RdbPredicates('draft');
      predicates.equalTo('id', id);
      await store.delete(predicates);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'delete draft failed id=%{public}s: %{public}s', id, JSON.stringify(err));
      throw new Error('DraftRepository.deleteDraftRecord: 删除失败');
    }
  }
}
