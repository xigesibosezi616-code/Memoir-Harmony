/**
 * 日记正文的内容块（05_DATA_MODEL.md §3）。对应 iOS `Models/ContentBlock.swift`。
 *
 * 正文 = `ContentBlock[]`，按数组顺序排版，JSON 存在日记的 `contentBlocksData` 一列里。
 *
 * - **解析逐块容错**：认不出的 `type` 跳过该块、字段坏了跳过该块 / 该段样式，
 *   绝不让整篇失败（05 §3；鸿蒙侧比 iOS 的 Codable 整体解码更宽容，这是文档要求）
 * - 墨迹时间（writtenAt / struckAt / addedAt / removedAt）一律 **Unix 秒**（浮点数），
 *   与 iOS、备份包同单位；日记的 date / createdAt / updatedAt 是毫秒（建表约定），两者别混
 * - 字符串区间（TextStyleRun、文本操作）一律 **UTF-16** 偏移与长度（与 NSString、ArkTS 一致）
 */
export enum ContentBlockType {
  Text = 'text',
  Photo = 'photo',
  Audio = 'audio',
  Trace = 'trace'
}

/** 照片在正文中的位置（左 / 右，不支持居中） */
export enum PhotoPosition {
  Left = 'left',
  Right = 'right'
}

/** 六种相纸样式（05 §3.5；会员判定见 7.2 的 MembershipRules） */
export enum PaperStyle {
  Original = 'original',
  Polaroid = 'polaroid',
  WashiSticker = 'washiSticker',
  MinimalCard = 'minimalCard',
  FilmFrame = 'filmFrame',
  LetterAttached = 'letterAttached'
}

/** 每篇正文照片上限（05 §3.6，iOS `canInsertPaperPhoto` 同款 5 张） */
export const PHOTO_LIMIT_PER_ENTRY: number = 5;

export function contentBlockTypeFromRaw(raw: string): ContentBlockType | undefined {
  switch (raw) {
    case 'text': return ContentBlockType.Text;
    case 'photo': return ContentBlockType.Photo;
    case 'audio': return ContentBlockType.Audio;
    case 'trace': return ContentBlockType.Trace;
    default: return undefined;
  }
}

export function photoPositionFromRaw(raw: string): PhotoPosition | undefined {
  switch (raw) {
    case 'left': return PhotoPosition.Left;
    case 'right': return PhotoPosition.Right;
    default: return undefined;
  }
}

export function paperStyleFromRaw(raw: string): PaperStyle | undefined {
  switch (raw) {
    case 'original': return PaperStyle.Original;
    case 'polaroid': return PaperStyle.Polaroid;
    case 'washiSticker': return PaperStyle.WashiSticker;
    case 'minimalCard': return PaperStyle.MinimalCard;
    case 'filmFrame': return PaperStyle.FilmFrame;
    case 'letterAttached': return PaperStyle.LetterAttached;
    default: return undefined;
  }
}

/** 相纸是不是会员款（05 §3.5：原图 / 宝丽来免费，其余四种会员） */
export function isMemberPaperStyle(style: PaperStyle): boolean {
  return style === PaperStyle.WashiSticker || style === PaperStyle.MinimalCard ||
    style === PaperStyle.FilmFrame || style === PaperStyle.LetterAttached;
}

/**
 * 实际渲染用的相纸（05 §3.5）：存的是会员款而当前不是会员 → 按宝丽来渲染，
 * **存的值不改写**。`isMember` 由 7.2 的会员判定接上；2.6 先全放开（判定恒放开）。
 */
export function effectivePaperStyle(style: PaperStyle, isMember: boolean): PaperStyle {
  if (!isMember && isMemberPaperStyle(style)) {
    return PaperStyle.Polaroid;
  }
  return style;
}

/** 两个 Unix 秒是否本地日历同一天（补记判定用；时区取设备本地） */
export function isSameLocalDay(aSeconds: number, bSeconds: number): boolean {
  const a = new Date(aSeconds * 1000);
  const b = new Date(bSeconds * 1000);
  return a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate();
}

/**
 * 墨迹会干（05 §3.4；交互见 06_RULES.md R-INK）。对应 iOS `ContentBlock.swift` 里的 `enum Ink`。
 * 时间一律 Unix 秒。
 */
