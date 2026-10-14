/**
 * 首启默认数据（10_BUILD_MANUAL.md 1.5，R-APP-07）。
 * 对应 iOS `ContentView.swift` 的 `insertDefaultMoodTagsIfNeeded` /
 * `ensureAllDefaultMoodsExist` / `ensureDefaultTagsExist` 三件事。
 *
 * - 12 个默认心情：空库全量插入；非空库按 key 补缺（新版本加预设时老用户也补上），
 *   补的接在现有最大 sortOrder 后面。**以库为准，不信本机标记** ——
 *   换机迁移 / 云同步恢复出来的库可能已经有数据
 * - 4 本默认日记本：只有库里一本都没有时建（默认色酒红，与 iOS `Tag.swift`
 *   声明处默认一致）。用户删光后重启**不会重建** —— 数据以用户为准
 * - 🔴 不铺任何示例日记 / 示例来信（R-APP-07）
 *
 * 触发时机对齐 iOS：主界面首次构建时（引导走完之后），而不是同意页 ——
 * 用户没同意就写库，等于「处理个人信息先于同意」（R-APP-01）。
 * 落库失败只记日志：下次启动重试，不拦主界面。
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MoodTag, defaultMoodTags } from '../models/Mood';
import { Notebook, DEFAULT_NOTEBOOK_NAMES } from '../models/Notebook';
import { generateUuid } from '../models/Uuid';
import { AppDatabase } from './Database';

/**
 * 缺失的默认心情（纯函数）。
 * 空库 → 全部 12 个（preset 顺序即 sortOrder）；非空库 → 按 name 补缺
 * （只与 isDefault 的行比，用户自建的同名心情不挡补齐），sortOrder 接现有最大值递增。
 */
export function moodsToEnsure(existingMoods: MoodTag[], makeId: () => string, now: number): MoodTag[] {
  const defaults: MoodTag[] = defaultMoodTags(makeId, now);
  if (existingMoods.length === 0) {
    return defaults;
  }
  const defaultNamesInDb: Set<string> = new Set<string>();
  let maxSortOrder: number = -1;
  for (const mood of existingMoods) {
    if (mood.isDefault) {
      defaultNamesInDb.add(mood.name);
    }
    if (mood.sortOrder > maxSortOrder) {
      maxSortOrder = mood.sortOrder;
    }
  }
  const missing: MoodTag[] = [];
  for (const preset of defaults) {
    if (!defaultNamesInDb.has(preset.name)) {
      preset.sortOrder = maxSortOrder + 1;
      maxSortOrder = preset.sortOrder;
      missing.push(preset);
    }
  }
  return missing;
}

/**
 * 要建的默认日记本（纯函数）。库非空 → 一本不建（用户删光不重建）；
 * 空库 → 4 本（生活 / 读书笔记 / 旅行 / 工作），sortOrder 0–3，
 * 颜色走 Notebook 声明处默认（酒红，与 iOS `Tag()` 一致）。
 */
export function notebooksToEnsure(existingCount: number, makeId: () => string, now: number): Notebook[] {
  if (existingCount > 0) {
    return [];
  }
  const created: Notebook[] = [];
  for (let i = 0; i < DEFAULT_NOTEBOOK_NAMES.length; i++) {
    const notebook: Notebook = new Notebook(makeId(), DEFAULT_NOTEBOOK_NAMES[i], now, now);
    notebook.sortOrder = i;
    created.push(notebook);
  }
  return created;
}

/** 默认数据服务：读库 → 纯函数算缺口 → 落库。幂等，主界面每次构建调一次 */
export class DefaultDataService {
  /** 补齐默认数据（内部先确保库已打开）。失败抛错，调用方 catch 记日志即可 */
  static async ensureDefaultData(context: common.Context): Promise<void> {
    const store: relationalStore.RdbStore = await AppDatabase.open(context);
    const now: number = Date.now();

    const existingMoods: MoodTag[] = await DefaultDataService.fetchAllMoods(store);
    const missingMoods: MoodTag[] = moodsToEnsure(existingMoods, generateUuid, now);
    for (const mood of missingMoods) {
      await DefaultDataService.insertMood(store, mood);
    }

    const notebookCount: number = await DefaultDataService.countNotebooks(store);
    const newNotebooks: Notebook[] = notebooksToEnsure(notebookCount, generateUuid, now);
    for (const notebook of newNotebooks) {
      await DefaultDataService.insertNotebook(store, notebook);
    }

    if (missingMoods.length > 0 || newNotebooks.length > 0) {
      hilog.info(0x0000, 'DefaultData', 'ensured: moods=%{public}d notebooks=%{public}d',
        missingMoods.length, newNotebooks.length);
    }
  }

