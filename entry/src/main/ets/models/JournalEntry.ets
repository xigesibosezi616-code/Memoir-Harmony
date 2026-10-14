/**
 * 一篇正式日记（05_DATA_MODEL.md §2）。对应 iOS `Models/JournalEntry.swift`。
 *
 * - 本地时间字段（date / createdAt / updatedAt）存**毫秒**时间戳（05 §0 建表约定）
 * - `content` 是**派生字段**：所有文本块的 `visibleText` 用 `\n\n` 连接。
 *   字数、搜索、摘要、寄给笔友都读它。**只能由 setContentBlocks 写入时同步生成**，
 *   不许单独写（R-RICH-10：iOS 出过「编辑后改动丢失」）
 * - `tags` 存日记本**名字**（🔴 最多一个元素，一篇最多属于一本）；空 = 只在「全部日记」
 * - 草稿是另一张表（Draft），**本表没有也不许有 isDraft**（05 §7）
 * - 不建 iOS 已废弃的 `stampEmoji`（05 §2）
 */
import { ContentBlock, ContentBlockType, Ink, decodeContentBlocks, encodeContentBlocks,
  blocksAudioPaths } from './ContentBlock';

export class JournalEntry {
  /** 标题字数上限（封面三行决定，iOS 同值） */
  static readonly titleMaxLength: number = 40;

  readonly id: string;
  title: string = '';
  /** 派生：只能由 setContentBlocks 同步生成（R-RICH-10） */
  content: string = '';
  /** 日记属于哪一天（排序键）。UI 目前不能改 */
  date: number;
  /** 心情 key（calm…，见 Mood；空 = 没选） */
  mood: string = '';
  moodColorHex?: string;
  /** 所在日记本的名字，🔴 ≤ 1 个元素。空 = 只在「全部日记」 */
  tags: string[] = [];
  /** iOS 没有任何 UI 用它，只是随备份包来回带。不做收藏功能 */
  isFavorite: boolean = false;
  wordCount: number = 0;
  /** 真正写下的时刻。「墨迹干没干」「邮筒要寄哪些」都按它判断，不按 date */
  createdAt: number;
  /** 内容块每次写入都刷新（setContentBlocks 里做） */
  updatedAt: number;
  /** 录音文件总清单，相对路径 "audio/<名>.m4a"。同步、备份、删日记清文件只认它 */
  audioURLs: string[] = [];
  weatherCode?: string;
  weatherInfo?: string;
  locationInfo?: string;
  /** ContentBlock[] 的 JSON。为空时按 content 退化成单文本块（老数据兼容） */
  contentBlocksData?: string;

  constructor(id: string, date: number, createdAt: number, updatedAt: number) {
    this.id = id;
    this.date = date;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }

  /**
   * 结构化内容块（读）。对应 iOS `contentBlocks` 的 get：
   * `contentBlocksData` 有就解码（逐块容错）；没有则从旧的 `content` 降级成
   * 单一文本块 —— 块 id 用 entry.id 保持稳定，否则「长按插入照片」的锚点会失配。
   */
  get contentBlocks(): ContentBlock[] {
    if (this.contentBlocksData !== undefined) {
      return decodeContentBlocks(this.contentBlocksData);
    }
    return this.content.length > 0 ? [ContentBlock.makeText(this.id, this.content)] : [];
  }

  /**
   * 🔴 日记内容的**唯一写入口**（R-RICH-10）。写内容块时同步生成：
   * `content`（文本块 visibleText 用 `\n\n` 连接）、`wordCount`、`audioURLs`
   * （正文里的录音块按顺序生成）、`updatedAt`。绝不分开写。
   */
  setContentBlocks(blocks: ContentBlock[], now: number): void {
    this.contentBlocksData = encodeContentBlocks(blocks);
    const texts: string[] = [];
    for (const block of blocks) {
      if (block.type === ContentBlockType.Text) {
        texts.push(block.visibleText());
      }
    }
    this.content = texts.join('\n\n');
    this.wordCount = this.content.length;
    this.audioURLs = blocksAudioPaths(blocks);
    this.updatedAt = now;
  }

