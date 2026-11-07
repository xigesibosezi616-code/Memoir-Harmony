/**
 * 备份包的数据格式定义（6.4 / 6.5；08_backup_package.md §3、iOS `Services/Backup/BackupFormat.swift`）。
 *
 * - **跨端契约**：字段名、类型、语义以 iOS `Docs/EXPORT_FORMAT.md` 为准；破坏性变更才升
 *   `formatVersion`，新增可选字段不算。改这里必须同步改那两处
 * - **导入逐条容错**（08 §2.4「宁可残缺也不要整包失败」）：坏 JSON / 缺必填字段的条目只丢
 *   那一条；只有 manifest.json 整个读不出才整包拒收。这比 iOS 的 Codable 整体解码更宽容，
 *   是文档明确要求的行为
 * - **日期**：包里一律 ISO8601 无毫秒（iOS `JSONEncoder` `.iso8601`）；解析时带毫秒的也认。
 *   墨迹时间（addedAt 等）是 Unix 秒（浮点），与模型层约定一致，两者别混
 * - **导出侧 wire 类**字段名与 iOS 完全一致。老版本 iOS 把 `mood` / `moods` / `blocks` /
 *   `counts` 等当必填读，这些「作废字段」必须写空值（"" / []），删了老包就读不进去
 * - moodSummaries（会员情绪小结）、penPalNotes（笔友手记）：鸿蒙侧没有对应模型，**静默跳过**
 */
import { TextStyleRun, decodeStyleRun } from '../../models/ContentBlock';

// ---- 常量（iOS `BackupFormat` 同名同值） ----

export class BackupFormat {
  /** 结构版本。只有破坏性变更才 +1；新增可选字段不算 */
  static readonly currentVersion: number = 1;
  static readonly manifestFile: string = 'manifest.json';
  static readonly entriesFile: string = 'entries.json';
  static readonly lettersFile: string = 'letters.json';
  static readonly taxonomyFile: string = 'taxonomy.json';
  static readonly mediaDirectory: string = 'media';
  /** 未加密时文件本身就是标准 zip，用户改名 .zip 即可打开检视 */
  static readonly fileExtension: string = 'memoir';
  /**
   * 鸿蒙侧自定义 UTD 类型 ID（6.4 文件关联「用尺素打开 .memoir」）。
   * 与 rawfile/arkdata/utd/utd.json5 的 TypeId、module.json5 skills 里的 type 必须一致。
   */
  static readonly utdTypeId: string = 'com.sinaratech.memoir.hmos.memoir';
}

// ---- 日期工具（ISO8601 无毫秒；解析放宽两种都认） ----

/** 毫秒时间戳 → 包里的 ISO8601 字符串（去毫秒，如 `2026-08-12T09:30:06Z`） */
export function toBackupIso8601(ms: number): string {
  const iso = new Date(ms).toISOString(); // 总是带 .sssZ
  return `${iso.split('.')[0]}Z`;
}

/** 包里的 ISO8601 字符串 → 毫秒时间戳。带不带毫秒都认；坏字符串返回 undefined */
export function parseBackupIso8601(raw: string): number | undefined {
  const t = Date.parse(raw);
  return Number.isNaN(t) ? undefined : t;
}

// ---- 字段取值辅助（Record 容错取值；解析全走这里，不做动态属性访问之外的事） ----

function fieldString(rec: Record<string, Object>, key: string): string | undefined {
  const v: Object | undefined = rec[key];
  return typeof v === 'string' ? v : undefined;
}

function fieldNumber(rec: Record<string, Object>, key: string): number | undefined {
  const v: Object | undefined = rec[key];
  return typeof v === 'number' ? v : undefined;
}

function fieldBoolean(rec: Record<string, Object>, key: string): boolean | undefined {
  const v: Object | undefined = rec[key];
  return typeof v === 'boolean' ? v : undefined;
}

/** string[] 字段：不是数组 / 混入非字符串 → 只丢坏项；缺字段返回 undefined */
function fieldStringArray(rec: Record<string, Object>, key: string): string[] | undefined {
  const v: Object | undefined = rec[key];
  if (v === undefined || !Array.isArray(v)) {
    return undefined;
  }
  const items = v as Object[];
  const result: string[] = [];
  for (const item of items) {
    if (typeof item === 'string') {
      result.push(item);
    }
  }
  return result;
}

