/**
 * 进程级图片内存缓存（10_BUILD_MANUAL.md 1.4）。对应 iOS
 * `Views/Components/PhotoPaper/PhotoPaperHelpers.swift` 里的 `ImageCache`（NSCache）。
 *
 * - 命中：跳过磁盘 IO + 解码（正文照片频繁重绘时的关键优化点）
 * - miss：由 PhotoPaperIO 读磁盘、解码缩略后放入
 * - ArkTS 没有 NSCache，这里用 Map 的插入序手写 LRU：
 *   条数（100）与估算内存（50 MB，cost = 像素数 × 4 字节 RGBA）双上限驱逐，
 *   语义对齐 iOS 的 countLimit / totalCostLimit
 */
import { image } from '@kit.ImageKit';

/**
 * 封面（大屏展示）加载的缓存键前缀（iOS `loadCoverImage` 同款约定）。
 * 同一文件名在正文小图与封面大图两处按不同尺寸取用，键分开存，防止互相覆盖。
 */
export const COVER_CACHE_KEY_PREFIX: string = 'cover:';

/** 单条缓存（值 + 估算内存占用） */
class CacheEntry {
  readonly value: image.PixelMap;
  readonly cost: number;

  constructor(value: image.PixelMap, cost: number) {
    this.value = value;
    this.cost = cost;
  }
}

export class ImageCache {
  private static instance: ImageCache | null = null;

  /** 全进程共享实例（对应 iOS `ImageCache.shared`） */
  static shared(): ImageCache {
    if (ImageCache.instance === null) {
      ImageCache.instance = new ImageCache();
    }
    return ImageCache.instance;
  }

  /** 最多缓存条数（iOS 同值） */
  countLimit: number = 100;
  /** 估算内存上限：50 MB（iOS 同值） */
  totalCostLimit: number = 50 * 1024 * 1024;

  private entries: Map<string, CacheEntry> = new Map();
  private totalCost: number = 0;

  get(key: string): image.PixelMap | undefined {
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return undefined;
    }
    // 触摸成最近使用：Map 保持插入序，删掉重插即移到末尾（LRU）
    this.entries.delete(key);
    this.entries.set(key, entry);
    return entry.value;
  }

  set(key: string, value: image.PixelMap, cost: number): void {
    const existing = this.entries.get(key);
    if (existing !== undefined) {
      this.totalCost -= existing.cost;
      this.entries.delete(key);
    }
    this.entries.set(key, new CacheEntry(value, cost));
    this.totalCost += cost;
    this.evictIfNeeded();
  }

  /** 移除单条（文件被删除时清掉缓存里的旧图，防止渲染出已删除的 stale 图） */
  remove(key: string): void {
    const entry = this.entries.get(key);
    if (entry !== undefined) {
      this.totalCost -= entry.cost;
      this.entries.delete(key);
    }
  }

  clear(): void {
    this.entries.clear();
    this.totalCost = 0;
  }

  get size(): number {
    return this.entries.size;
  }

  /** 超限驱逐：Map 里最靠前的键即最久未用，从头逐条清到限额内 */
  private evictIfNeeded(): void {
    while (this.entries.size > this.countLimit || this.totalCost > this.totalCostLimit) {
      const keys: string[] = Array.from(this.entries.keys());
      if (keys.length === 0) {
        break;
      }
      this.remove(keys[0]);
    }
  }
}
