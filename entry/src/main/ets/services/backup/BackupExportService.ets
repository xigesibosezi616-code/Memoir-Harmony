/**
 * 把用户的全部日记打成一个可分享的备份包（6.5；08_backup_package.md §4、iOS `Services/Backup/BackupExporter.swift`）。
 *
 * 流程：组装临时目录 → zlib 压成 zip →（可选）整体加密 → 落到 cacheDir 交给分享面板。
 *
 * - 输出文件「尺素备份_yyyyMMdd.memoir」：iOS 那边的 zip 以目录名命名（NSFileCoordinator），
 *   这边手动保持一致 —— 双端包内结构相同，导入端 findPackageRoot 对平铺 / 套一层都认
 * - **导出只读库不写库**，任何时刻取消都不伤数据；临时目录用完即删（finally）
 * - 日记本按书架顺序写出 —— 导入端按数组顺序接在书架末尾（merge），
 *   书架顺序就这样带过去了，备份格式不用为 sortOrder 加字段
 * - moodSummaries（会员情绪小结）鸿蒙侧没有对应模型，**不写这个字段**（可选字段，
 *   老格式的包长得和以前一样）；penPalNotes（笔友手记，U01 B3）写进 letters.json，
 *   没有手记时字段整个不写（iOS 导出空时 nil 同款）
 */
import { relationalStore } from '@kit.ArkData';
import { common, bundleManager } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { JournalEntry } from '../../models/JournalEntry';
import { ContentBlock, ContentBlockType } from '../../models/ContentBlock';
import { Notebook } from '../../models/Notebook';
import { Letter } from '../../models/Letter';
import { WritingStreak } from '../../models/WritingStreak';
import { PenPalNote } from '../../models/PenPalNote';
import { AppPrefs } from '../AppPrefs';
import { PHOTO_DIR_NAME, AUDIO_DIR_NAME } from '../MediaStorage';
import { BackupFormat, toBackupIso8601, ManifestWire, ManifestCountsWire,
  BlockWire, EntryWire, WritingStatsWire, EntriesWire, LetterWire, LettersWire,
  PenPalNoteWire, TagWire, TaxonomyWire } from './BackupFormat';
import { BackupCrypto } from './BackupCrypto';
import { readBytes, writeBytes, writeTextFile, removeTree, ensureDir,
  fileExists, fileSizeOf, lastPathComponent } from './BackupFs';

const DOMAIN = 0x0000;
const TAG = 'BackupExportService';

/** zlib 打包的中间产物（cacheDir 下，读完就删） */
const PAYLOAD_ZIP_NAME = 'memoir-export-payload.zip';

// ---- 错误 ----

export enum BackupExportError {
  NothingToExport = 'nothingToExport',
  AssemblyFailed = 'assemblyFailed',
  ZipFailed = 'zipFailed'
}

/** 带类型的导出失败：UI 按 kind 映射用户文案；detail 供插值 */
export class BackupExportFailure extends Error {
  readonly kind: BackupExportError;
  readonly detail: string;

  constructor(kind: BackupExportError, detail: string = '') {
    super(kind);
    this.kind = kind;
    this.detail = detail;
  }
}

// ---- 输入输出 ----

export class BackupExportOptions {
  /** 关掉则只导出文字，包体通常只有几百 KB —— 大文件传输限制下的保命通道 */
  includesMedia: boolean = true;
  /** undefined / 空串 = 不加密（文件就是纯 zip） */
  password: string | undefined = undefined;
}

export class BackupExportResult {
  /** .memoir 文件的完整沙箱路径，交给分享面板用 */
  filePath: string = '';
  byteCount: number = 0;
  entryCount: number = 0;
  mediaCount: number = 0;
}

/** copyMedia 的产出（manifest 的 mediaTotalBytes / counts.media 都来自这里） */
class MediaCopyResult {
  bytes: number = 0;
  count: number = 0;
}

