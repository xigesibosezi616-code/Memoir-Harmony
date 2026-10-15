/**
 * 心情表的读取（10_BUILD_MANUAL.md 2.1）。对应 iOS `MoodSelector` 的
 * `@Query(sort: \MoodTag.sortOrder)`。心情纯预设、不可增删改（R-ENTRY-09），
 * 这里只有读；建表写入见 `DefaultData.ets`。
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MoodTag } from '../models/Mood';

const DOMAIN = 0x0000;
const TAG = 'MoodRepository';

export class MoodRepository {
  /** 全部心情，按 sortOrder 升序（12 个预设的固定顺序） */
  static async fetchAllMoods(store: relationalStore.RdbStore): Promise<MoodTag[]> {
    let result: relationalStore.ResultSet;
    try {
      result = await store.querySql(
        `SELECT id, name, color_hex, is_default, sort_order, created_at, icon_name
         FROM mood ORDER BY sort_order ASC`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'query moods failed: %{public}s', JSON.stringify(err));
      throw new Error('MoodRepository.fetchAllMoods: 查询失败');
    }
    const moods: MoodTag[] = [];
    try {
      while (result.goToNextRow()) {
        const mood = new MoodTag(
          result.getString(result.getColumnIndex('id')),
          result.getString(result.getColumnIndex('name')),
          result.getString(result.getColumnIndex('color_hex')),
          result.getLong(result.getColumnIndex('created_at'))
        );
        mood.isDefault = result.getLong(result.getColumnIndex('is_default')) === 1;
        mood.sortOrder = result.getLong(result.getColumnIndex('sort_order'));
        if (!result.isColumnNull(result.getColumnIndex('icon_name'))) {
          mood.iconName = result.getString(result.getColumnIndex('icon_name'));
        }
        moods.push(mood);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read mood rows failed: %{public}s', JSON.stringify(err));
      throw new Error('MoodRepository.fetchAllMoods: 读行失败');
    } finally {
      try {
        result.close();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'close resultSet failed: %{public}s', JSON.stringify(err));
      }
    }
    return moods;
  }
}