  /** 录音清单里、正文中没有位置的录音（老日记的录音）—— 还按原来的样子排在正文后面 */
  get looseAudioURLs(): string[] {
    const placed = new Set<string>(blocksAudioPaths(this.contentBlocks));
    const loose: string[] = [];
    for (const url of this.audioURLs) {
      if (!placed.has(url)) {
        loose.push(url);
      }
    }
    return loose;
  }

  /** 补记过的那几天（不同的日子，按先后，本地午夜毫秒）。详情页「补记 N 次」用 */
  get addendumDays(): number[] {
    const days = new Set<number>();
    const baseSec = this.createdAt / 1000;
    for (const block of this.contentBlocks) {
      JournalEntry.addAddendumDay(days, block.addedAt, baseSec);
      if (block.styles !== undefined) {
        for (const run of block.styles) {
          if (run.struckAt === undefined) {
            JournalEntry.addAddendumDay(days, run.writtenAt, baseSec);
          }
        }
      }
    }
    return Array.from(days).sort((a, b) => a - b);
  }

  private static addAddendumDay(days: Set<number>, writtenSec: number | undefined, baseSec: number): void {
    if (writtenSec === undefined || !Ink.isAddendum(writtenSec, baseSec)) {
      return;
    }
    const d = new Date(writtenSec * 1000);
    days.add(new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime());
  }

  /** 当前日记中的照片数量 */
  get photoCount(): number {
    let count = 0;
    for (const block of this.contentBlocks) {
      if (block.type === ContentBlockType.Photo) {
        count++;
      }
    }
    return count;
  }

  // ---- 大屏展示的派生数据（iOS `JournalEntry+Showcase.swift`） ----

  /** 正文里的全部照片文件名，按出现顺序。多张时大屏封面轮播 */
  get photoFilenames(): string[] {
    const names: string[] = [];
    for (const block of this.contentBlocks) {
      if (block.type === ContentBlockType.Photo && block.photoFilename !== undefined) {
        names.push(block.photoFilename);
      }
    }
    return names;
  }

  /** 封面照片：用户指定的优先；没指定用第一张；没照片为空 */
  get coverPhotoFilename(): string | undefined {
    let first: string | undefined = undefined;
    for (const block of this.contentBlocks) {
      if (block.type === ContentBlockType.Photo && block.photoFilename !== undefined) {
        if (block.isCover === true) {
          return block.photoFilename;
        }
        if (first === undefined) {
          first = block.photoFilename;
        }
      }
    }
    return first;
  }

  /** 是否有录音 —— 大屏卡片要不要出播放键 */
  get hasAudio(): boolean {
    return this.audioURLs.length > 0;
  }

  /** 正文纯文字预览（只取文本块，`\n` 连接，去首尾空白） */
  get textPreview(): string {
    const parts: string[] = [];
    for (const block of this.contentBlocks) {
      if (block.type === ContentBlockType.Text) {
        parts.push(block.visibleText());
      }
    }
    return parts.join('\n').trim();
  }

  // ---- 标题规则（iOS `JournalEntry.sanitizedTitle`） ----

  /**
   * 标题输入的净化：去掉换行（列表 / 大屏 / 阅读器页眉都是单行，藏个换行会变空隙）
   * + 截到上限。
   */
  static sanitizedTitle(raw: string): string {
    // 去掉全部换行（JS 的 replace 首参为字符串只换第一处，用 split/join 换干净）
    const trimmed = raw.split('\n').join('');
    const result = trimmed.length > JournalEntry.titleMaxLength
      ? trimmed.substring(0, JournalEntry.titleMaxLength)
      : trimmed;
    return result;
  }
}