export class BackupExportService {
  /**
   * 导出前给用户看的媒体体积预估（对齐 iOS estimateMediaBytes 口径）：
   * 日记本照片封面 + 正文照片 + 录音。Live Photo 的视频 / 原图与 iOS 一样不计入，
   * 只是预估，实际字节数以导出时 copyMedia 统计为准
   */
  static estimateMediaBytes(context: common.Context, entries: JournalEntry[],
    tags: Notebook[]): number {
    const photosDir = `${context.filesDir}/${PHOTO_DIR_NAME}`;
    const audioDir = `${context.filesDir}/${AUDIO_DIR_NAME}`;
    let total = 0;
    const counted = new Set<string>();
    for (const tag of tags) {
      const cover = tag.coverPhotoFilename;
      if (cover !== undefined && cover.length > 0 && !counted.has(cover)) {
        counted.add(cover);
        total += BackupExportService.positiveFileSize(`${photosDir}/${cover}`);
      }
    }
    for (const entry of entries) {
      for (const block of entry.contentBlocks) {
        if (block.type !== ContentBlockType.Photo) {
          continue;
        }
        const name = block.photoFilename;
        if (name !== undefined && !counted.has(name)) {
          counted.add(name);
          total += BackupExportService.positiveFileSize(`${photosDir}/${name}`);
        }
      }
      for (const relative of entry.audioURLs) {
        const name = lastPathComponent(relative);
        if (!counted.has(name)) {
          counted.add(name);
          total += BackupExportService.positiveFileSize(`${audioDir}/${name}`);
        }
      }
    }
    return total;
  }

