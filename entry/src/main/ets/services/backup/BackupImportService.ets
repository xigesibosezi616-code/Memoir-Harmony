/**
 * 把 .memoir 备份包读回本机（6.4；08_backup_package.md §4、iOS `Services/Backup/BackupImporter.swift`）。
 *
 * 流程：读文件 →（加密则解密）→ 解压到临时目录 → 校验 manifest → 按 id 合并进库 → 清理临时目录。
 *
 * **合并策略只有一种：跳过已存在的，绝不覆盖**（EXPORT_FORMAT.md §5 决策 3）。
 * 唯一要用户选的是同名日记本合并还是分开（TagConflictPolicy），两种都只增不减。
 * 不提供「替换全部」—— 一次误操作就能清空用户所有日记，收益远小于风险。
 * 导入在任何情况下都只会让库里的东西变多，不会变少。
 *
 * moodSummaries（会员情绪小结）与 penPalNotes（笔友手记）鸿蒙侧没有对应模型，**静默跳过**
 * （格式解析层就没解，见 BackupFormat.ets）。
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { JournalEntry } from '../../models/JournalEntry';
import { ContentBlock, ContentBlockType, PhotoPosition, PaperStyle,
  contentBlockTypeFromRaw, photoPositionFromRaw, paperStyleFromRaw } from '../../models/ContentBlock';
import { Notebook, BookTexture, nameKey, uniqueName, singleNotebook, nextSortOrder,
  retiredColorReplacement, cleanedName } from '../../models/Notebook';
import { Letter } from '../../models/Letter';
import { WritingStreak } from '../../models/WritingStreak';
import { generateUuid, uuidKey } from '../../models/Uuid';
import { SUBTITLE_MAX_LENGTH } from '../../models/CoverEdit';
import { AppPrefs } from '../AppPrefs';
import { EntryRepository } from '../../data/EntryRepository';
import { NotebookRepository } from '../../data/NotebookRepository';
import { LetterRepository } from '../../data/LetterRepository';
import { AUDIO_DIR_NAME, PHOTO_DIR_NAME, AUDIO_PREFIX } from '../MediaStorage';
import { BackupFormat, BackupManifest, BackupEntryDto, BackupLetterDto, BackupTagDto,
  BackupEntriesFile, parseBackupManifest, parseBackupEntries, parseBackupLetters,
  parseBackupTaxonomy } from './BackupFormat';
import { BackupCrypto, BackupCryptoFailure, BackupCryptoError } from './BackupCrypto';
import { readHeadBytes, readBytes, writeBytes, readTextFile, removeTree, ensureDir,
  fileExists, fileSizeOf, lastPathComponent } from './BackupFs';

const DOMAIN = 0x0000;
const TAG = 'BackupImportService';

/** 临时解压目录前缀（cacheDir 下） */
const STAGING_PREFIX = 'memoir-import-';

// ---- 6.4 入口接线（文件关联 / 选择器 → 沙箱中转副本 → 导入页） ----

/** AppStorage key：EntryAbility 收到 .memoir 打开请求（+1 信号，MainTabsView 消费切设置 tab） */
export const STORAGE_KEY_OPEN_BACKUP_IMPORT_TICK = 'openBackupImportTick';
/** AppStorage key：主框架已切设置 tab，设置栈该推导入页了（+1 信号，SettingsTabView 消费） */
export const STORAGE_KEY_BACKUP_IMPORT_REQUEST_TICK = 'backupImportRequestTick';
/** AppStorage key：中转副本的沙箱路径（BackupImport 路由参数） */
export const STORAGE_KEY_BACKUP_IMPORT_SOURCE = 'backupImportSource';

/** 外部 URI 落进沙箱的中转副本文件名（cacheDir 下，单份覆盖；导入页销毁时删除） */
const INTAKE_FILE_NAME = 'memoir-backup-intake.memoir';

// ---- 错误 ----

export enum BackupImportError {
  UnreadableFile = 'unreadableFile',
  /** 包是加密的，但还没拿到密码 —— 不是失败，是要 UI 去问用户 */
  NeedsPassword = 'needsPassword',
  WrongPassword = 'wrongPassword',
  NotABackup = 'notABackup',
  UnsupportedVersion = 'unsupportedVersion',
  StagingFailed = 'stagingFailed',
  SaveFailed = 'saveFailed'
}

/** 带类型的导入失败：UI 按 kind 映射用户文案；version / detail 供插值 */
export class BackupImportFailure extends Error {
  readonly kind: BackupImportError;
  readonly version: number;
  readonly detail: string;

