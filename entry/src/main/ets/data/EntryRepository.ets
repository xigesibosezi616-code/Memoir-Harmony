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

  /**
   * 全部日记，date 倒序（10_BUILD_MANUAL.md 2.2 记录页列表；对应 iOS
   * `@Query(sort: \JournalEntry.date, order: .reverse)`）。
   * 记录页分组、本月天数都在这份数据上算；详情 / 搜索后续卡片各自再补。
   */
  static async fetchAllEntries(store: relationalStore.RdbStore): Promise<JournalEntry[]> {
    let result: relationalStore.ResultSet;
    try {
      result = await store.querySql(
        `SELECT id, title, content, date, mood, mood_color_hex, tags, is_favorite, word_count,
          created_at, updated_at, audio_urls, weather_code, weather_info, location_info, content_blocks
         FROM journal_entry ORDER BY date DESC, created_at DESC`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'query entries failed: %{public}s', JSON.stringify(err));
      throw new Error('EntryRepository.fetchAllEntries: 查询失败');
    }
    const entries: JournalEntry[] = [];
    try {
      while (result.goToNextRow()) {
        entries.push(EntryRepository.rowToEntry(result));
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read entry rows failed: %{public}s', JSON.stringify(err));
      throw new Error('EntryRepository.fetchAllEntries: 读行失败');
    } finally {
      try {
        result.close();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'close resultSet failed: %{public}s', JSON.stringify(err));
      }
    }
    return entries;
  }

  /** 单篇日记（详情页）。查无（已被并发删除等）返回 null */
  static async fetchEntryById(store: relationalStore.RdbStore, id: string): Promise<JournalEntry | null> {
    let result: relationalStore.ResultSet;
    try {
      result = await store.querySql(
        `SELECT id, title, content, date, mood, mood_color_hex, tags, is_favorite, word_count,
          created_at, updated_at, audio_urls, weather_code, weather_info, location_info, content_blocks
         FROM journal_entry WHERE id = ?`, [id]);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'query entry failed id=%{public}s: %{public}s', id, JSON.stringify(err));
      throw new Error('EntryRepository.fetchEntryById: 查询失败');
    }
    try {
      if (result.goToNextRow()) {
        return EntryRepository.rowToEntry(result);
      }
      return null;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read entry row failed id=%{public}s: %{public}s', id, JSON.stringify(err));
      throw new Error('EntryRepository.fetchEntryById: 读行失败');
    } finally {
      try {
        result.close();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'close resultSet failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  /**
   * 编辑后整篇写回（10_BUILD_MANUAL.md 2.4）。全字段覆盖：调用方先在
   * JournalEntry 上改好（内容必须经 setContentBlocks，它会同步派生
   * content / wordCount / audioURLs / updatedAt，R-RICH-10），这里只落库。
   */
  static async updateEntry(store: relationalStore.RdbStore, entry: JournalEntry): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'title': entry.title,
      'content': entry.content,
      'mood': entry.mood,
      'mood_color_hex': entry.moodColorHex ?? null,
      'tags': JSON.stringify(entry.tags),
      'word_count': entry.wordCount,
      'updated_at': entry.updatedAt,
      'audio_urls': JSON.stringify(entry.audioURLs),
      'weather_code': entry.weatherCode ?? null,
      'weather_info': entry.weatherInfo ?? null,
      'location_info': entry.locationInfo ?? null,
      'content_blocks': entry.contentBlocksData ?? null
    };
    const predicates = new relationalStore.RdbPredicates('journal_entry');
    predicates.equalTo('id', entry.id);
    try {
      // API 12 形态：表名在 RdbPredicates 里，返回受影响行数
      const changed = await store.update(values, predicates);
      if (changed === 0) {
        // 并发删除等：一行都没动，按失败处理（调用方提示「保存失败」）
        throw new Error('EntryRepository.updateEntry: 目标不存在');
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'update entry failed id=%{public}s: %{public}s', entry.id, JSON.stringify(err));
      throw new Error('EntryRepository.updateEntry: 更新失败');
    }
  }

  /**
   * 删一篇日记的库记录（详情页，R-ENTRY-16）。媒体清理在调用方先做
   * （`deleteEntryMedia`，05 §2 的顺序：先文件后记录）。
   */
  static async deleteEntry(store: relationalStore.RdbStore, id: string): Promise<void> {
    try {
      await store.executeSql('DELETE FROM journal_entry WHERE id = ?', [id]);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'delete entry failed id=%{public}s: %{public}s', id, JSON.stringify(err));
      throw new Error('EntryRepository.deleteEntry: 删除失败');
    }
  }

  /** 行 → JournalEntry（日期毫秒用 getLong；可空列先 isColumnNull 再取） */
  private static rowToEntry(row: relationalStore.ResultSet): JournalEntry {
    const entry = new JournalEntry(
      row.getString(row.getColumnIndex('id')),
      row.getLong(row.getColumnIndex('date')),
      row.getLong(row.getColumnIndex('created_at')),
      row.getLong(row.getColumnIndex('updated_at'))
    );
    entry.title = row.getString(row.getColumnIndex('title'));
    entry.content = row.getString(row.getColumnIndex('content'));
    entry.mood = row.getString(row.getColumnIndex('mood'));
    if (!row.isColumnNull(row.getColumnIndex('mood_color_hex'))) {
      entry.moodColorHex = row.getString(row.getColumnIndex('mood_color_hex'));
    }
    const tagsRaw = row.getString(row.getColumnIndex('tags'));
    entry.tags = EntryRepository.decodeStringArray(tagsRaw);
    entry.isFavorite = row.getLong(row.getColumnIndex('is_favorite')) === 1;
    entry.wordCount = row.getLong(row.getColumnIndex('word_count'));
    entry.audioURLs = EntryRepository.decodeStringArray(row.getString(row.getColumnIndex('audio_urls')));
    if (!row.isColumnNull(row.getColumnIndex('weather_code'))) {
      entry.weatherCode = row.getString(row.getColumnIndex('weather_code'));
    }
    if (!row.isColumnNull(row.getColumnIndex('weather_info'))) {
      entry.weatherInfo = row.getString(row.getColumnIndex('weather_info'));
    }
    if (!row.isColumnNull(row.getColumnIndex('location_info'))) {
      entry.locationInfo = row.getString(row.getColumnIndex('location_info'));
    }
    if (!row.isColumnNull(row.getColumnIndex('content_blocks'))) {
      entry.contentBlocksData = row.getString(row.getColumnIndex('content_blocks'));
    }
    return entry;
  }

  /** JSON 字符串数组容错解码（空 / 坏数据 → 空数组） */
  private static decodeStringArray(raw: string): string[] {
    if (raw.length === 0) {
      return [];
    }
    try {
      // 单次断言到具体类型；坏数据（非数组 / 坏 JSON）由 catch 兜底成空数组
      const parsed: Object[] = JSON.parse(raw) as Object[];
      const items: string[] = [];
      for (const item of parsed) {
        if (typeof item === 'string') {
          items.push(item);
        }
      }
      return items;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'decode string array failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }
}
