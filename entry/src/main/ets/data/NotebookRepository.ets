/**
 * 日记本表的读写（10_BUILD_MANUAL.md 2.1）。对应 iOS `TagSelector` 里的
 * `@Query(sort: [sortOrder, createdAt])` 与 `createAndSelect()`。
 *
 * - 「收进日记本」按书架顺序列出全部日记本（sortOrder 升序，同序按创建时间）
 * - 当场新建：撞名（忽略大小写 / 全半角）直接选中已有那本，不另建（R-ENTRY-10）
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookColor, BookTexture, CoverLayout, Notebook, cleanedName, isNameTaken } from '../models/Notebook';
import { SortOrderChange } from '../models/ShelfDrag';
import { encodeStringArray, parseStringArray } from './ColumnCodec';

const DOMAIN = 0x0000;
const TAG = 'NotebookRepository';

/** 重命名结果（iOS `Tag.RenameResult`，三态同义） */
export enum NotebookRenameResult {
  /** 改了（日记的 tags 已连带改） */
  Renamed = 'Renamed',
  /** 空名字或和原来一样——什么都没做 */
  Unchanged = 'Unchanged',
  /** 和别的日记本撞名 */
  NameTaken = 'NameTaken'
}

/** 书架篇数统计：各日记本名下篇数 + 总篇数（iOS `entryCountsByTag` + `entries.count`） */
export class ShelfEntryCounts {
  /** key = 日记本名（tags 里存的名字），value = 篇数 */
  readonly byName: Record<string, number>;
  /** 全部日记篇数（= 日记总数） */
  readonly total: number;

  constructor(byName: Record<string, number>, total: number) {
    this.byName = byName;
    this.total = total;
  }

  /** 指定日记本名的篇数；没有挂日记的返回 0 */
  countFor(name: string): number {
    const value = this.byName[name];
    return value !== undefined ? value : 0;
  }
}

/**
 * 按日记本名字汇总篇数（纯函数）。一篇日记最多属于一本（R-BOOK-01），
 * 但容错按多本计：tags 里出现过的名字各 +1（与 iOS `entryCountsByTag` 一致）。
 */
export function countNotebookUsage(entryTags: string[][]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const tags of entryTags) {
    for (const name of tags) {
      counts[name] = (counts[name] !== undefined ? counts[name] : 0) + 1;
    }
  }
  return counts;
}

export class NotebookRepository {
  /** 全部日记本，按书架顺序（与书架同一个顺序，见 iOS `BookshelfView`） */
  static async fetchAllNotebooks(store: relationalStore.RdbStore): Promise<Notebook[]> {
    let result: relationalStore.ResultSet;
    try {
      result = await store.querySql(
        `SELECT id, name, color_id, texture_id, last_opened_at, created_at, sort_order,
          cover_photo_filename, cover_layout_id, subtitle
         FROM notebook ORDER BY sort_order ASC, created_at ASC`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'query notebooks failed: %{public}s', JSON.stringify(err));
      throw new Error('NotebookRepository.fetchAllNotebooks: 查询失败');
    }
    const notebooks: Notebook[] = [];
    try {
      while (result.goToNextRow()) {
        const notebook = new Notebook(
          result.getString(result.getColumnIndex('id')),
          result.getString(result.getColumnIndex('name')),
          result.getLong(result.getColumnIndex('created_at')),
          result.getLong(result.getColumnIndex('last_opened_at'))
        );
        notebook.colorId = result.getString(result.getColumnIndex('color_id'));
        const texture = result.getString(result.getColumnIndex('texture_id'));
        notebook.textureId = texture.length > 0 ? texture : BookTexture.Linen;
        notebook.sortOrder = result.getLong(result.getColumnIndex('sort_order'));
        if (!result.isColumnNull(result.getColumnIndex('cover_photo_filename'))) {
          notebook.coverPhotoFilename = result.getString(result.getColumnIndex('cover_photo_filename'));
        }
        if (!result.isColumnNull(result.getColumnIndex('cover_layout_id'))) {
          notebook.coverLayoutId = result.getString(result.getColumnIndex('cover_layout_id'));
        }
        if (!result.isColumnNull(result.getColumnIndex('subtitle'))) {
          notebook.subtitle = result.getString(result.getColumnIndex('subtitle'));
        }
        notebooks.push(notebook);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read notebook rows failed: %{public}s', JSON.stringify(err));
      throw new Error('NotebookRepository.fetchAllNotebooks: 读行失败');
    } finally {
      try {
        result.close();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'close resultSet failed: %{public}s', JSON.stringify(err));
      }
    }
    return notebooks;
  }

