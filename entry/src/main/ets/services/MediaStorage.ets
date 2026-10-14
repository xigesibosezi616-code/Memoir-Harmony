/**
 * 媒体文件的引用表、占用统计与孤儿清理的**纯逻辑**（10_BUILD_MANUAL.md 1.4）。
 * 对应 iOS `Services/MediaStorage.swift`；接 RDB 的服务壳在 `MediaStorageService.ets`。
 *
 * 照片 / 录音 / 封面都是**磁盘上的独立文件**，库里只存文件名。这意味着：
 * - 删日记时忘了删文件，文件就永远留着（用户看不见，也没有任何入口能删）
 * - 写盘成功但入库失败（中途取消、App 被杀）的产物同样是孤儿
 * 所以要有一条「以库为准，扫盘对账」的回收路径。
 *
 * **引用表**（R-DATA-08）= 所有日记的照片三件套 + 录音 + **草稿**引用的 + **日记本封面**。
 * 漏掉任何一类，「清理残留文件」就会误删用户的东西（iOS 两次差点踩：草稿、封面）。
 *
 * 云端副本（iOS 的 MediaAsset / CloudKit）鸿蒙侧不做（云同步阻塞 Q3）；
 * R-DATA-07 的「连云端副本一起删」等云同步方案落地后再接。
 */
import { JournalEntry } from '../models/JournalEntry';
import { DraftEntry } from '../models/Draft';
import { ContentBlockType } from '../models/ContentBlock';
import { MediaFileEntry, MediaDirs, MediaFileSystem } from './MediaFiles';

/** 照片目录名（应用沙箱 filesDir 下；对应 iOS Documents/journal_photos/） */
export const PHOTO_DIR_NAME: string = 'journal_photos';

/** 录音目录名 */
export const AUDIO_DIR_NAME: string = 'audio';

/** 录音在库里记的相对路径前缀（"audio/xxx.m4a"） */
export const AUDIO_PREFIX: string = `${AUDIO_DIR_NAME}/`;

// ---- 命名规则（05_DATA_MODEL.md §8） ----

/** 日记照片：`photo_<UUID 前 8 位>.jpg`，JPEG 质量 0.85 */
export function photoFilenameFor(uuid: string): string {
  return `photo_${uuid.substring(0, 8)}.jpg`;
}

/** 相机拍的未裁原图：`photo_<同上>_full.jpg`。🔴 原样字节，绝不重编码（R-PHOTO-03） */
export function fullPhotoFilenameFor(uuid: string): string {
  return `photo_${uuid.substring(0, 8)}_full.jpg`;
}

/** 动态照片视频：`photo_<同上>.mov`。原样字节 */
export function livePhotoVideoFilenameFor(uuid: string): string {
  return `photo_${uuid.substring(0, 8)}.mov`;
}

/** 日记本照片封面：`cover_<UUID>.jpg`（与日记照片同目录） */
export function coverFilenameFor(uuid: string): string {
  return `cover_${uuid}.jpg`;
}

// ---- 占用概况 ----

/** 媒体占用概况（iOS `MediaStorage.Usage`） */
export class MediaUsage {
  /** 被引用的文件数与字节数 */
  referencedCount: number = 0;
  referencedBytes: number = 0;
  /** 没有任何引用的文件数与字节数（可安全清理） */
  orphanCount: number = 0;
  orphanBytes: number = 0;

  get totalBytes(): number {
    return this.referencedBytes + this.orphanBytes;
  }
}

// ---- 引用表（R-DATA-08） ----

/**
 * 库里所有**日记、草稿、日记本封面**引用到的文件名集合。
 * 照片 / 封面是 `journal_photos/` 下的裸名；录音既记 `"audio/xxx.m4a"` 相对路径、
 * 也记裸名（扫盘两侧都能对上）。
 *
 * ⚠️ **草稿必须算在内**：草稿里的照片在插入那一刻就落盘了，却还没有任何日记引用它 ——
 * 漏算的话，用户存了草稿再去清理残留文件，草稿里的图就被当孤儿删了。
 * ⚠️ **日记本的照片封面也必须算在内**：只有封面、还没写日记的新设备，不能被当成空库。
 */