  private static async fetchAllMoods(store: relationalStore.RdbStore): Promise<MoodTag[]> {
    const predicates = new relationalStore.RdbPredicates('mood');
    predicates.orderByAsc('sort_order');
    let result: relationalStore.ResultSet;
    try {
      result = await store.query(predicates,
        ['id', 'name', 'color_hex', 'is_default', 'sort_order', 'created_at', 'icon_name']);
    } catch (err) {
      hilog.error(0x0000, 'DefaultData', 'query moods failed: %{public}s', JSON.stringify(err));
      throw new Error('DefaultData.queryMoods failed');
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
        const iconIndex = result.getColumnIndex('icon_name');
        if (!result.isColumnNull(iconIndex)) {
          mood.iconName = result.getString(iconIndex);
        }
        moods.push(mood);
      }
    } catch (err) {
      hilog.error(0x0000, 'DefaultData', 'read mood rows failed: %{public}s', JSON.stringify(err));
      throw new Error('DefaultData.readMoods failed');
    } finally {
      try {
        result.close();
      } catch (err) {
        // 关闭失败只记日志：结果集随 GC 回收，不往上抛
        hilog.warn(0x0000, 'DefaultData', 'close mood resultSet failed: %{public}s', JSON.stringify(err));
      }
    }
    return moods;
  }

  private static async insertMood(store: relationalStore.RdbStore, mood: MoodTag): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'id': mood.id,
      'name': mood.name,
      'color_hex': mood.colorHex,
      'is_default': mood.isDefault ? 1 : 0,
      'sort_order': mood.sortOrder,
      'created_at': mood.createdAt,
      'icon_name': mood.iconName ?? null
    };
    try {
      await store.insert('mood', values);
    } catch (err) {
      hilog.error(0x0000, 'DefaultData', 'insert mood failed name=%{public}s: %{public}s',
        mood.name, JSON.stringify(err));
      throw new Error(`DefaultData.insertMood failed: ${mood.name}`);
    }
  }

  private static async countNotebooks(store: relationalStore.RdbStore): Promise<number> {
    let result: relationalStore.ResultSet;
    try {
      result = await store.querySql('SELECT COUNT(*) AS cnt FROM notebook');
    } catch (err) {
      hilog.error(0x0000, 'DefaultData', 'count notebooks failed: %{public}s', JSON.stringify(err));
      throw new Error('DefaultData.countNotebooks failed');
    }
    try {
      return result.goToNextRow() ? result.getLong(result.getColumnIndex('cnt')) : 0;
    } catch (err) {
      hilog.error(0x0000, 'DefaultData', 'read notebook count failed: %{public}s', JSON.stringify(err));
      throw new Error('DefaultData.readNotebookCount failed');
    } finally {
      try {
        result.close();
      } catch (err) {
        hilog.warn(0x0000, 'DefaultData', 'close count resultSet failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  private static async insertNotebook(store: relationalStore.RdbStore, notebook: Notebook): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'id': notebook.id,
      'name': notebook.name,
      'color_id': notebook.colorId,
      'texture_id': notebook.textureId,
      'last_opened_at': notebook.lastOpenedAt,
      'created_at': notebook.createdAt,
      'sort_order': notebook.sortOrder,
      'cover_photo_filename': notebook.coverPhotoFilename ?? null,
      'cover_layout_id': notebook.coverLayoutId ?? null,
      'subtitle': notebook.subtitle ?? null
    };
    try {
      await store.insert('notebook', values);
    } catch (err) {
      hilog.error(0x0000, 'DefaultData', 'insert notebook failed name=%{public}s: %{public}s',
        notebook.name, JSON.stringify(err));
      throw new Error(`DefaultData.insertNotebook failed: ${notebook.name}`);
    }
  }
}