/** 顶层 JSON 对象解析：坏 JSON / 不是对象返回 undefined */
function parseJsonObject(json: string): Record<string, Object> | undefined {
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(json);
  } catch (err) {
    return undefined;
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return undefined;
  }
  return parsed as Record<string, Object>;
}

// ---- manifest.json ----

export class BackupManifestCounts {
  entries: number = 0;
  letters: number = 0;
  media: number = 0;
}

export class BackupManifest {
  /** 唯一必须可信的字段（决定敢不敢解析）；缺失按 1（iOS 同款兜底） */
  formatVersion: number = 1;
  app: string = 'memoir';
  appVersion: string = '';
  platform: string = 'unknown';
  /** 导出时刻（毫秒）；缺失按 0 */
  exportedAtMs: number = 0;
  counts: BackupManifestCounts = new BackupManifestCounts();
  /** 「仅文字」导出时为 false，media/ 目录不存在 */
  includesMedia: boolean = true;
  mediaTotalBytes: number = 0;
  /** 明文标记：导入端在解密前就知道要不要问密码 */
  encrypted: boolean = false;
}

/** 解析 manifest.json。除 formatVersion 外全部按缺省值兜底（iOS 手写 init(from:) 同款） */
export function parseBackupManifest(json: string): BackupManifest | undefined {
  const rec = parseJsonObject(json);
  if (rec === undefined) {
    return undefined;
  }
  const manifest = new BackupManifest();
  const formatVersion = fieldNumber(rec, 'formatVersion');
  manifest.formatVersion = formatVersion !== undefined ? Math.trunc(formatVersion) : 1;
  const app = fieldString(rec, 'app');
  if (app !== undefined) {
    manifest.app = app;
  }
  const appVersion = fieldString(rec, 'appVersion');
  if (appVersion !== undefined) {
    manifest.appVersion = appVersion;
  }
  const platform = fieldString(rec, 'platform');
  if (platform !== undefined) {
    manifest.platform = platform;
  }
  const exportedAt = fieldString(rec, 'exportedAt');
  const exportedAtMs = exportedAt !== undefined ? parseBackupIso8601(exportedAt) : undefined;
  if (exportedAtMs !== undefined) {
    manifest.exportedAtMs = exportedAtMs;
  }
  const countsRaw: Object | undefined = rec['counts'];
  if (countsRaw !== undefined && typeof countsRaw === 'object' && !Array.isArray(countsRaw)) {
    const c = countsRaw as Record<string, Object>;
    const entries = fieldNumber(c, 'entries');
    if (entries !== undefined) {
      manifest.counts.entries = Math.trunc(entries);
    }
    const letters = fieldNumber(c, 'letters');
    if (letters !== undefined) {
      manifest.counts.letters = Math.trunc(letters);
    }
    const media = fieldNumber(c, 'media');
    if (media !== undefined) {
      manifest.counts.media = Math.trunc(media);
    }
  }
  const includesMedia = fieldBoolean(rec, 'includesMedia');
  if (includesMedia !== undefined) {
    manifest.includesMedia = includesMedia;
  }
  const mediaTotalBytes = fieldNumber(rec, 'mediaTotalBytes');
  if (mediaTotalBytes !== undefined) {
    manifest.mediaTotalBytes = Math.trunc(mediaTotalBytes);
  }
  const encrypted = fieldBoolean(rec, 'encrypted');
  if (encrypted !== undefined) {
    manifest.encrypted = encrypted;
  }
  return manifest;
}

// ---- entries.json ----

/**
 * 内容块的包内形态。type 之外的字段按块类型取用；file / liveVideo / liveStill 是
 * media/ 内的文件名。paperStyle / position / traceOf 原样存字符串（可能有不认识的值）
 */
export class BackupBlockDto {
  type: string = '';
  text?: string;
  styles?: TextStyleRun[];
  file?: string;
  liveVideo?: string;
  liveStill?: string;
  paperStyle?: string;
  position?: string;
  rotationAngle?: number;
  isCover?: boolean;
  addedAt?: number;
  traceOf?: string;
  removedAt?: number;
}