  constructor(kind: BackupImportError, version: number = 0, detail: string = '') {
    super(kind);
    this.kind = kind;
    this.version = version;
    this.detail = detail;
  }
}

// ---- 打开后的包 ----

/** 已解压待导入的包。持有临时目录，用完必须调 discard */
export class BackupPackage {
  readonly manifest: BackupManifest;
  /** manifest.json 所在目录（包内） */
  readonly rootDir: string;
  /** 本次解压的临时根目录（rootDir 在它里面），清理时删这个 */
  readonly stagingDir: string;

  constructor(manifest: BackupManifest, rootDir: string, stagingDir: string) {
    this.manifest = manifest;
    this.rootDir = rootDir;
    this.stagingDir = stagingDir;
  }

  mediaDir(): string {
    return `${this.rootDir}/${BackupFormat.mediaDirectory}`;
  }
}

/** 导入结果。给用户看的那句话就是从这里拼的 */
export class BackupImportSummary {
  entriesImported: number = 0;
  entriesSkipped: number = 0;
  lettersImported: number = 0;
  lettersSkipped: number = 0;
  tagsImported: number = 0;
  /** 包里引用了、但 media/ 下找不到的照片 / 录音数 */
  missingMedia: number = 0;
}

// ---- 同名日记本 ----

/** 包里的日记本和本机的同名时怎么办（只有两边都挂着日记的同名本子才走到这个选择） */
export enum TagConflictPolicy {
  /** 导入的日记放进本机已有的同名日记本（默认） */
  Merge = 'merge',
  /** 作为新日记本导入，名字后面加序号：「旅行」→「旅行 2」 */
  KeepSeparate = 'keepSeparate'
}

/** 包里每个日记本名字导入后叫什么（planTagNames 的产出，纯数据可单测） */
export class TagNamePlan {
  /** 包里的写法 → 导入后用的名字。不在表里的原样用 */
  readonly rename: Map<string, string> = new Map();
  /** 需要问用户的同名日记本（返回包里的写法）。空 = 不用问，直接 Merge */
  readonly conflicts: string[] = [];
}

/**
 * 日记本名字改写计划（纯函数，可单测；iOS `planTagNames` 同逻辑）。
 *
 * 日记靠名字挂在日记本上（journal_entry.tags），所以「合并」和「分开」的区别全在名字：
 * - 合并：包里的「travel」改写成本机的「Travel」，导入的日记自然落进那本
 * - 分开：改写成一个没人用过的「travel 2」，连同它名下导入的日记一起改
 *
 * 「同名」按 nameKey 比（忽略大小写 / 全半角 / 首尾空白），而且要**两边都挂着日记**：
 * 有一边是空本子时合并不会混任何东西，不必打扰用户（两台设备各有一套默认本子，
 * 不这么筛几乎每次导入都弹窗）；包里那边只算这次真会新增的日记（重导同一个包时全会跳过）。
 */
export function planTagNames(incomingEntries: BackupEntryDto[], taxonomyNames: string[],
  localNotebooks: Notebook[], localEntries: JournalEntry[],
  policy: TagConflictPolicy): TagNamePlan {
  const plan = new TagNamePlan();

  // 本机判重键 → 名字（同一个键有多本时取最早建的，与 merge 里挑的是同一本）
  const sortedNotebooks = localNotebooks.slice().sort((a, b) => a.createdAt - b.createdAt);
  const localNameByKey = new Map<string, string>();
  for (const notebook of sortedNotebooks) {
    const key = nameKey(notebook.name);
    if (!localNameByKey.has(key)) {
      localNameByKey.set(key, notebook.name);
    }
  }

  const localIds = new Set<string>();
  const localKeysWithEntries = new Set<string>();
  for (const entry of localEntries) {
    localIds.add(uuidKey(entry.id));
    for (const tag of entry.tags) {
      localKeysWithEntries.add(nameKey(tag));
    }
  }
  // 只算导入后真会落进某一本的：同时挂着几本的日记按单本规则会退回「全部日记」，不进任何一本
  const incomingKeysWithEntries = new Set<string>();
  for (const be of incomingEntries) {
    if (localIds.has(uuidKey(be.id))) {
      continue;
    }
    const keys = new Set<string>();
    for (const tag of be.tags) {
      keys.add(nameKey(tag));
    }
    if (keys.size === 1) {
      const first = Array.from(keys)[0];
      incomingKeysWithEntries.add(first);
    }
  }

  // 包里出现过的全部名字：日记本定义 + 日记上挂的，按出现顺序去重。
  // 本机没有的名字也要进改写表：包里自己可能就有「Travel」和「travel」两种写法，导入后要并成一个
  const seen = new Set<string>();
  const incomingNames: string[] = [];
  for (const name of taxonomyNames) {
    if (!seen.has(name)) {
      seen.add(name);
      incomingNames.push(name);
    }
  }
  for (const be of incomingEntries) {
    for (const tag of be.tags) {
      if (!seen.has(tag)) {
        seen.add(tag);
        incomingNames.push(tag);
      }
    }
  }

  // 起新名字时要避开的：本机的日记本、本机日记上挂着的名字（含已删日记本留下的）、包里的全部名字
  const taken: string[] = [];
  for (const notebook of localNotebooks) {
    taken.push(notebook.name);
  }
  for (const entry of localEntries) {
    for (const tag of entry.tags) {
      taken.push(tag);
    }
  }
  for (const name of incomingNames) {
    taken.push(name);
  }

  const finalNameByKey = new Map<string, string>();
  for (const name of incomingNames) {
    const key = nameKey(name);
    const decided = finalNameByKey.get(key);
    if (decided !== undefined) {
      plan.rename.set(name, decided);
      continue;
    }
    let final = name;
    const local = localNameByKey.get(key);
    if (local !== undefined) {
      const conflicts = localKeysWithEntries.has(key) && incomingKeysWithEntries.has(key);
      if (conflicts) {
        plan.conflicts.push(name);
      }
      if (conflicts && policy === TagConflictPolicy.KeepSeparate) {
        final = uniqueName(name, taken);
        taken.push(final);
      } else {
        final = local;
      }
    }
    finalNameByKey.set(key, final);
    plan.rename.set(name, final);
  }
  return plan;
}

