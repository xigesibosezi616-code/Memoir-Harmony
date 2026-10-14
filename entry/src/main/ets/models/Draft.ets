/**
 * 没写完的那一篇草稿（05_DATA_MODEL.md §7）。对应 iOS `Models/DraftEntry.swift`。
 *
 * - 🔴 **单独一张表、全局只留一份**；绝不在日记表加 isDraft ——
 *   加标志位的话首页、日记本、统计、备份每处查询都得记得过滤，漏一处草稿就混进正式日记
 * - 草稿不进统计、列表、备份包；草稿引用的媒体算「在用」（孤儿清理不删，1.4）
 * - 转正：建日记 → 删草稿记录，**不删草稿引用的媒体**（新日记接着用）；
 *   「不保存」：草稿记录连同媒体一起删
 * - 「此时此地」存的是**存草稿那一刻的快照**，恢复时原样还原、不重新定位（R-ENTRY-05）
 */
import { ContentBlock, ContentBlockType, decodeContentBlocks, encodeContentBlocks } from './ContentBlock';

/** 地点选择模式（DraftEntry.placeMode 的取值） */
export enum PlaceMode {
  Auto = 'auto',
  None = 'none',
  Manual = 'manual'
}

export class DraftEntry {
  readonly id: string;
  title: string = '';
  /** 与日记同一套内容块 JSON，转正时直接搬 */
  contentBlocksData?: string;
  mood: string = '';
  moodColorHex?: string;
  /** 选过的日记本（≤ 1 个名字） */
  tags: string[] = [];
  audioURLs: string[] = [];
  weatherCode?: string;
  weatherInfo?: string;
  locationInfo?: string;
  /** auto / none / manual，配合 manualPlaceName 还原地点选择 */
  placeMode: string = PlaceMode.Auto;
  manualPlaceName?: string;
  createdAt: number;
  updatedAt: number;

  constructor(id: string, createdAt: number, updatedAt: number) {
    this.id = id;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }

  /**
   * 结构化内容块。草稿没有「从 content 降级」的旧路径 —— 它是全新的模型，不存在历史数据。
   */
  get contentBlocks(): ContentBlock[] {
    if (this.contentBlocksData !== undefined) {
      return decodeContentBlocks(this.contentBlocksData);
    }
    return [];
  }

  /** 写内容块（编码 + 刷新 updatedAt）。草稿没有派生 content，字数等转正时再算 */
  setContentBlocks(blocks: ContentBlock[], now: number): void {
    this.contentBlocksData = encodeContentBlocks(blocks);
    this.updatedAt = now;
  }

  /**
   * 这份草稿引用到的全部媒体文件名（照片三件套 + 录音相对路径与裸名）。
   * ⚠️ 1.4 的引用表靠它把草稿里的照片算进「被引用」，否则孤儿清理会误删。
   */
  get referencedMediaNames(): string[] {
    const names: string[] = [];
    for (const block of this.contentBlocks) {
      if (block.type === ContentBlockType.Text) {
        continue;
      }
      if (block.photoFilename !== undefined) {
        names.push(block.photoFilename);
      }
      if (block.livePhotoVideoFilename !== undefined) {
        names.push(block.livePhotoVideoFilename);
      }
      if (block.livePhotoStillFilename !== undefined) {
        names.push(block.livePhotoStillFilename);
      }
    }
    for (const relative of this.audioURLs) {
      names.push(relative);
      const slash = relative.lastIndexOf('/');
      if (slash >= 0) {
        names.push(relative.substring(slash + 1));
      }
    }
    return names;
  }
}