/** 一篇日记的包内形态。日期全换算成毫秒；audio 是 media/ 内的文件名清单 */
export class BackupEntryDto {
  id: string = '';
  title: string = '';
  dateMs: number = 0;
  createdAtMs: number = 0;
  updatedAtMs: number = 0;
  /** ⚠️ 作废字段（旧心情标签）：随包来回带，导入时只是保字符串，不参与任何 UI */
  mood: string = '';
  moodColorHex?: string;
  tags: string[] = [];
  isFavorite: boolean = false;
  weatherCode?: string;
  weatherInfo?: string;
  locationInfo?: string;
  audio: string[] = [];
  moodValence?: number;
  moodLabels?: string[];
  blocks: BackupBlockDto[] = [];
}

/** entries.json 的解析结果：条目 + 顶层 writingStats.bestStreakDays（可选，U16） */
export class BackupEntriesFile {
  entries: BackupEntryDto[] = [];
  /** 包里记下的最长连续写作天数；没有该字段 = undefined（不算 0） */
  bestStreakDays: number | undefined = undefined;
}

function parseBlockDto(raw: Object): BackupBlockDto | undefined {
  const rec = raw as Record<string, Object>;
  const type = fieldString(rec, 'type');
  if (type === undefined) {
    return undefined;
  }
  const block = new BackupBlockDto();
  block.type = type;
  const text = fieldString(rec, 'text');
  if (text !== undefined) {
    block.text = text;
  }
  const file = fieldString(rec, 'file');
  if (file !== undefined) {
    block.file = file;
  }
  const liveVideo = fieldString(rec, 'liveVideo');
  if (liveVideo !== undefined) {
    block.liveVideo = liveVideo;
  }
  const liveStill = fieldString(rec, 'liveStill');
  if (liveStill !== undefined) {
    block.liveStill = liveStill;
  }
  const paperStyle = fieldString(rec, 'paperStyle');
  if (paperStyle !== undefined) {
    block.paperStyle = paperStyle;
  }
  const position = fieldString(rec, 'position');
  if (position !== undefined) {
    block.position = position;
  }
  const rotationAngle = fieldNumber(rec, 'rotationAngle');
  if (rotationAngle !== undefined) {
    block.rotationAngle = rotationAngle;
  }
  const isCover = fieldBoolean(rec, 'isCover');
  if (isCover !== undefined) {
    block.isCover = isCover;
  }
  const addedAt = fieldNumber(rec, 'addedAt');
  if (addedAt !== undefined) {
    block.addedAt = addedAt;
  }
  const traceOf = fieldString(rec, 'traceOf');
  if (traceOf !== undefined) {
    block.traceOf = traceOf;
  }
  const removedAt = fieldNumber(rec, 'removedAt');
  if (removedAt !== undefined) {
    block.removedAt = removedAt;
  }
  const stylesRaw: Object | undefined = rec['styles'];
  if (stylesRaw !== undefined && Array.isArray(stylesRaw)) {
    const styles: TextStyleRun[] = [];
    const rawRuns = stylesRaw as Object[];
    for (const rawRun of rawRuns) {
      const run = decodeStyleRun(rawRun);
      if (run !== undefined) {
        styles.push(run);
      }
    }
    block.styles = styles;
  }
  return block;
}