export class Ink {
  /** 墨迹多久变干：24 小时 */
  static readonly dryingInterval: number = 24 * 60 * 60;

  /**
   * `writtenAt`（没有就用日记写下的时刻 `base`）过了 24 小时就是干的。
   * 两者都没有（还在写的新稿）一律不干。`now` 可注入，单测跑穿多天。
   */
  static isDry(writtenAt: number | undefined, base: number | undefined, now: number): boolean {
    const written = writtenAt !== undefined ? writtenAt : base;
    if (written === undefined) {
      return false;
    }
    return now - written >= Ink.dryingInterval;
  }

  /** 是不是「补记」：写的那天和日记写下的那天（本地日历）不是同一天 */
  static isAddendum(writtenAt: number | undefined, base: number | undefined): boolean {
    if (writtenAt === undefined || base === undefined) {
      return false;
    }
    return !isSameLocalDay(writtenAt, base);
  }
}

/** 一段文字的格式（05 §3.3）。区间按 UTF-16 计，相对所在文本块的 `text`。 */
export class TextStyleRun {
  location: number;
  length: number;
  bold?: boolean;
  italic?: boolean;
  /** 小标题（整段格式，区间覆盖整段） */
  heading?: boolean;
  /** 荧光笔 */
  highlight?: boolean;
  /** 这段字什么时候写的（Unix 秒）。没写 = 日记写下时就有 */
  writtenAt?: number;
  /** 什么时候划掉的（Unix 秒）。没划掉 = undefined */
  struckAt?: number;

  constructor(location: number, length: number) {
    this.location = location;
    this.length = length;
  }
}

/**
 * 一个内容块。字段按块类型取用（文本块的 `text`、照片块的 `photoFilename`…），
 * 与 iOS `ContentBlock` 同构 —— 同一个类装四种块，序列化 / 备份包字段完全一致。
 */
export class ContentBlock {
  readonly id: string;
  readonly type: ContentBlockType;

  // 文本块
  text?: string;
  /** 文字格式（只有文本块有，没格式时为 undefined） */
  styles?: TextStyleRun[];

  // 照片块
  photoFilename?: string;
  livePhotoVideoFilename?: string;
  /** 未裁原图，只有尺素相机拍的动态照片有（配对用）；为空时用 photoFilename 配对 */
  livePhotoStillFilename?: string;
  position?: PhotoPosition;
  paperStyle?: PaperStyle;
  /** ±3° 固定倾斜角，创建时定死（不能每次渲染随机，会抖） */
  rotationAngle?: number;
  /** 大屏展示封面，一篇最多一张为 true */
  isCover?: boolean;

  // 录音块
  /** 录音相对路径，与 JournalEntry.audioURLs 同写法（"audio/xxx.m4a"） */
  audioFilename?: string;

  // 墨迹
  /** 照片 / 录音什么时候放进来的（Unix 秒）。没写 = 日记写下时就有 */
  addedAt?: number;
  /** 痕迹块：取下的是什么（"photo" / "audio"） */
  traceOf?: string;
  /** 痕迹块：什么时候取下的（Unix 秒） */
  removedAt?: number;

  constructor(id: string, type: ContentBlockType) {
    this.id = id;
    this.type = type;
  }

  /** 是否为动态照片 */
  get isLivePhoto(): boolean {
    return this.livePhotoVideoFilename !== undefined;
  }

  /** 与 .mov 配对用的静态图文件名 —— 相机拍的用未裁原图，相册选的就是 photoFilename */
  get pairingStillFilename(): string | undefined {
    return this.livePhotoStillFilename !== undefined ? this.livePhotoStillFilename : this.photoFilename;
  }