/** 日记上挂的日记本名字按计划改写，再按单本规则整理（多于一本退回「全部日记」） */
function renamedTags(tags: string[], plan: TagNamePlan): string[] {
  const renamed: string[] = [];
  for (const tag of tags) {
    renamed.push(plan.rename.get(tag) ?? tag);
  }
  return singleNotebook(renamed);
}

/**
 * 把包内 media/<name> 拷进沙箱，返回它在沙箱里的最终文件名（可能和包里不同）。源文件不存在返回 null。
 * - 同名同大小：就是同一个文件（多半是把自己的备份又导了一遍），复用不重复占空间
 * - 同名不同内容：照片名只取 UUID 前 8 位，跨库撞名并非不可能 —— 这时必须另起名字
 *   （photo_XXXX_1.jpg），否则日记会指到别人的照片上，比丢图还糟
 * - 同一个源文件被多篇日记引用时走缓存只拷一次
 */
function adoptMedia(name: string, mediaDir: string, destDir: string,
  cache: Map<string, string>): string | null {
  const safe = lastPathComponent(name);
  if (safe.length === 0 || safe === '.' || safe === '..') {
    return null;
  }
  const already = cache.get(safe);
  if (already !== undefined) {
    return already;
  }
  const source = `${mediaDir}/${safe}`;
  if (!fileExists(source)) {
    return null;
  }
  let finalName = safe;
  let dest = `${destDir}/${finalName}`;
  if (fileExists(dest)) {
    const sourceSize = fileSizeOf(source);
    if (sourceSize >= 0 && sourceSize === fileSizeOf(dest)) {
      cache.set(safe, finalName);
      return finalName;
    }
    const dot = safe.lastIndexOf('.');
    const base = dot > 0 ? safe.substring(0, dot) : safe;
    const ext = dot > 0 ? safe.substring(dot + 1) : '';
    let n = 1;
    do {
      finalName = ext.length > 0 ? `${base}_${n}.${ext}` : `${base}_${n}`;
      dest = `${destDir}/${finalName}`;
      n++;
    } while (fileExists(dest) && n < 100);
  }
  try {
    fileIo.copyFileSync(source, dest);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'adoptMedia copy failed %{public}s → %{public}s: %{public}s',
      source, dest, JSON.stringify(err));
    return null;
  }
  cache.set(safe, finalName);
  return finalName;
}

/**
 * 找到 manifest.json 所在的目录。
 * iOS 导出的包多套一层同名目录（尺素备份_20260812/manifest.json），
 * 手工打的包则可能是平的 —— 两种都得认：先看根目录，再看下一层。
 * macOS 打的 zip 会塞一个 __MACOSX 元数据目录，跳过。
 */
function findPackageRoot(directory: string): string | null {
  if (fileExists(`${directory}/${BackupFormat.manifestFile}`)) {
    return directory;
  }
  let names: string[] = [];
  try {
    names = fileIo.listFileSync(directory);
  } catch (err) {
    return null;
  }
  for (const name of names) {
    if (name.length === 0 || name.startsWith('.') || name === '__MACOSX') {
      continue;
    }
    const child = `${directory}/${name}`;
    try {
      if (!fileIo.statSync(child).isDirectory()) {
        continue;
      }
    } catch (err) {
      continue;
    }
    if (fileExists(`${child}/${BackupFormat.manifestFile}`)) {
      return child;
    }
  }
  return null;
}