function parseEntryDto(raw: Object): BackupEntryDto | undefined {
  const rec = raw as Record<string, Object>;
  const id = fieldString(rec, 'id');
  const title = fieldString(rec, 'title');
  const dateRaw = fieldString(rec, 'date');
  const createdAtRaw = fieldString(rec, 'createdAt');
  const updatedAtRaw = fieldString(rec, 'updatedAt');
  if (id === undefined || id.length === 0 || title === undefined || dateRaw === undefined ||
    createdAtRaw === undefined || updatedAtRaw === undefined) {
    return undefined;
  }
  const dateMs = parseBackupIso8601(dateRaw);
  const createdAtMs = parseBackupIso8601(createdAtRaw);
  const updatedAtMs = parseBackupIso8601(updatedAtRaw);
  if (dateMs === undefined || createdAtMs === undefined || updatedAtMs === undefined) {
    return undefined;
  }
  const entry = new BackupEntryDto();
  entry.id = id;
  entry.title = title;
  entry.dateMs = dateMs;
  entry.createdAtMs = createdAtMs;
  entry.updatedAtMs = updatedAtMs;
  const mood = fieldString(rec, 'mood');
  if (mood !== undefined) {
    entry.mood = mood;
  }
  const moodColorHex = fieldString(rec, 'moodColorHex');
  if (moodColorHex !== undefined) {
    entry.moodColorHex = moodColorHex;
  }
  const tags = fieldStringArray(rec, 'tags');
  if (tags !== undefined) {
    entry.tags = tags;
  }
  const isFavorite = fieldBoolean(rec, 'isFavorite');
  if (isFavorite !== undefined) {
    entry.isFavorite = isFavorite;
  }
  const weatherCode = fieldString(rec, 'weatherCode');
  if (weatherCode !== undefined) {
    entry.weatherCode = weatherCode;
  }
  const weatherInfo = fieldString(rec, 'weatherInfo');
  if (weatherInfo !== undefined) {
    entry.weatherInfo = weatherInfo;
  }
  const locationInfo = fieldString(rec, 'locationInfo');
  if (locationInfo !== undefined) {
    entry.locationInfo = locationInfo;
  }
  const audio = fieldStringArray(rec, 'audio');
  if (audio !== undefined) {
    entry.audio = audio;
  }
  const moodValence = fieldNumber(rec, 'moodValence');
  if (moodValence !== undefined) {
    entry.moodValence = moodValence;
  }
  const moodLabels = fieldStringArray(rec, 'moodLabels');
  if (moodLabels !== undefined) {
    entry.moodLabels = moodLabels;
  }
  const blocksRaw: Object | undefined = rec['blocks'];
  if (blocksRaw !== undefined && Array.isArray(blocksRaw)) {
    const blocks: BackupBlockDto[] = [];
    const rawBlocks = blocksRaw as Object[];
    for (const rawBlock of rawBlocks) {
      const block = parseBlockDto(rawBlock);
      if (block !== undefined) {
        blocks.push(block);
      }
    }
    entry.blocks = blocks;
  }
  return entry;
}

/** 解析 entries.json。entries 字段坏了返回 undefined（整包拒收）；单条坏只丢那一条 */
export function parseBackupEntries(json: string): BackupEntriesFile | undefined {
  const rec = parseJsonObject(json);
  if (rec === undefined) {
    return undefined;
  }
  const result = new BackupEntriesFile();
  const entriesRaw: Object | undefined = rec['entries'];
  if (entriesRaw === undefined || !Array.isArray(entriesRaw)) {
    return undefined;
  }
  const rawEntries = entriesRaw as Object[];
  for (const raw of rawEntries) {
    const entry = parseEntryDto(raw);
    if (entry !== undefined) {
      result.entries.push(entry);
    }
  }
  // 顶层 writingStats.bestStreakDays（U16，可选）：坏值当没有
  const statsRaw: Object | undefined = rec['writingStats'];
  if (statsRaw !== undefined && typeof statsRaw === 'object' && !Array.isArray(statsRaw)) {
    const stats = statsRaw as Record<string, Object>;
    const best = fieldNumber(stats, 'bestStreakDays');
    if (best !== undefined && best >= 0 && Number.isInteger(best)) {
      result.bestStreakDays = Math.trunc(best);
    }
  }
  return result;
}

// ---- letters.json ----

/** 一封来信的包内形态。日期全换算成毫秒；status / triggerKind / stationery 原样存字符串 */
export class BackupLetterDto {
  id: string = '';
  body: string = '';
  fromCharacter: string = '青鸟';
  toName?: string;
  stationery?: string;
  status: string = 'pending';
  triggerKind: string = 'weekly';
  /** 寄出时刻（= 回信写好的时刻） */
  generatedAtMs: number = 0;
  /** 到达时刻。在路上的信是未来时间——导入后到点才出现在信箱里，这是对的，不要修正 */
  deliveredAtMs?: number;
  readAtMs?: number;
  relatedEntryIDs: string[] = [];
}