  /**
   * 去掉划掉的字之后的正文（05 §3.4）。字数、搜索、寄给笔友都用它 ——
   * 划掉就是收回了，只是在纸上还留着痕迹。
   * 从后往前删，越界 / 负长度的区间跳过（与 iOS 一致）。
   */
  visibleText(): string {
    const text = this.text;
    if (text === undefined) {
      return '';
    }
    const styles = this.styles;
    if (styles === undefined) {
      return text;
    }
    const struck = styles.filter(run => run.struckAt !== undefined);
    if (struck.length === 0) {
      return text;
    }
    let result = text;
    const ordered = struck.slice().sort((a, b) => b.location - a.location);
    for (const run of ordered) {
      const loc = run.location;
      const len = run.length;
      if (loc < 0 || len < 0 || loc + len > result.length) {
        continue;
      }
      result = result.substring(0, loc) + result.substring(loc + len);
    }
    return result;
  }

  /** 文本块 */
  static makeText(id: string, text: string): ContentBlock {
    const block = new ContentBlock(id, ContentBlockType.Text);
    block.text = text;
    return block;
  }

  /** 录音块 */
  static makeAudio(id: string, audioFilename: string): ContentBlock {
    const block = new ContentBlock(id, ContentBlockType.Audio);
    block.audioFilename = audioFilename;
    return block;
  }

  /**
   * 照片块。倾斜角由 id 确定性推导（-3.0 ~ +2.9，步长 0.1），同一张照片每次渲染一致。
   * iOS 用的是 Swift `hashValue`（进程内随机种子，跨启动其实不稳定）；鸿蒙改用
   * 对 id 字符串的确定性哈希 —— 范围与精度和 iOS 相同，行为更符合「角度定死」的本意。
   */
  static makePhoto(id: string, photoFilename: string,
    livePhotoVideoFilename: string | undefined, position: PhotoPosition, paperStyle: PaperStyle): ContentBlock {
    const block = new ContentBlock(id, ContentBlockType.Photo);
    block.photoFilename = photoFilename;
    block.livePhotoVideoFilename = livePhotoVideoFilename;
    block.position = position;
    block.paperStyle = paperStyle;
    block.rotationAngle = ContentBlock.rotationAngleFor(id);
    return block;
  }

  /** 痕迹块：干了的照片 / 录音被取下后留在原处（05 §3.2） */
  static makeTrace(id: string, traceOf: ContentBlockType, removedAt: number): ContentBlock {
    const block = new ContentBlock(id, ContentBlockType.Trace);
    block.traceOf = traceOf as string;
    block.removedAt = removedAt;
    return block;
  }

  /** 由 id 推导 -3.0 ~ +2.9 的固定倾斜角（31 进制多项式哈希，确定性、跨启动稳定） */
  static rotationAngleFor(id: string): number {
    let hash = 0;
    for (let i = 0; i < id.length; i++) {
      hash = (hash * 31 + id.charCodeAt(i)) | 0;
    }
    return (Math.abs(hash) % 60 - 30) / 10.0;
  }
}

// ---- JSON 编解码（逐块容错） ----

/** 从 JSON 对象里取 string 字段，类型不对 / 缺失返回 undefined */
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

/** 解码一段文字格式。location / length 缺失或类型不对 → 整段丢弃 */
function decodeStyleRun(raw: Object): TextStyleRun | undefined {
  const rec = raw as Record<string, Object>;
  const location = fieldNumber(rec, 'location');
  const length = fieldNumber(rec, 'length');
  if (location === undefined || length === undefined) {
    return undefined;
  }
  const run = new TextStyleRun(location, length);
  const bold = fieldBoolean(rec, 'bold');
  if (bold !== undefined) {
    run.bold = bold;
  }
  const italic = fieldBoolean(rec, 'italic');
  if (italic !== undefined) {
    run.italic = italic;
  }
  const heading = fieldBoolean(rec, 'heading');
  if (heading !== undefined) {
    run.heading = heading;
  }
  const highlight = fieldBoolean(rec, 'highlight');
  if (highlight !== undefined) {
    run.highlight = highlight;
  }
  const writtenAt = fieldNumber(rec, 'writtenAt');
  if (writtenAt !== undefined) {
    run.writtenAt = writtenAt;
  }
  const struckAt = fieldNumber(rec, 'struckAt');
  if (struckAt !== undefined) {
    run.struckAt = struckAt;
  }
  return run;
}