// ---- 包内定位 / 宽松解码（文件不存在或整体解析失败都当「这部分没有」，不让一个坏文件毁掉整次导入） ----

function decodeEntriesFile(pkg: BackupPackage): BackupEntriesFile {
  const text = readTextFile(`${pkg.rootDir}/${BackupFormat.entriesFile}`);
  if (text === undefined) {
    return new BackupEntriesFile();
  }
  return parseBackupEntries(text) ?? new BackupEntriesFile();
}

function decodeTaxonomy(pkg: BackupPackage): BackupTagDto[] {
  const text = readTextFile(`${pkg.rootDir}/${BackupFormat.taxonomyFile}`);
  if (text === undefined) {
    return [];
  }
  return parseBackupTaxonomy(text) ?? [];
}

function decodeLetters(pkg: BackupPackage): BackupLetterDto[] {
  const text = readTextFile(`${pkg.rootDir}/${BackupFormat.lettersFile}`);
  if (text === undefined) {
    return [];
  }
  return parseBackupLetters(text) ?? [];
}

export class BackupImportService {
  /** 只读文件头判断加密（不解整包）。读不到按未加密（open 时会报 UnreadableFile） */
  static isEncryptedFile(filePath: string): boolean {
    const head = readHeadBytes(filePath, 16);
    if (head === undefined) {
      return false;
    }
    return BackupCrypto.isEncrypted(head);
  }

  // ---- 入口：外部 URI → 沙箱中转副本 ----

  /** 外部 URI 落进沙箱后的中转副本路径（cacheDir 下固定名，单份覆盖） */
  static intakePath(context: common.Context): string {
    return `${context.cacheDir}/${INTAKE_FILE_NAME}`;
  }

  /**
   * 选择器 / 文件关联给的是带临时读权限的 file:// URI，权限随时会失效 ——
   * 拿到后第一件事就是拷进沙箱固定位置，之后所有读取都走这份副本。
   * 文件名刻意不带 memoir-import- 前缀：sweepStaleStaging 不会把它当垃圾扫掉。
   */
  static async intakeExternalFile(context: common.Context, sourceUri: string): Promise<string> {
    const dest = BackupImportService.intakePath(context);
    if (fileExists(dest)) {
      removeTree(dest);
    }
    await fileIo.copy(sourceUri, fileUri.getUriFromPath(dest));
    return dest;
  }

  /**
   * 打开备份包但**先不写库** —— 让用户看清「这里面是什么、什么时候导出的」再决定导不导。
   * 成功后调用方有责任在用完（导入完成 / 取消 / 出错）时调 discard。
   */
  static async open(context: common.Context, filePath: string,
    password: string | undefined): Promise<BackupPackage> {
    const raw = readBytes(filePath);
    if (raw === undefined) {
      throw new BackupImportFailure(BackupImportError.UnreadableFile);
    }

    // 1. 解密（不加密的包就是纯 zip，直接用）
    let zipData: Uint8Array;
    if (BackupCrypto.isEncrypted(raw)) {
      if (password === undefined || password.length === 0) {
        throw new BackupImportFailure(BackupImportError.NeedsPassword);
      }
      try {
        zipData = await BackupCrypto.decrypt(raw, password);
      } catch (err) {
        if (err instanceof BackupCryptoFailure) {
          if (err.kind === BackupCryptoError.WrongPassword) {
            throw new BackupImportFailure(BackupImportError.WrongPassword);
          }
        }
        throw new BackupImportFailure(BackupImportError.NotABackup);
      }
    } else {
      zipData = raw;
    }

    // 2. 解压到独立的临时目录（UUID 命名，避免两次导入互相踩）。
    // 开工前先扫一遍上次没扫干净的：用户在导入面板开着时把 App 划掉，onDisappear 不会走，
    // 解压出来的东西（可能上百 MB）会一直留在 cache 里
    BackupImportService.sweepStaleStaging(context.cacheDir);
    const staging = `${context.cacheDir}/${STAGING_PREFIX}${generateUuid()}`;
    if (!ensureDir(staging)) {
      throw new BackupImportFailure(BackupImportError.StagingFailed, 0, 'mkdir staging failed');
    }
    const zipPath = `${staging}/payload.zip`;
    const extracted = `${staging}/package`;
    if (!ensureDir(extracted)) {
      removeTree(staging);
      throw new BackupImportFailure(BackupImportError.StagingFailed, 0, 'mkdir package failed');
    }
    if (!writeBytes(zipPath, zipData)) {
      removeTree(staging);
      throw new BackupImportFailure(BackupImportError.StagingFailed, 0, 'write payload.zip failed');
    }
    try {
      await zlib.decompressFile(zipPath, extracted);
    } catch (err) {
      removeTree(staging);
      hilog.error(DOMAIN, TAG, 'decompress failed: %{public}s', JSON.stringify(err));
      throw new BackupImportFailure(BackupImportError.NotABackup);
    }
    // 解压完 zip 本体就没用了，早点删省一份体积（大包时这一份可能就是上百 MB）
    try {
      fileIo.unlinkSync(zipPath);
    } catch (err) {
      // 删不掉只多占点临时空间，不挡导入
    }

    // 3. 找到 manifest.json 所在目录
    const root = findPackageRoot(extracted);
    if (root === null) {
      removeTree(staging);
      throw new BackupImportFailure(BackupImportError.NotABackup);
    }

    // 4. 读 manifest 并判版本
    const manifestText = readTextFile(`${root}/${BackupFormat.manifestFile}`);
    const manifest = manifestText !== undefined ? parseBackupManifest(manifestText) : undefined;
    if (manifest === undefined) {
      removeTree(staging);
      throw new BackupImportFailure(BackupImportError.NotABackup);
    }
    // §2.4 规则 1：版本比自己认识的新就直接拒绝，不做半吊子解析
    if (manifest.formatVersion > BackupFormat.currentVersion) {
      removeTree(staging);
      throw new BackupImportFailure(BackupImportError.UnsupportedVersion, manifest.formatVersion);
    }
    return new BackupPackage(manifest, root, staging);
  }