export function referencedFilenames(entries: JournalEntry[], drafts: DraftEntry[],
  coverFilenames: string[]): Set<string> {
  const names = new Set<string>();
  for (const entry of entries) {
    for (const block of entry.contentBlocks) {
      if (block.type !== ContentBlockType.Photo) {
        continue;
      }
      if (block.photoFilename !== undefined) {
        names.add(block.photoFilename);
      }
      if (block.livePhotoVideoFilename !== undefined) {
        names.add(block.livePhotoVideoFilename);
      }
      if (block.livePhotoStillFilename !== undefined) {
        names.add(block.livePhotoStillFilename);
      }
    }
    for (const relative of entry.audioURLs) {
      names.add(relative);
      addBareName(names, relative);
    }
  }
  for (const draft of drafts) {
    for (const name of draft.referencedMediaNames) {
      names.add(name);
    }
  }
  for (const cover of coverFilenames) {
    if (cover.length > 0) {
      names.add(cover);
    }
  }
  return names;
}

/** 把 "audio/xxx.m4a" 的裸名部分 xxx.m4a 也记进集合 */
function addBareName(names: Set<string>, relative: string): void {
  const slash = relative.lastIndexOf('/');
  if (slash >= 0) {
    names.add(relative.substring(slash + 1));
  }
}

/**
 * 扫盘结果与引用表对账（纯函数）。⚠️ 只统计不删除。
 * 照片目录的文件以裸名比对；录音目录的文件以 `"audio/<名>"` 与裸名双侧比对。
 */
export function classifyMediaFiles(photoFiles: MediaFileEntry[], audioFiles: MediaFileEntry[],
  referenced: Set<string>): MediaUsage {
  const usage = new MediaUsage();
  accumulateUsage(usage, photoFiles, '', referenced);
  accumulateUsage(usage, audioFiles, AUDIO_PREFIX, referenced);
  return usage;
}

function accumulateUsage(usage: MediaUsage, files: MediaFileEntry[], prefix: string,
  referenced: Set<string>): void {
  for (const file of files) {
    if (referenced.has(prefix + file.name) || referenced.has(file.name)) {
      usage.referencedCount++;
      usage.referencedBytes += file.size;
    } else {
      usage.orphanCount++;
      usage.orphanBytes += file.size;
    }
  }
}

// ---- 孤儿清理的安全闸 ----

/**
 * 孤儿清理的安全闸（iOS `reclaimOrphans` 的 guard）：
 * - 引用表非空 → 允许（正常路径，只删引用表之外的）
 * - 引用表为空 → 必须**日记、草稿、封面全都是零**才允许（这时文件确实没有主人）
 * - 读库失败计 -1，落进「不允许」一侧 —— 读不到库就更不该动文件
 *
 * 否则「没有引用」多半是库还没加载好的假象，照删会把用户的照片全清光。
 */
export function isOrphanReclaimAllowed(referencedCount: number, entryCount: number,
  draftCount: number, coverCount: number): boolean {
  if (referencedCount > 0) {
    return true;
  }
  return entryCount === 0 && draftCount === 0 && coverCount === 0;
}

// ---- 删日记 / 草稿的媒体清单（05 §2「先删它引用的全部媒体文件，再删记录」） ----

/** 这篇日记在 journal_photos/ 下引用的全部文件名（照片三件套，去重、按出现序） */
export function entryPhotoFilenames(entry: JournalEntry): string[] {
  const names = new Set<string>();
  for (const block of entry.contentBlocks) {
    if (block.type !== ContentBlockType.Photo) {
      continue;
    }
    if (block.photoFilename !== undefined) {
      names.add(block.photoFilename);
    }
    if (block.livePhotoVideoFilename !== undefined) {
      names.add(block.livePhotoVideoFilename);
    }
    if (block.livePhotoStillFilename !== undefined) {
      names.add(block.livePhotoStillFilename);
    }
  }
  return Array.from(names);
}