  /**
   * 导出。成功后返回 .memoir 文件路径；临时文件全部清理干净，只剩这一个产物。
   * 导出过程**不写库**（除 U16：最长连续写作按导出时算一次的口径更新偏好，只升不降）。
   */
  static async export(context: common.Context, store: relationalStore.RdbStore,
    entries: JournalEntry[], letters: Letter[], tags: Notebook[],
    penPalNotes: PenPalNote[], options: BackupExportOptions): Promise<BackupExportResult> {
    if (entries.length === 0) {
      throw new BackupExportFailure(BackupExportError.NothingToExport);
    }

    const stageName = `尺素备份_${BackupExportService.dateStamp(Date.now())}`;
    const stage = `${context.cacheDir}/${stageName}`;
    // 上次导出的残留会污染这次的内容
    removeTree(stage);
    if (!ensureDir(stage)) {
      throw new BackupExportFailure(BackupExportError.AssemblyFailed, 'mkdir stage failed');
    }

    // 最长连续写作：记下的和这些日记里算出来的取大的（U16：导出时各算一次，只升不降）
    const dates: number[] = [];
    for (const entry of entries) {
      dates.push(entry.date);
    }
    const recorded = AppPrefs.recordedBestStreakDays();
    const best = WritingStreak.raisedValue(recorded, WritingStreak.longestRun(dates));
    if (best > recorded) {
      AppPrefs.setRecordedBestStreakDays(best);
    }

    try {
      // 1. 媒体：先拷贝，因为要统计实际字节数写进 manifest
      let mediaResult: MediaCopyResult = new MediaCopyResult();
      if (options.includesMedia) {
        const mediaDir = `${stage}/${BackupFormat.mediaDirectory}`;
        if (!ensureDir(mediaDir)) {
          throw new BackupExportFailure(BackupExportError.AssemblyFailed, 'mkdir media failed');
        }
        mediaResult = BackupExportService.copyMedia(entries, tags, mediaDir,
          `${context.filesDir}/${PHOTO_DIR_NAME}`, `${context.filesDir}/${AUDIO_DIR_NAME}`);
      }

      // 2. 信件关联（letter_entry 多对多），一次查全
      const links = await BackupExportService.letterEntryLinks(store);

      // 3. JSON（pretty + 键序对齐 iOS jsonEncoder，便于双端 diff 同一份数据）
      const entriesFile = new EntriesWire();
      const wireEntries: EntryWire[] = [];
      for (const entry of entries) {
        wireEntries.push(BackupExportService.makeWireEntry(entry, options.includesMedia));
      }
      entriesFile.entries = wireEntries;
      entriesFile.writingStats = new WritingStatsWire();
      entriesFile.writingStats.bestStreakDays = best;
      if (!writeTextFile(`${stage}/${BackupFormat.entriesFile}`,
        JSON.stringify(entriesFile, null, 2))) {
        throw new BackupExportFailure(BackupExportError.AssemblyFailed, 'write entries.json failed');
      }

      const lettersFile = new LettersWire();
      const wireLetters: LetterWire[] = [];
      for (const letter of letters) {
        wireLetters.push(BackupExportService.makeWireLetter(letter,
          links.get(letter.id) ?? []));
      }
      lettersFile.letters = wireLetters;
      // 笔友手记（U01 B3）：没有时字段整个不写（老包形状不变）
      if (penPalNotes.length > 0) {
        const wireNotes: PenPalNoteWire[] = [];
        for (const note of penPalNotes) {
          wireNotes.push(BackupExportService.makeWirePenPalNote(note));
        }
        lettersFile.penPalNotes = wireNotes;
      }
      if (!writeTextFile(`${stage}/${BackupFormat.lettersFile}`,
        JSON.stringify(lettersFile, null, 2))) {
        throw new BackupExportFailure(BackupExportError.AssemblyFailed, 'write letters.json failed');
      }

      // 日记本按书架顺序写出（fetchAllNotebooks 已排好，这里不重排）
      const taxonomy = new TaxonomyWire();
      const wireTags: TagWire[] = [];
      for (const tag of tags) {
        wireTags.push(BackupExportService.makeWireTag(tag, options.includesMedia));
      }
      taxonomy.tags = wireTags;
      if (!writeTextFile(`${stage}/${BackupFormat.taxonomyFile}`,
        JSON.stringify(taxonomy, null, 2))) {
        throw new BackupExportFailure(BackupExportError.AssemblyFailed, 'write taxonomy.json failed');
      }

      const manifest = new ManifestWire();
      manifest.appVersion = await BackupExportService.appVersion();
      manifest.exportedAt = toBackupIso8601(Date.now());
      manifest.counts = new ManifestCountsWire();
      manifest.counts.entries = entries.length;
      manifest.counts.letters = letters.length;
      manifest.counts.media = mediaResult.count;
      manifest.includesMedia = options.includesMedia;
      manifest.mediaTotalBytes = mediaResult.bytes;
      manifest.encrypted = options.password !== undefined && options.password.length > 0;
      if (!writeTextFile(`${stage}/${BackupFormat.manifestFile}`,
        JSON.stringify(manifest, null, 2))) {
        throw new BackupExportFailure(BackupExportError.AssemblyFailed, 'write manifest.json failed');
      }

      // 4. 打包（目录 → zip）
      const zipPath = `${context.cacheDir}/${PAYLOAD_ZIP_NAME}`;
      removeTree(zipPath);
      try {
        const zlibOptions: zlib.Options = {};
        await zlib.compressFile(stage, zipPath, zlibOptions);
      } catch (err) {
        throw new BackupExportFailure(BackupExportError.ZipFailed,
          `compressFile failed: ${JSON.stringify(err)}`);
      }
      let zipData: Uint8Array | undefined = undefined;
      try {
        zipData = readBytes(zipPath);
      } finally {
        removeTree(zipPath);
      }
      if (zipData === undefined) {
        throw new BackupExportFailure(BackupExportError.ZipFailed, 'read payload.zip failed');
      }

      // 5. 加密（可选）
      let payload: Uint8Array;
      if (options.password !== undefined && options.password.length > 0) {
        try {
          payload = await BackupCrypto.encrypt(zipData, options.password);
        } catch (err) {
          hilog.error(DOMAIN, TAG, 'encrypt failed: %{public}s', JSON.stringify(err));
          throw new BackupExportFailure(BackupExportError.ZipFailed, 'encrypt failed');
        }
      } else {
        payload = zipData;
      }

      // 6. 落到 cacheDir 交给分享面板
      const outPath = `${context.cacheDir}/${stageName}.${BackupFormat.fileExtension}`;
      removeTree(outPath);
      if (!writeBytes(outPath, payload)) {
        throw new BackupExportFailure(BackupExportError.ZipFailed, 'write .memoir failed');
      }

      const result = new BackupExportResult();
      result.filePath = outPath;
      result.byteCount = payload.length;
      result.entryCount = entries.length;
      result.mediaCount = mediaResult.count;
      return result;
    } finally {
      // 组装目录使命结束（zip 已打好 / 出错废弃），不留残留
      removeTree(stage);
    }
  }

  // ---- 媒体收集 ----