  /** 删掉解压出来的临时文件。导入完成、取消、出错都要调 */
  static discard(pkg: BackupPackage): void {
    removeTree(pkg.stagingDir);
  }

  /** 清掉历次没来得及删的解压目录 */
  static sweepStaleStaging(cacheDir: string): void {
    let names: string[] = [];
    try {
      names = fileIo.listFileSync(cacheDir);
    } catch (err) {
      return;
    }
    for (const name of names) {
      if (name.startsWith(STAGING_PREFIX)) {
        removeTree(`${cacheDir}/${name}`);
      }
    }
  }

  /** 需要问用户的同名日记本（返回包里的写法）。空数组 = 不用问，直接 Merge */
  static async tagConflicts(store: relationalStore.RdbStore,
    pkg: BackupPackage): Promise<string[]> {
    const entriesFile = decodeEntriesFile(pkg);
    const taxonomy = decodeTaxonomy(pkg);
    const taxonomyNames: string[] = [];
    for (const tag of taxonomy) {
      taxonomyNames.push(tag.name);
    }
    const localNotebooks = await BackupImportService.fetchLocalNotebooks(store);
    const localEntries = await BackupImportService.fetchLocalEntries(store);
    const plan = planTagNames(entriesFile.entries, taxonomyNames, localNotebooks,
      localEntries, TagConflictPolicy.Merge);
    return plan.conflicts;
  }

