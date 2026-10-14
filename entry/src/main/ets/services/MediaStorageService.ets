/**
 * 媒体存储服务壳：接 RDB 的入口（10_BUILD_MANUAL.md 1.4）。对应 iOS
 * `Services/MediaStorage.swift`（@MainActor enum MediaStorage）+ `DraftEntry.deleteAssociatedMedia`。
 *
 * 纯逻辑（引用表、对账、安全闸、清理）都在 `MediaStorage.ets`，可单测；
 * 这里只做三件事：①从库里读日记 / 草稿 / 封面喂给纯函数 ②调文件系统执行 ③删完文件清图片缓存。
 *
 * 与 iOS 的差异：iOS 的云端副本（MediaAsset / CloudKit）鸿蒙侧不做（云同步阻塞 Q3），
 * R-DATA-07 的「连云端副本一起删」等云同步方案落地后再接。
 *
 * 调用约定：
 * - 删**日记**：先 `deleteEntryMedia`（照片三件套 + 录音）再删库里的记录（05 §2 的顺序）。
 *   来信不随日记删除（信里的关联置空即可，见 05 §2）
 * - 删**草稿**：转正时**绝不能调** `deleteDraftMedia`——那些文件正要被新日记接着用；
 *   只在「不保存」丢弃草稿时调（R-ENTRY-03）
 * - 换 / 移除 / 删日记本封面时调 `deleteCoverFile`（R-BOOK-16 的本地文件部分）
 * - 「清理残留文件」入口调 `reclaimOrphans`；显示占用调 `usage`（R-DATA-08 显示「照片与录音占用」）
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { JournalEntry } from '../models/JournalEntry';
import { DraftEntry } from '../models/Draft';
import { MediaDirs, MediaFileSystem, HarmonyMediaFileSystem, deleteFilesInDir } from './MediaFiles';
import { ImageCache, COVER_CACHE_KEY_PREFIX } from './ImageCache';
import { MediaUsage, PHOTO_DIR_NAME, AUDIO_DIR_NAME, referencedFilenames, scanMediaUsage,
  reclaimOrphanFiles, ReclaimResult, isOrphanReclaimAllowed, entryPhotoFilenames,
  entryAudioFilenames, draftPhotoFilenames, draftAudioFilenames, parseAudioUrls } from './MediaStorage';

const DOMAIN = 0x0000;
const TAG = 'MediaStorageService';

/** 库里的记录数（孤儿清理安全闸用）。读库失败计 -1，落进「不允许清理」一侧 */
export class LibraryCounts {
  readonly entryCount: number;
  readonly draftCount: number;
  readonly coverCount: number;

  constructor(entryCount: number, draftCount: number, coverCount: number) {
    this.entryCount = entryCount;
    this.draftCount = draftCount;
    this.coverCount = coverCount;
  }
}

export class MediaStorageService {
  private readonly db: relationalStore.RdbStore;
  private readonly fs: MediaFileSystem;
  private readonly dirs: MediaDirs;

  constructor(db: relationalStore.RdbStore, fs: MediaFileSystem, dirs: MediaDirs) {
    this.db = db;
    this.fs = fs;
    this.dirs = dirs;
  }

  /** 按应用沙箱 filesDir 建服务（目录不存在则创建），真机默认入口 */
  static create(context: common.Context, db: relationalStore.RdbStore,
    fs: MediaFileSystem = new HarmonyMediaFileSystem()): MediaStorageService {
    const dirs = new MediaDirs(`${context.filesDir}/${PHOTO_DIR_NAME}`,
      `${context.filesDir}/${AUDIO_DIR_NAME}`);
    fs.mkdirs(dirs.photosDir);
    fs.mkdirs(dirs.audioDir);
    return new MediaStorageService(db, fs, dirs);
  }

  /** 媒体占用概况（只统计不删除，R-DATA-08「照片与录音占用」） */
  async usage(): Promise<MediaUsage> {
    const referenced = await this.loadReferenced();
    return scanMediaUsage(this.fs, this.dirs, referenced);
  }

  /**
   * 删掉所有没被任何日记 / 草稿 / 封面引用的媒体文件（「清理残留文件」入口）。
   *
   * **以库为准**：每次都重新读一遍全部引用，不依赖任何缓存或标记 ——
   * 这是在删用户的文件，宁可多扫一遍库，也不能因为一份过期的清单误删还在用的照片（iOS 同款注释）。
   * 安全闸（isOrphanReclaimAllowed）不过 → 一个都不删，返回 0 字节。
   */
  async reclaimOrphans(): Promise<ReclaimResult> {
    const referenced = await this.loadReferenced();
    const counts = await this.loadCounts();
    if (!isOrphanReclaimAllowed(referenced.size, counts.entryCount, counts.draftCount,
      counts.coverCount)) {
      return new ReclaimResult(0, []);
    }
    const result = reclaimOrphanFiles(this.fs, this.dirs, referenced);
    this.evictFromCache(result.deletedFiles);
    return result;
  }