  /** 新建日记本。失败抛错，调用方走 errors 提示 */
  static async insertNotebook(store: relationalStore.RdbStore, notebook: Notebook): Promise<void> {
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
      hilog.error(DOMAIN, TAG, 'insert notebook failed name=%{public}s: %{public}s',
        notebook.name, JSON.stringify(err));
      throw new Error('NotebookRepository.insertNotebook: 插入失败');
    }
  }

  /**
   * 编辑封面落库（10_BUILD_MANUAL.md 3.4，R-BOOK-13/15/16 的库端）：
   * 颜色 / 照片文件名 / 版式 / 副标题一次写回；照片换掉或移除时
   * cover_photo_filename 置 null（旧文件删除由调用方做，云端副本等 Q3）。
   * 失败抛错，调用方走 errors 提示。
   */
  static async updateCover(store: relationalStore.RdbStore, notebookId: string,
    color: BookColor, coverPhotoFilename: string | undefined,
    coverLayout: CoverLayout | undefined, subtitle: string | undefined): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'color_id': color,
      'cover_photo_filename': coverPhotoFilename ?? null,
      'cover_layout_id': coverLayout ?? null,
      'subtitle': subtitle ?? null
    };
    try {
      const predicates = new relationalStore.RdbPredicates('notebook')
        .equalTo('id', notebookId);
      await store.update(values, predicates);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'update cover failed id=%{public}s: %{public}s',
        notebookId, JSON.stringify(err));
      throw new Error('NotebookRepository.updateCover: 更新失败');
    }
  }

  /**
   * 书架篇数统计：一次查全部日记的 tags 汇总（书可能很多，
   * 不许每画一本书都把全部日记过滤一遍——iOS 同款优化）。
   * 只查 tags 列，不整行加载。
   */
  static async fetchShelfEntryCounts(store: relationalStore.RdbStore): Promise<ShelfEntryCounts> {
    let result: relationalStore.ResultSet;
    try {
      result = await store.querySql('SELECT tags FROM journal_entry');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'query entry tags failed: %{public}s', JSON.stringify(err));
      throw new Error('NotebookRepository.fetchShelfEntryCounts: 查询失败');
    }
    const entryTags: string[][] = [];
    try {
      while (result.goToNextRow()) {
        // tags 列 NOT NULL DEFAULT '[]'，直接读
        entryTags.push(parseStringArray(result.getString(result.getColumnIndex('tags'))));
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read entry tags failed: %{public}s', JSON.stringify(err));
      throw new Error('NotebookRepository.fetchShelfEntryCounts: 读行失败');
    } finally {
      try {
        result.close();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'close resultSet failed: %{public}s', JSON.stringify(err));
      }
    }
    return new ShelfEntryCounts(countNotebookUsage(entryTags), entryTags.length);
  }

  /**
   * 书架拖动换位落库（10_BUILD_MANUAL.md 3.2）：只写变了的那几条 sortOrder
   * （新值 0, 1, 2…，iOS `saveOrder`）。失败抛错，调用方走 errors 提示 + 重查回滚。
   */
  static async updateSortOrders(store: relationalStore.RdbStore,
    changes: SortOrderChange[]): Promise<void> {
    for (const change of changes) {
      try {
        await store.executeSql('UPDATE notebook SET sort_order = ? WHERE id = ?',
          [change.sortOrder, change.id]);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'update sort order failed id=%{public}s: %{public}s',
          change.id, JSON.stringify(err));
        throw new Error('NotebookRepository.updateSortOrders: 更新失败');
      }
    }
  }

  /**
   * 重命名（10_BUILD_MANUAL.md 3.3，iOS `Tag.rename`）：名字就是身份，
   * 改名必须把挂在这本上的日记（journal_entry.tags 里的旧名）一起改过去，
   * 否则日记会从这本里「掉」出来。判重键 nameKey（忽略大小写 / 全半角）。
   * 只改 journal_entry，不碰草稿表（iOS rename 也只 fetch JournalEntry）。
   * 成功后同步改入参 notebook.name（调用方在页面上继续用它渲染）。
   */
  static async renameNotebook(store: relationalStore.RdbStore, notebook: Notebook,
    rawNewName: string, otherNames: string[]): Promise<NotebookRenameResult> {
    const newName = cleanedName(rawNewName);
    if (newName.length === 0 || newName === notebook.name) {
      return NotebookRenameResult.Unchanged;
    }
    if (isNameTaken(newName, otherNames)) {
      return NotebookRenameResult.NameTaken;
    }
    const oldName = notebook.name;
    // 1. 挂在这本上的日记：tags 里的旧名换新名（一篇一篇 UPDATE，量级 = 本内篇数）
    let result: relationalStore.ResultSet;
    try {
      result = await store.querySql('SELECT id, tags FROM journal_entry');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'rename: query entry tags failed: %{public}s', JSON.stringify(err));
      throw new Error('NotebookRepository.renameNotebook: 查询失败');
    }
    const updates: string[][] = []; // [id, 新 tags JSON]
    try {
      while (result.goToNextRow()) {
        const tags = parseStringArray(result.getString(result.getColumnIndex('tags')));
        if (!tags.includes(oldName)) {
          continue;
        }
        const replaced: string[] = [];
        for (const tag of tags) {
          replaced.push(tag === oldName ? newName : tag);
        }
        updates.push([result.getString(result.getColumnIndex('id')), encodeStringArray(replaced)]);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'rename: read entry tags failed: %{public}s', JSON.stringify(err));
      throw new Error('NotebookRepository.renameNotebook: 读行失败');
    } finally {
      try {
        result.close();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'close resultSet failed: %{public}s', JSON.stringify(err));
      }
    }
    try {
      for (const update of updates) {
        await store.executeSql('UPDATE journal_entry SET tags = ? WHERE id = ?',
          [update[1], update[0]]);
      }
      // 2. 本子改名
      await store.executeSql('UPDATE notebook SET name = ? WHERE id = ?',
        [newName, notebook.id]);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'rename notebook failed %{public}s→%{public}s: %{public}s',
        oldName, newName, JSON.stringify(err));
      throw new Error('NotebookRepository.renameNotebook: 更新失败');
    }
    notebook.name = newName;
    return NotebookRenameResult.Renamed;
  }

  /**
   * 删日记本（R-BOOK-08）：只删本子记录，**不删日记**。
   * 日记 tags 里的名字字符串原样保留（与 iOS `context.delete(tag)` 一致：
   * 删的是 Tag 记录，JournalEntry.tags 是独立存的字符串数组）——
   * 同名新建一本时那些日记会按「名字就是身份」重新归入。
   * 照片封面文件由调用方经 MediaStorageService 删（R-BOOK-16 的本地部分）。
   */
  static async deleteNotebook(store: relationalStore.RdbStore, notebookId: string): Promise<void> {
    try {
      await store.executeSql('DELETE FROM notebook WHERE id = ?', [notebookId]);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'delete notebook failed id=%{public}s: %{public}s',
        notebookId, JSON.stringify(err));
      throw new Error('NotebookRepository.deleteNotebook: 删除失败');
    }
  }

  /** 每次进这本的日记列表刷新 lastOpenedAt（iOS BookDetailView.onAppear；「全部日记」无本，不调） */
  static async touchLastOpenedAt(store: relationalStore.RdbStore,
    notebookId: string, now: number): Promise<void> {
    try {
      await store.executeSql('UPDATE notebook SET last_opened_at = ? WHERE id = ?',
        [now, notebookId]);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'touch lastOpenedAt failed id=%{public}s: %{public}s',
        notebookId, JSON.stringify(err));
      // 只是埋点性质的字段，失败不挡页面
    }
  }
}