  /**
   * 按 id 合并进库。**已存在的一律跳过，不覆盖**。
   * tagPolicy 只影响 tagConflicts 报出来的那几本，其余同名日记本一律合并。
   */
  static async merge(context: common.Context, store: relationalStore.RdbStore,
    pkg: BackupPackage, tagPolicy: TagConflictPolicy): Promise<BackupImportSummary> {
    const summary = new BackupImportSummary();
    const entriesFile = decodeEntriesFile(pkg);
    const incomingEntries = entriesFile.entries;
    const taxonomy = decodeTaxonomy(pkg);
    const mediaDir = pkg.mediaDir();
    const photosDir = `${context.filesDir}/${PHOTO_DIR_NAME}`;
    const audioDir = `${context.filesDir}/${AUDIO_DIR_NAME}`;
    ensureDir(photosDir);
    ensureDir(audioDir);

    const localNotebooks = await BackupImportService.fetchLocalNotebooks(store);
    const localEntries = await BackupImportService.fetchLocalEntries(store);
    const plan = planTagNames(incomingEntries, taxonomy.map(tag => tag.name),
      localNotebooks, localEntries, tagPolicy);

    // 媒体文件在包内是扁平文件名，导入时可能因重名改名 —— 这两张表记住改成了什么，
    // 同一个源文件被多篇日记引用时也只拷一次
    const photoNames = new Map<string, string>();
    const audioNames = new Map<string, string>();

    // 1. 日记本。**按名字去重，不按 id**：journal_entry.tags 存的是名字字符串，名字才是身份。
    // 每台设备首启会各自生成一套默认日记本（id 各不相同），按 id 去重的话导入一次
    // 就多出一整套同名的「生活」「旅行」。
    const tagsByKey = new Map<string, Notebook>();
    const sortedNotebooks = localNotebooks.slice().sort((a, b) => a.createdAt - b.createdAt);
    for (const notebook of sortedNotebooks) {
      const key = nameKey(notebook.name);
      if (!tagsByKey.has(key)) {
        tagsByKey.set(key, notebook);
      }
    }
    const takenTagIds = new Set<string>();
    for (const notebook of localNotebooks) {
      takenTagIds.add(uuidKey(notebook.id));
    }
    let nextTagOrder = nextSortOrder(localNotebooks.map(notebook => notebook.sortOrder));
    for (const t of taxonomy) {
      const name = plan.rename.get(t.name) ?? t.name;
      const key = nameKey(name);
      const target = tagsByKey.get(key);
      if (target !== undefined) {
        // 并进本机已有的同名那本：本机缺什么补什么，已有的一律不动（封面 + 副标题）
        await BackupImportService.fillMissingCover(store, target, t, mediaDir,
          photosDir, photoNames);
        continue;
      }
      // 下架的颜色就近换成保留色；完全不认识的（更新版本加的）原样留着，渲染时 bookColor 兜底。
      // 纹理不读包里的：2026-10 起只有亚麻
      const retired = retiredColorReplacement(t.colorID);
      const notebook = new Notebook(
        takenTagIds.has(uuidKey(t.id)) ? generateUuid() : t.id,
        cleanedName(name), t.createdAtMs, t.createdAtMs);
      notebook.colorId = retired !== undefined ? retired : t.colorID;
      notebook.textureId = BookTexture.Linen;
      notebook.sortOrder = nextTagOrder;
      nextTagOrder++;
      // 照片封面：包里找不到文件就当没有封面（纯色），不算错、不阻断
      const cover = t.coverFile !== undefined
        ? adoptMedia(t.coverFile, mediaDir, photosDir, photoNames) : null;
      if (cover !== null) {
        notebook.coverPhotoFilename = cover;
        // 版式只跟着照片走；不认识的值（更新版本加的）原样留着，显示时按满版
        if (t.coverLayout !== undefined) {
          notebook.coverLayoutId = t.coverLayout;
        }
      }
      // 副标题：空 = 没有
      if (t.subtitle !== undefined && t.subtitle.length > 0) {
        notebook.subtitle = t.subtitle.substring(0, SUBTITLE_MAX_LENGTH);
      }
      await NotebookRepository.insertNotebook(store, notebook);
      tagsByKey.set(key, notebook);
      takenTagIds.add(uuidKey(notebook.id));
      summary.tagsImported++;
    }

    // 2. 日记
    const entriesById = new Map<string, JournalEntry>();
    for (const entry of localEntries) {
      entriesById.set(uuidKey(entry.id), entry);
    }
    for (const be of incomingEntries) {
      const idKey = uuidKey(be.id);
      const existing = entriesById.get(idKey);
      if (existing !== undefined) {
        summary.entriesSkipped++;
        continue;
      }
      const entry = new JournalEntry(be.id, be.dateMs, be.createdAtMs, be.updatedAtMs);
      entry.title = be.title;
      entry.isFavorite = be.isFavorite;
      entry.tags = renamedTags(be.tags, plan);
      // 旧心情标签：随包保字符串（mood 列仍在），不参与任何 UI
      entry.mood = be.mood;
      if (be.moodColorHex !== undefined) {
        entry.moodColorHex = be.moodColorHex;
      }
      // 写完时的心情：愉悦度夹在 -1…1；情绪词原样收（不认识的 key 留着，显示时跳过）
      if (be.moodValence !== undefined) {
        entry.moodValence = Math.min(1, Math.max(-1, be.moodValence));
      }
      if (be.moodLabels !== undefined) {
        entry.moodLabels = be.moodLabels;
      }
      entry.weatherCode = be.weatherCode;
      entry.weatherInfo = be.weatherInfo;
      entry.locationInfo = be.locationInfo;

      // 内容块。照片文件缺失时只丢这一块，日记其余部分照常导入（§2.4 规则 3）
      const blocks: ContentBlock[] = [];
      for (const bb of be.blocks) {
        if (bb.type === ContentBlockType.Text) {
          const block = ContentBlock.makeText(generateUuid(), bb.text ?? '');
          if (bb.styles !== undefined) {
            block.styles = bb.styles;
          }
          blocks.push(block);
        } else if (bb.type === ContentBlockType.Audio) {
          // 录音文件和下面 be.audio 清单是同一个，共用缓存，改了名两边一致。
          // 文件缺了只丢这个位置，不计缺失（清单那边会计一次）
          if (bb.file === undefined) {
            continue;
          }
          const local = adoptMedia(bb.file, mediaDir, audioDir, audioNames);
          if (local === null) {
            continue;
          }
          const audio = ContentBlock.makeAudio(generateUuid(), `${AUDIO_PREFIX}${local}`);
          if (bb.addedAt !== undefined) {
            audio.addedAt = bb.addedAt;
          }
          blocks.push(audio);
        } else if (bb.type === ContentBlockType.Trace) {
          // 痕迹不带文件，原样还原
          const traceOf = bb.traceOf !== undefined
            ? contentBlockTypeFromRaw(bb.traceOf) : undefined;
          const trace = ContentBlock.makeTrace(generateUuid(),
            traceOf ?? ContentBlockType.Photo,
            bb.removedAt !== undefined ? bb.removedAt : Date.now() / 1000);
          blocks.push(trace);
        } else if (bb.type === ContentBlockType.Photo) {
          if (bb.file === undefined) {
            summary.missingMedia++;
            continue;
          }
          const localName = adoptMedia(bb.file, mediaDir, photosDir, photoNames);
          if (localName === null) {
            summary.missingMedia++;
            continue;
          }
          // Live Photo 的视频部分丢了不算错 —— 降级成一张静态图即可，不计入缺失
          const live = bb.liveVideo !== undefined
            ? adoptMedia(bb.liveVideo, mediaDir, photosDir, photoNames) : null;
          const block = ContentBlock.makePhoto(generateUuid(), localName,
            live !== null ? live : undefined,
            bb.position !== undefined ? photoPositionFromRaw(bb.position) ?? PhotoPosition.Right
              : PhotoPosition.Right,
            bb.paperStyle !== undefined ? paperStyleFromRaw(bb.paperStyle) ?? PaperStyle.Original
              : PaperStyle.Original);
          // 相机拍的 Live Photo 带的未裁原图；缺了就退回用 file 配对（LivePhotoView 兜底显示静态图）
          if (bb.liveStill !== undefined) {
            const still = adoptMedia(bb.liveStill, mediaDir, photosDir, photoNames);
            if (still !== null) {
              block.livePhotoStillFilename = still;
            }
          }
          if (bb.rotationAngle !== undefined) {
            block.rotationAngle = bb.rotationAngle;
          }
          if (bb.isCover !== undefined) {
            block.isCover = bb.isCover;
          }
          if (bb.addedAt !== undefined) {
            block.addedAt = bb.addedAt;
          }
          blocks.push(block);
        } else {
          // 未来版本新增的块类型 —— 忽略，不阻断（§2.4 规则 2）
          continue;
        }
      }
      // setContentBlocks 会重算 content / wordCount / audioURLs，并把 updatedAt 抹成 now，
      // 所以时间戳在它之后恢复
      entry.setContentBlocks(blocks, Date.now());

      // 录音总清单（be.audio）。文件缺了计缺失，清单里不记
      const audioList: string[] = [];
      for (const name of be.audio) {
        const local = adoptMedia(name, mediaDir, audioDir, audioNames);
        if (local === null) {
          summary.missingMedia++;
          continue;
        }
        audioList.push(`${AUDIO_PREFIX}${local}`);
      }
      entry.audioURLs = audioList;

      // 时间戳恢复（setContentBlocks 把 updatedAt 抹掉了）
      entry.createdAt = be.createdAtMs;
      entry.updatedAt = be.updatedAtMs;

      await EntryRepository.insertEntry(store, entry);
      entriesById.set(idKey, entry);
      summary.entriesImported++;
    }

    // 3. 来信
    const existingLetters = await BackupImportService.fetchLocalLetters(store);
    const letterIds = new Set<string>();
    for (const letter of existingLetters) {
      letterIds.add(uuidKey(letter.id));
    }
    for (const bl of decodeLetters(pkg)) {
      const idKey = uuidKey(bl.id);
      if (letterIds.has(idKey)) {
        summary.lettersSkipped++;
        continue;
      }
      const letter = new Letter(bl.id, bl.generatedAtMs, bl.generatedAtMs);
      letter.body = bl.body;
      letter.fromCharacter = bl.fromCharacter;
      // 老包可能没有 toName / stationery → undefined（普通信纸）。火漆信导回来还是火漆信
      letter.toName = bl.toName;
      letter.stationery = bl.stationery;
      // status / triggerKind 存原始字符串而不过枚举：后端会新增取值，不该在导入时被抹掉
      letter.status = bl.status;
      letter.triggerKind = bl.triggerKind;
      if (bl.deliveredAtMs !== undefined) {
        letter.deliveredAt = bl.deliveredAtMs;
      }
      if (bl.readAtMs !== undefined) {
        letter.readAt = bl.readAtMs;
      }
      await LetterRepository.saveLetter(store, letter);
      // 关联日记：只连库里有的（含刚导入的）；找不到的忽略，不阻断导入
      const linkedIds: string[] = [];
      for (const entryId of bl.relatedEntryIDs) {
        const target = entriesById.get(uuidKey(entryId));
        if (target !== undefined) {
          linkedIds.push(target.id);
        }
      }
      if (linkedIds.length > 0) {
        await LetterRepository.linkLetterEntries(store, letter.id, linkedIds);
      }
      letterIds.add(idKey);
      summary.lettersImported++;
    }

    // 4. 最长连续写作：包里的和本机的取大的（只升不降），再用合并后的全部日记算一次
    const packageDays = entriesFile.bestStreakDays;
    if (packageDays !== undefined && packageDays > 0) {
      const recorded = AppPrefs.recordedBestStreakDays();
      AppPrefs.setRecordedBestStreakDays(WritingStreak.raisedValue(recorded, packageDays));
    }
    try {
      const dates: number[] = [];
      const result = await store.querySql('SELECT date FROM journal_entry');
      try {
        while (result.goToNextRow()) {
          dates.push(result.getLong(0));
        }
      } finally {
        result.close();
      }
      const recorded = AppPrefs.recordedBestStreakDays();
      const best = WritingStreak.best(recorded, dates);
      if (best > recorded) {
        AppPrefs.setRecordedBestStreakDays(best);
      }
    } catch (err) {
      // 只是统计，失败不挡导入
      hilog.warn(DOMAIN, TAG, 'recompute streak after import failed: %{public}s', JSON.stringify(err));
    }
    return summary;
  }

