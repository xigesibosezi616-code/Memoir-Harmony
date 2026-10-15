/**
 * 日记本表的读写（10_BUILD_MANUAL.md 2.1）。对应 iOS `TagSelector` 里的
 * `@Query(sort: [sortOrder, createdAt])` 与 `createAndSelect()`。
 *
 * - 「收进日记本」按书架顺序列出全部日记本（sortOrder 升序，同序按创建时间）
 * - 当场新建：撞名（忽略大小写 / 全半角）直接选中已有那本，不另建（R-ENTRY-10）
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookTexture, Notebook } from '../models/Notebook';

const DOMAIN = 0x0000;
const TAG = 'NotebookRepository';

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
}