function parseLetterDto(raw: Object): BackupLetterDto | undefined {
  const rec = raw as Record<string, Object>;
  const id = fieldString(rec, 'id');
  const generatedAtRaw = fieldString(rec, 'generatedAt');
  if (id === undefined || id.length === 0 || generatedAtRaw === undefined) {
    return undefined;
  }
  const generatedAtMs = parseBackupIso8601(generatedAtRaw);
  if (generatedAtMs === undefined) {
    return undefined;
  }
  const letter = new BackupLetterDto();
  letter.id = id;
  letter.generatedAtMs = generatedAtMs;
  const body = fieldString(rec, 'body');
  if (body !== undefined) {
    letter.body = body;
  }
  const fromCharacter = fieldString(rec, 'fromCharacter');
  if (fromCharacter !== undefined) {
    letter.fromCharacter = fromCharacter;
  }
  const toName = fieldString(rec, 'toName');
  if (toName !== undefined) {
    letter.toName = toName;
  }
  const stationery = fieldString(rec, 'stationery');
  if (stationery !== undefined) {
    letter.stationery = stationery;
  }
  const status = fieldString(rec, 'status');
  if (status !== undefined) {
    letter.status = status;
  }
  const triggerKind = fieldString(rec, 'triggerKind');
  if (triggerKind !== undefined) {
    letter.triggerKind = triggerKind;
  }
  const deliveredAtRaw = fieldString(rec, 'deliveredAt');
  if (deliveredAtRaw !== undefined) {
    const deliveredAtMs = parseBackupIso8601(deliveredAtRaw);
    if (deliveredAtMs !== undefined) {
      letter.deliveredAtMs = deliveredAtMs;
    }
  }
  const readAtRaw = fieldString(rec, 'readAt');
  if (readAtRaw !== undefined) {
    const readAtMs = parseBackupIso8601(readAtRaw);
    if (readAtMs !== undefined) {
      letter.readAtMs = readAtMs;
    }
  }
  const relatedEntryIDs = fieldStringArray(rec, 'relatedEntryIDs');
  if (relatedEntryIDs !== undefined) {
    letter.relatedEntryIDs = relatedEntryIDs;
  }
  return letter;
}

/** 解析 letters.json。文件整个坏了返回 undefined；缺 letters 字段按空算（老包兼容） */
export function parseBackupLetters(json: string): BackupLetterDto[] | undefined {
  const rec = parseJsonObject(json);
  if (rec === undefined) {
    return undefined;
  }
  const lettersRaw: Object | undefined = rec['letters'];
  if (lettersRaw === undefined) {
    return [];
  }
  if (!Array.isArray(lettersRaw)) {
    return undefined;
  }
  const result: BackupLetterDto[] = [];
  const rawLetters = lettersRaw as Object[];
  for (const raw of rawLetters) {
    const letter = parseLetterDto(raw);
    if (letter !== undefined) {
      result.push(letter);
    }
  }
  return result;
}

// ---- taxonomy.json ----

/** 一本日记本的包内形态（iOS 的 BackupTag：鸿蒙的 Notebook 就是 iOS 的 Tag） */
export class BackupTagDto {
  id: string = '';
  name: string = '';
  colorID: string = 'WineRed';
  textureID: string = 'Leather';
  createdAtMs: number = 0;
  /** 照片封面，media/ 内的文件名。缺失 = 纯色封面 */
  coverFile?: string;
  /** 封面版式：FullBleed / Framed / TipIn。缺失或不认识按满版 */
  coverLayout?: string;
  /** 副标题。缺失 = 没有 */
  subtitle?: string;
}