  /**
   * 包里的日记本并进本机已有的同名那本时：本机缺什么补什么，已有的一律不动。
   * 封面照片和版式是一套（本机没有照片封面才把包里的整套带过来）；副标题单独看；
   * 颜色、书架位置、名字的写法都按本机的。直写 SQL：coverLayout 要原样保留
   * 不认识的字符串，updateCover 只收枚举
   */
  private static async fillMissingCover(store: relationalStore.RdbStore, target: Notebook,
    incoming: BackupTagDto, mediaDir: string, photosDir: string,
    photoNames: Map<string, string>): Promise<void> {
    const hasCover = target.coverPhotoFilename !== undefined && target.coverPhotoFilename.length > 0;
    if (!hasCover && incoming.coverFile !== undefined) {
      const adopted = adoptMedia(incoming.coverFile, mediaDir, photosDir, photoNames);
      if (adopted !== null) {
        try {
          await store.executeSql(
            'UPDATE notebook SET cover_photo_filename = ?, cover_layout_id = ? WHERE id = ?',
            [adopted, incoming.coverLayout ?? null, target.id]);
          target.coverPhotoFilename = adopted;
          if (incoming.coverLayout !== undefined) {
            target.coverLayoutId = incoming.coverLayout;
          }
        } catch (err) {
          hilog.error(DOMAIN, TAG, 'fillMissingCover update failed: %{public}s', JSON.stringify(err));
        }
      }
    }
    const hasSubtitle = target.subtitle !== undefined && target.subtitle.length > 0;
    if (!hasSubtitle && incoming.subtitle !== undefined && incoming.subtitle.length > 0) {
      const subtitle = incoming.subtitle.substring(0, SUBTITLE_MAX_LENGTH);
      try {
        await store.executeSql('UPDATE notebook SET subtitle = ? WHERE id = ?',
          [subtitle, target.id]);
        target.subtitle = subtitle;
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'fillMissingCover subtitle failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  // ---- 读库（读失败按空处理，对齐 iOS try? ?? []：不让一个坏查询毁掉整次导入） ----

  private static async fetchLocalNotebooks(store: relationalStore.RdbStore): Promise<Notebook[]> {
    try {
      return await NotebookRepository.fetchAllNotebooks(store);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'fetch local notebooks failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  private static async fetchLocalEntries(store: relationalStore.RdbStore): Promise<JournalEntry[]> {
    try {
      return await EntryRepository.fetchAllEntries(store);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'fetch local entries failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  private static async fetchLocalLetters(store: relationalStore.RdbStore): Promise<Letter[]> {
    try {
      return await LetterRepository.listLetters(store);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'fetch local letters failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }
}