  /** 同一文件被多篇引用时只拷一次；单个拷贝失败不挡整个备份（导入端对缺失媒体有降级处理） */
  private static copyMedia(entries: JournalEntry[], tags: Notebook[], mediaDir: string,
    photosDir: string, audioDir: string): MediaCopyResult {
    const result = new MediaCopyResult();
    const copied = new Set<string>();
    const copy = (source: string, name: string): void => {
      if (name.length === 0 || copied.has(name) || !fileExists(source)) {
        return;
      }
      const dest = `${mediaDir}/${name}`;
      try {
        fileIo.copyFileSync(source, dest);
        copied.add(name);
        result.bytes += Math.max(0, fileSizeOf(dest));
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'media copy failed %{public}s: %{public}s',
          name, JSON.stringify(err));
      }
    };
    for (const entry of entries) {
      for (const block of entry.contentBlocks) {
        if (block.type !== ContentBlockType.Photo) {
          continue;
        }
        if (block.photoFilename !== undefined) {
          copy(`${photosDir}/${block.photoFilename}`, block.photoFilename);
        }
        if (block.livePhotoVideoFilename !== undefined) {
          copy(`${photosDir}/${block.livePhotoVideoFilename}`, block.livePhotoVideoFilename);
        }
        // 相机拍的 Live Photo 还有一份未裁原图 —— 不带走的话导入端就配不成对了
        if (block.livePhotoStillFilename !== undefined) {
          copy(`${photosDir}/${block.livePhotoStillFilename}`, block.livePhotoStillFilename);
        }
      }
      for (const relative of entry.audioURLs) {
        // audioURLs 存的是 "audio/xxx.m4a" 这样的相对路径，包内统一用扁平文件名
        const name = lastPathComponent(relative);
        copy(`${audioDir}/${name}`, name);
      }
    }
    // 日记本的照片封面
    for (const tag of tags) {
      const cover = tag.coverPhotoFilename;
      if (cover !== undefined && cover.length > 0) {
        copy(`${photosDir}/${cover}`, cover);
      }
    }
    result.count = copied.size;
    return result;
  }

  // ---- 模型 → wire ----

  private static makeWireEntry(entry: JournalEntry, includesMedia: boolean): EntryWire {
    const wire = new EntryWire();
    wire.id = entry.id;
    wire.title = entry.title;
    wire.date = toBackupIso8601(entry.date);
    wire.createdAt = toBackupIso8601(entry.createdAt);
    wire.updatedAt = toBackupIso8601(entry.updatedAt);
    // 作废字段：mood 写 ""（老版本 iOS 当必填读）；moodColorHex 不写（iOS 导出也是 nil）
    wire.mood = '';
    wire.tags = entry.tags;
    wire.isFavorite = entry.isFavorite;
    wire.weatherCode = entry.weatherCode;
    wire.weatherInfo = entry.weatherInfo;
    wire.locationInfo = entry.locationInfo;
    wire.audio = includesMedia
      ? entry.audioURLs.map((relative: string) => lastPathComponent(relative))
      : [];
    wire.moodValence = entry.moodValence;
    wire.moodLabels = entry.moodLabels;
    const blocks: BlockWire[] = [];
    for (const block of entry.contentBlocks) {
      blocks.push(BackupExportService.makeWireBlock(block, includesMedia));
    }
    wire.blocks = blocks;
    return wire;
  }

  private static makeWireBlock(block: ContentBlock, includesMedia: boolean): BlockWire {
    const wire = new BlockWire();
    wire.type = block.type;
    wire.text = block.text;
    wire.styles = block.styles;
    if (includesMedia) {
      // 录音块记的是 "audio/xxx.m4a"，包内统一用扁平文件名（同 audio 清单）
      if (block.type === ContentBlockType.Audio) {
        if (block.audioFilename !== undefined) {
          wire.file = lastPathComponent(block.audioFilename);
        }
      } else {
        wire.file = block.photoFilename;
      }
      wire.liveVideo = block.livePhotoVideoFilename;
      wire.liveStill = block.livePhotoStillFilename;
    }
    wire.paperStyle = block.paperStyle;
    wire.position = block.position;
    wire.rotationAngle = block.rotationAngle;
    wire.isCover = block.isCover;
    wire.addedAt = block.addedAt;
    wire.traceOf = block.traceOf;
    wire.removedAt = block.removedAt;
    return wire;
  }

  /** Letter → 包内 wire 形态。非 private：letters 导出 round-trip 单测直接调 */
  static makeWireLetter(letter: Letter, relatedEntryIds: string[]): LetterWire {
    const wire = new LetterWire();
    wire.id = letter.id;
    wire.body = letter.body;
    wire.fromCharacter = letter.fromCharacter;
    wire.toName = letter.toName;
    wire.stationery = letter.stationery;
    // status / triggerKind 原样字符串（后端会新增取值，不该在导出时被枚举截断）
    wire.status = letter.status;
    wire.triggerKind = letter.triggerKind;
    wire.generatedAt = toBackupIso8601(letter.generatedAt);
    if (letter.deliveredAt !== undefined) {
      wire.deliveredAt = toBackupIso8601(letter.deliveredAt);
    }
    if (letter.readAt !== undefined) {
      wire.readAt = toBackupIso8601(letter.readAt);
    }
    wire.relatedEntryIDs = relatedEntryIds;
    // 世界笔友四字段（可选；老包导入的信没有，原样不写）
    wire.penPalID = letter.penPalId;
    wire.translatedBody = letter.translatedBody;
    wire.danger = letter.danger;
    wire.postage = letter.postage;
    return wire;
  }

  /** PenPalNote → 包内 wire 形态（U01 B3）。非 private：round-trip 单测直接调 */
  static makeWirePenPalNote(note: PenPalNote): PenPalNoteWire {
    const wire = new PenPalNoteWire();
    wire.id = note.id;
    wire.penPalID = note.penPalID;
    wire.text = note.text;
    // kind 原样写出（可能有不认识的值），undefined 时省略（导入端按 recent）
    wire.kind = note.kind;
    wire.notedAt = toBackupIso8601(note.notedAtMs);
    wire.createdAt = toBackupIso8601(note.createdAtMs);
    if (note.updatedAtMs !== undefined) {
      wire.updatedAt = toBackupIso8601(note.updatedAtMs);
    }
    return wire;
  }

  private static makeWireTag(tag: Notebook, includesMedia: boolean): TagWire {
    const wire = new TagWire();
    wire.id = tag.id;
    wire.name = tag.name;
    wire.colorID = tag.colorId;
    wire.textureID = tag.textureId;
    wire.createdAt = toBackupIso8601(tag.createdAt);
    if (includesMedia) {
      wire.coverFile = tag.coverPhotoFilename;
      // 「仅文字」导出不带照片，版式也就没意义了
      wire.coverLayout = tag.coverLayoutId;
    }
    wire.subtitle = tag.subtitle;
    return wire;
  }

  // ---- 辅助 ----

  /** letter_entry 全表 → letterId → entryIds[]。查询失败按空处理（关联丢了不算错） */
  private static async letterEntryLinks(store: relationalStore.RdbStore):
    Promise<Map<string, string[]>> {
    const links = new Map<string, string[]>();
    try {
      const result = await store.querySql('SELECT letter_id, entry_id FROM letter_entry');
      try {
        while (result.goToNextRow()) {
          const letterId = result.getString(0);
          const entryId = result.getString(1);
          const list = links.get(letterId);
          if (list !== undefined) {
            list.push(entryId);
          } else {
            links.set(letterId, [entryId]);
          }
        }
      } finally {
        // close 抛错由外层 catch 兜住（丢的是日志，不是数据）
        result.close();
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'query letter_entry failed: %{public}s', JSON.stringify(err));
    }
    return links;
  }

  private static async appVersion(): Promise<string> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName.length > 0 ? info.versionName : '1.0';
    } catch (err) {
      return '1.0';
    }
  }

  /** 本地时间 yyyyMMdd（文件名用，和 iOS DateFormatter 同口径） */
  private static dateStamp(now: number): string {
    const d = new Date(now);
    const month = d.getMonth() + 1;
    const day = d.getDate();
    const mm = month < 10 ? `0${month}` : `${month}`;
    const dd = day < 10 ? `0${day}` : `${day}`;
    return `${d.getFullYear()}${mm}${dd}`;
  }

  /** 文件存在取字节数，不存在 0（预估用，和 iOS fileSize 的 ?? 0 一致） */
  private static positiveFileSize(path: string): number {
    const size = fileSizeOf(path);
    return size > 0 ? size : 0;
  }
}