  /** 删这篇日记引用的全部媒体文件（照片三件套 + 录音）。先调它、再删库里的记录（05 §2） */
  deleteEntryMedia(entry: JournalEntry): number {
    const photos = entryPhotoFilenames(entry);
    const audios = entryAudioFilenames(entry);
    const deleted = deleteFilesInDir(this.fs, this.dirs.photosDir, photos) +
      deleteFilesInDir(this.fs, this.dirs.audioDir, audios);
    this.evictFromCache(photos);
    return deleted;
  }

  /**
   * 删这份草稿引用的全部媒体文件。🔴 只在「不保存」丢弃草稿时调；
   * 转正时**绝对不能调**——那些文件正要被新日记接着用（R-ENTRY-03）。
   */
  deleteDraftMedia(draft: DraftEntry): number {
    const photos = draftPhotoFilenames(draft);
    const audios = draftAudioFilenames(draft);
    const deleted = deleteFilesInDir(this.fs, this.dirs.photosDir, photos) +
      deleteFilesInDir(this.fs, this.dirs.audioDir, audios);
    this.evictFromCache(photos);
    return deleted;
  }

  /** 删日记本的旧封面文件（换 / 移除 / 删本时；R-BOOK-16 的本地部分） */
  deleteCoverFile(filename: string): void {
    if (filename.length === 0) {
      return;
    }
    this.fs.deleteFile(`${this.dirs.photosDir}/${filename}`);
    this.evictFromCache([filename]);
  }

  // ---- 读库 ----

  /**
   * 库里所有**日记、草稿、日记本封面**引用到的文件名集合（R-DATA-08 引用表）。
   * 单表读失败只丢那张表的贡献（对齐 iOS `try? fetch ?? []`），绝不让整次扫描失败。
   */
  private async loadReferenced(): Promise<Set<string>> {
    const entries: JournalEntry[] = [];
    const entrySet = await this.queryOrLog(
      'SELECT id, date, created_at, updated_at, content_blocks, audio_urls FROM journal_entry');
    if (entrySet !== undefined) {
      try {
        while (entrySet.goToNextRow()) {
          const entry = new JournalEntry(entrySet.getString(0), entrySet.getLong(1),
            entrySet.getLong(2), entrySet.getLong(3));
          if (!entrySet.isColumnNull(4)) {
            entry.contentBlocksData = entrySet.getString(4);
          }
          entry.audioURLs = entrySet.isColumnNull(5) ? [] : parseAudioUrls(entrySet.getString(5));
          entries.push(entry);
        }
      } finally {
        entrySet.close();
      }
    }

    const drafts: DraftEntry[] = [];
    const draftSet = await this.queryOrLog(
      'SELECT id, created_at, updated_at, content_blocks, audio_urls FROM draft');
    if (draftSet !== undefined) {
      try {
        while (draftSet.goToNextRow()) {
          const draft = new DraftEntry(draftSet.getString(0), draftSet.getLong(1),
            draftSet.getLong(2));
          if (!draftSet.isColumnNull(3)) {
            draft.contentBlocksData = draftSet.getString(3);
          }
          draft.audioURLs = draftSet.isColumnNull(4) ? [] : parseAudioUrls(draftSet.getString(4));
          drafts.push(draft);
        }
      } finally {
        draftSet.close();
      }
    }

    const covers: string[] = [];
    const coverSet = await this.queryOrLog(
      "SELECT cover_photo_filename FROM notebook WHERE cover_photo_filename IS NOT NULL " +
      "AND cover_photo_filename != ''");
    if (coverSet !== undefined) {
      try {
        while (coverSet.goToNextRow()) {
          if (!coverSet.isColumnNull(0)) {
            const cover = coverSet.getString(0);
            if (cover.length > 0) {
              covers.push(cover);
            }
          }
        }
      } finally {
        coverSet.close();
      }
    }

    return referencedFilenames(entries, drafts, covers);
  }

  /** 库里的记录数（安全闸用）。查询失败计 -1（读不到库就更不该动文件） */
  private async loadCounts(): Promise<LibraryCounts> {
    const entryCount = await this.countOrLog('SELECT COUNT(*) FROM journal_entry');
    const draftCount = await this.countOrLog('SELECT COUNT(*) FROM draft');
    const coverCount = await this.countOrLog(
      "SELECT COUNT(*) FROM notebook WHERE cover_photo_filename IS NOT NULL " +
      "AND cover_photo_filename != ''");
    return new LibraryCounts(entryCount, draftCount, coverCount);
  }

  private async queryOrLog(sql: string): Promise<relationalStore.ResultSet | undefined> {
    try {
      return await this.db.querySql(sql);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'querySql failed: %{public}s %{public}s', sql, JSON.stringify(err));
      return undefined;
    }
  }

  private async countOrLog(sql: string): Promise<number> {
    const set = await this.queryOrLog(sql);
    if (set === undefined) {
      return -1;
    }
    try {
      return set.goToNextRow() ? set.getLong(0) : -1;
    } finally {
      set.close();
    }
  }

  /** 删掉的文件清出图片缓存（正文小图 + 封面大图两个键），防止渲染出已删除的旧图 */
  private evictFromCache(filenames: string[]): void {
    const cache = ImageCache.shared();
    for (const name of filenames) {
      cache.remove(name);
      cache.remove(COVER_CACHE_KEY_PREFIX + name);
    }
  }
}