/** 这篇日记在 audio/ 下引用的全部录音文件名（audioURLs 的裸名部分，去重、按顺序） */
export function entryAudioFilenames(entry: JournalEntry): string[] {
  const names = new Set<string>();
  for (const relative of entry.audioURLs) {
    const slash = relative.lastIndexOf('/');
    names.add(slash >= 0 ? relative.substring(slash + 1) : relative);
  }
  return Array.from(names);
}

/** 这份草稿在 journal_photos/ 下引用的全部文件名（照片三件套，去重） */
export function draftPhotoFilenames(draft: DraftEntry): string[] {
  const names = new Set<string>();
  for (const block of draft.contentBlocks) {
    if (block.type !== ContentBlockType.Photo) {
      continue;
    }
    if (block.photoFilename !== undefined) {
      names.add(block.photoFilename);
    }
    if (block.livePhotoVideoFilename !== undefined) {
      names.add(block.livePhotoVideoFilename);
    }
    if (block.livePhotoStillFilename !== undefined) {
      names.add(block.livePhotoStillFilename);
    }
  }
  return Array.from(names);
}

/** 这份草稿在 audio/ 下引用的全部录音文件名（audioURLs 的裸名部分，去重） */
export function draftAudioFilenames(draft: DraftEntry): string[] {
  const names = new Set<string>();
  for (const relative of draft.audioURLs) {
    const slash = relative.lastIndexOf('/');
    names.add(slash >= 0 ? relative.substring(slash + 1) : relative);
  }
  return Array.from(names);
}

// ---- 库列解析 ----

/** 解析库里的 audio_urls JSON 列：坏 JSON / 不是数组 / 混入非字符串都只丢坏项 */
export function parseAudioUrls(json: string): string[] {
  try {
    const parsed: Object | null = JSON.parse(json);
    if (parsed !== null && Array.isArray(parsed)) {
      const raw = parsed as Object[];
      const result: string[] = [];
      for (const item of raw) {
        if (typeof item === 'string') {
          result.push(item);
        }
      }
      return result;
    }
  } catch (err) {
    // 坏 JSON 当空清单
  }
  return [];
}

// ---- 扫盘核心（注入 fs） ----

/** 扫两个目录并与引用表对账（统计口径同 classifyMediaFiles） */
export function scanMediaUsage(fileSystem: MediaFileSystem, dirs: MediaDirs,
  referenced: Set<string>): MediaUsage {
  return classifyMediaFiles(fileSystem.listFiles(dirs.photosDir),
    fileSystem.listFiles(dirs.audioDir), referenced);
}

/** 一次孤儿清理的结果：释放的字节数 + 被删文件的裸名清单（图片缓存失效用） */
export class ReclaimResult {
  readonly freedBytes: number;
  readonly deletedFiles: string[];

  constructor(freedBytes: number, deletedFiles: string[]) {
    this.freedBytes = freedBytes;
    this.deletedFiles = deletedFiles;
  }
}

/**
 * 删掉两个目录里所有**不在引用表里**的媒体文件，返回释放的字节数与被删清单。
 * ⚠️ 只删文件不查库；「库确实全空」的安全闸由调用方先过 isOrphanReclaimAllowed。
 */
export function reclaimOrphanFiles(fileSystem: MediaFileSystem, dirs: MediaDirs,
  referenced: Set<string>): ReclaimResult {
  const deleted: string[] = [];
  const freedPhotos = reclaimDir(fileSystem, dirs.photosDir, '', referenced, deleted);
  const freedAudios = reclaimDir(fileSystem, dirs.audioDir, AUDIO_PREFIX, referenced, deleted);
  return new ReclaimResult(freedPhotos + freedAudios, deleted);
}

function reclaimDir(fileSystem: MediaFileSystem, dirPath: string, prefix: string,
  referenced: Set<string>, deleted: string[]): number {
  let freed = 0;
  for (const file of fileSystem.listFiles(dirPath)) {
    if (referenced.has(prefix + file.name) || referenced.has(file.name)) {
      continue;
    }
    if (fileSystem.deleteFile(`${dirPath}/${file.name}`)) {
      freed += file.size;
      deleted.push(file.name);
    }
  }
  return freed;
}