function parseTagDto(raw: Object): BackupTagDto | undefined {
  const rec = raw as Record<string, Object>;
  const id = fieldString(rec, 'id');
  const name = fieldString(rec, 'name');
  if (id === undefined || id.length === 0 || name === undefined || name.trim().length === 0) {
    return undefined;
  }
  const tag = new BackupTagDto();
  tag.id = id;
  tag.name = name;
  const colorID = fieldString(rec, 'colorID');
  if (colorID !== undefined) {
    tag.colorID = colorID;
  }
  const textureID = fieldString(rec, 'textureID');
  if (textureID !== undefined) {
    tag.textureID = textureID;
  }
  const createdAtRaw = fieldString(rec, 'createdAt');
  if (createdAtRaw !== undefined) {
    const createdAtMs = parseBackupIso8601(createdAtRaw);
    if (createdAtMs !== undefined) {
      tag.createdAtMs = createdAtMs;
    }
  }
  const coverFile = fieldString(rec, 'coverFile');
  if (coverFile !== undefined) {
    tag.coverFile = coverFile;
  }
  const coverLayout = fieldString(rec, 'coverLayout');
  if (coverLayout !== undefined) {
    tag.coverLayout = coverLayout;
  }
  const subtitle = fieldString(rec, 'subtitle');
  if (subtitle !== undefined) {
    tag.subtitle = subtitle;
  }
  return tag;
}

/** 解析 taxonomy.json。只取 tags（moods 已作废，忽略）；坏文件返回 undefined */
export function parseBackupTaxonomy(json: string): BackupTagDto[] | undefined {
  const rec = parseJsonObject(json);
  if (rec === undefined) {
    return undefined;
  }
  const tagsRaw: Object | undefined = rec['tags'];
  if (tagsRaw === undefined) {
    return [];
  }
  if (!Array.isArray(tagsRaw)) {
    return undefined;
  }
  const result: BackupTagDto[] = [];
  const rawTags = tagsRaw as Object[];
  for (const raw of rawTags) {
    const tag = parseTagDto(raw);
    if (tag !== undefined) {
      result.push(tag);
    }
  }
  return result;
}

// ---- 导出侧 wire 类（字段名与 iOS 编码完全一致；undefined 的可选字段 JSON.stringify 自动省略） ----

export class ManifestCountsWire {
  entries: number = 0;
  letters: number = 0;
  media: number = 0;
}

export class ManifestWire {
  formatVersion: number = BackupFormat.currentVersion;
  app: string = 'memoir';
  appVersion: string = '';
  platform: string = 'harmony';
  exportedAt: string = '';
  counts: ManifestCountsWire = new ManifestCountsWire();
  includesMedia: boolean = true;
  mediaTotalBytes: number = 0;
  encrypted: boolean = false;
}

export class BlockWire {
  type: string = '';
  text?: string;
  styles?: TextStyleRun[];
  file?: string;
  liveVideo?: string;
  liveStill?: string;
  paperStyle?: string;
  position?: string;
  rotationAngle?: number;
  isCover?: boolean;
  addedAt?: number;
  traceOf?: string;
  removedAt?: number;
}

export class EntryWire {
  id: string = '';
  title: string = '';
  date: string = '';
  createdAt: string = '';
  updatedAt: string = '';
  /** 作废字段：写 ""（老版本 iOS 当必填读） */
  mood: string = '';
  moodColorHex?: string;
  tags: string[] = [];
  isFavorite: boolean = false;
  weatherCode?: string;
  weatherInfo?: string;
  locationInfo?: string;
  audio: string[] = [];
  moodValence?: number;
  moodLabels?: string[];
  blocks: BlockWire[] = [];
}

export class WritingStatsWire {
  bestStreakDays: number = 0;
}

export class EntriesWire {
  entries: EntryWire[] = [];
  writingStats?: WritingStatsWire;
}

export class LetterWire {
  id: string = '';
  body: string = '';
  fromCharacter: string = '';
  toName?: string;
  stationery?: string;
  status: string = '';
  triggerKind: string = '';
  generatedAt: string = '';
  deliveredAt?: string;
  readAt?: string;
  relatedEntryIDs: string[] = [];
}

export class LettersWire {
  letters: LetterWire[] = [];
}

export class TagWire {
  id: string = '';
  name: string = '';
  colorID: string = '';
  textureID: string = '';
  createdAt: string = '';
  coverFile?: string;
  coverLayout?: string;
  subtitle?: string;
}

/** 作废的旧心情标签：导出写空数组（老版本 iOS 当必填读），导入忽略 */
export class MoodWire {
  id: string = '';
  name: string = '';
  colorHex: string = '';
  isDefault: boolean = false;
  sortOrder: number = 0;
  iconName?: string;
  createdAt: string = '';
}

export class TaxonomyWire {
  tags: TagWire[] = [];
  moods: MoodWire[] = [];
}