/** 解码单个内容块。认不出的 type / 缺 id → 跳过（返回 undefined），不影响其他块 */
function decodeBlock(raw: Object): ContentBlock | undefined {
  const rec = raw as Record<string, Object>;
  const id = fieldString(rec, 'id');
  const typeRaw = fieldString(rec, 'type');
  if (id === undefined || typeRaw === undefined) {
    return undefined;
  }
  const type = contentBlockTypeFromRaw(typeRaw);
  if (type === undefined) {
    return undefined; // 认不出的 type：跳过该块（05 §3）
  }
  const block = new ContentBlock(id, type);
  const text = fieldString(rec, 'text');
  if (text !== undefined) {
    block.text = text;
  }
  const photoFilename = fieldString(rec, 'photoFilename');
  if (photoFilename !== undefined) {
    block.photoFilename = photoFilename;
  }
  const livePhotoVideoFilename = fieldString(rec, 'livePhotoVideoFilename');
  if (livePhotoVideoFilename !== undefined) {
    block.livePhotoVideoFilename = livePhotoVideoFilename;
  }
  const livePhotoStillFilename = fieldString(rec, 'livePhotoStillFilename');
  if (livePhotoStillFilename !== undefined) {
    block.livePhotoStillFilename = livePhotoStillFilename;
  }
  const positionRaw = fieldString(rec, 'position');
  const position = positionRaw !== undefined ? photoPositionFromRaw(positionRaw) : undefined;
  if (position !== undefined) {
    block.position = position;
  }
  const paperRaw = fieldString(rec, 'paperStyle');
  const paperStyle = paperRaw !== undefined ? paperStyleFromRaw(paperRaw) : undefined;
  if (paperStyle !== undefined) {
    block.paperStyle = paperStyle;
  }
  const rotationAngle = fieldNumber(rec, 'rotationAngle');
  if (rotationAngle !== undefined) {
    block.rotationAngle = rotationAngle;
  }
  const isCover = fieldBoolean(rec, 'isCover');
  if (isCover !== undefined) {
    block.isCover = isCover;
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
  const audioFilename = fieldString(rec, 'audioFilename');
  if (audioFilename !== undefined) {
    block.audioFilename = audioFilename;
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
  return block;
}

/**
 * 解码 `ContentBlock[]` 的 JSON（日记的 contentBlocksData 列）。
 * **逐块容错**：JSON 不是数组 → 空数组；单块坏了 / 认不出 → 只丢那一块。
 */
export function decodeContentBlocks(json: string): ContentBlock[] {
  const result: ContentBlock[] = [];
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(json);
  } catch (err) {
    return result;
  }
  if (parsed === null || !Array.isArray(parsed)) {
    return result;
  }
  const rawBlocks = parsed as Object[];
  for (const raw of rawBlocks) {
    const block = decodeBlock(raw);
    if (block !== undefined) {
      result.push(block);
    }
  }
  return result;
}

/** 编码 `ContentBlock[]` 为 JSON（undefined 的可选字段自动省略，与 iOS 编码一致） */
export function encodeContentBlocks(blocks: ContentBlock[]): string {
  return JSON.stringify(blocks);
}

// ---- 数组级辅助（对应 iOS `Array<ContentBlock>` 扩展） ----

/** 正文里放了的录音路径（按出现顺序） */
export function blocksAudioPaths(blocks: ContentBlock[]): string[] {
  const paths: string[] = [];
  for (const block of blocks) {
    if (block.type === ContentBlockType.Audio && block.audioFilename !== undefined) {
      paths.push(block.audioFilename);
    }
  }
  return paths;
}

/**
 * 把「在录音清单里、但正文里还没有位置」的录音补到正文末尾（R-RICH-09）。
 * 2026-10-10 之前的日记录音都在正文外面，打开编辑时就地转成正文里的录音块。
 */
export function blocksWithLooseAudio(blocks: ContentBlock[], audioURLs: string[],
  makeId: () => string): ContentBlock[] {
  const placed = new Set<string>(blocksAudioPaths(blocks));
  const loose: string[] = [];
  for (const url of audioURLs) {
    if (!placed.has(url)) {
      loose.push(url);
    }
  }
  if (loose.length === 0) {
    return blocks;
  }
  const result = blocks.slice();
  for (const url of loose) {
    result.push(ContentBlock.makeAudio(makeId(), url));
  }
  return result;
}
