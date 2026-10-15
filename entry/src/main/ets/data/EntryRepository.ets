/**
 * 日记表的写入（10_BUILD_MANUAL.md 2.1）。对应 iOS SwiftData 的 `modelContext.insert`。
 * 读（列表 / 详情 / 搜索）在 2.2 / 2.3 各自的仓储里补，本卡只有「建一篇」。
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { JournalEntry } from '../models/JournalEntry';

const DOMAIN = 0x0000;
const TAG = 'EntryRepository';

export class EntryRepository {
  /** 建一篇日记（点 ✓ 那一刻）。失败抛错，调用方走 errors 提示 */
  static async insertEntry(store: relationalStore.RdbStore, entry: JournalEntry): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'id': entry.id,
      'title': entry.title,
      'content': entry.content,
      'date': entry.date,
      'mood': entry.mood,
      'mood_color_hex': entry.moodColorHex ?? null,
      'tags': JSON.stringify(entry.tags),
      'is_favorite': entry.isFavorite ? 1 : 0,
      'word_count': entry.wordCount,
      'created_at': entry.createdAt,
      'updated_at': entry.updatedAt,
      'audio_urls': JSON.stringify(entry.audioURLs),
      'weather_code': entry.weatherCode ?? null,
      'weather_info': entry.weatherInfo ?? null,
      'location_info': entry.locationInfo ?? null,
      'content_blocks': entry.contentBlocksData ?? null
    };
    try {
      await store.insert('journal_entry', values);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'insert entry failed id=%{public}s: %{public}s', entry.id, JSON.stringify(err));
      throw new Error('EntryRepository.insertEntry: 插入失败');
    }
  }
}
