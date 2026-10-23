/**
 * 大屏 / 总览的照片解码 + 底色缓存（10_BUILD_MANUAL.md 3.6，U06 R-HOME-10）。
 * 对应 iOS `Views/Components/EntryPhotoStore.swift`。
 *
 * 🔴 为什么要有它：用户照片是 1200 万～4800 万像素的原图，在画界面时同步
 * 解 + 取色会把主线程占住好几秒（iOS 2026-10-21 真机翻页卡几秒）。现在：
 *
 * - **全在后台异步解**，画界面只拿结果（image 解码本身走系统能力）
 * - **同时最多解 3 张，后来的先解**（DecodeGate 先进后出）：快速滚动时
 *   眼前刚出现的格子比早就滚走的要紧
 * - **解过的小图按尺寸存一份在 cacheDir**（`EntryPhotos/<尺寸>/<名>.jpg`），
 *   下次直接读几十 KB 的小图，不再碰原图；照片文件名带 UUID、存下不改，
 *   不用管失效
 * - **底色按文件名记一份**（'#RRGGBB'），各尺寸共用——换级时颜色不跳
 * - 内存缓存复用 ImageCache（LRU）：条数 400 / 90MB（iOS NSCache 同值）
 */
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ImageCache } from './ImageCache';
import { PHOTO_DIR_NAME } from './MediaStorage';
import { averageBgraRegion, normalizedTintHex } from './DominantColor';

const DOMAIN = 0x0000;
const TAG = 'EntryPhotoStore';

/** 内存缓存的尺寸档（anyCached 先大后小找） */
const SIZE_TIERS: number[] = [1400, 600, 300, 160];
/** 小图落盘 JPEG 质量（iOS 0.82） */
const SMALL_JPEG_QUALITY: number = 82;

/** 缓存键：`<尺寸>:<文件名>`（iOS `key` 同款） */
export function entryPhotoKey(pixels: number, filename: string): string {
  return `${pixels}:${filename}`;
}

/** 小图落盘路径：`<cacheDir>/EntryPhotos/<尺寸>/<原文件名>.jpg` */
export function smallPhotoPath(cacheDir: string, pixels: number,
  filename: string): string {
  return `${cacheDir}/EntryPhotos/${pixels}/${filename}.jpg`;
}

/**
 * 同时最多放 limit 个进去，多的排队；**后来的先进**（LIFO）。
 * 导出供单测跑「后来的先解」。
 */
export class DecodeGate {
  private readonly limit: number;
  private running: number = 0;
  private waiting: Array<() => void> = [];

  constructor(limit: number) {
    this.limit = limit;
  }

  /** 拿名额：有空的立即返回，没空的排队（后来者先出队） */
  acquire(): Promise<void> {
    if (this.running < this.limit) {
      this.running++;
      return Promise.resolve();
    }
    return new Promise<void>((resolve: (value: void) => void) => {
      this.waiting.push(resolve);
    });
  }

  /** 放名额：直接交给排在最后的那个（running 不变） */
  release(): void {
    const next = this.waiting.pop();
    if (next !== undefined) {
      next();
    } else {
      this.running = Math.max(0, this.running - 1);
    }
  }
}

/** 一张解好的照片 + 它的底色 */
export class EntryPhoto {
  readonly pixelMap: image.PixelMap;
  readonly tintHex: string;

  constructor(pixelMap: image.PixelMap, tintHex: string) {
    this.pixelMap = pixelMap;
    this.tintHex = tintHex;
  }
}

export class EntryPhotoStore {
  private static instance: EntryPhotoStore | null = null;

  static shared(): EntryPhotoStore {
    if (EntryPhotoStore.instance === null) {
      EntryPhotoStore.instance = new EntryPhotoStore();
    }
    return EntryPhotoStore.instance;
  }

  /** 照片原图目录（应用沙箱 filesDir/journal_photos/） */
  private photosDir: string = '';
  /** 小图落盘根目录（应用沙箱 cacheDir/EntryPhotos/） */
  private cacheDir: string = '';

  /** 解好的图（LRU：400 张 / 90MB，iOS 同值） */
  private readonly memory: ImageCache = new ImageCache();
  /** 底色：按文件名，各尺寸共用 */
  private readonly tints: Map<string, string> = new Map();
  private readonly gate: DecodeGate = new DecodeGate(3);

  private constructor() {
    this.memory.countLimit = 400;
    this.memory.totalCostLimit = 90 * 1024 * 1024;
  }

  /** 注入目录（HomeView aboutToAppear 调，幂等）。没配置过就 load 会返回 undefined */
  configure(context: common.Context): void {
    if (this.photosDir.length === 0) {
      this.photosDir = `${context.filesDir}/${PHOTO_DIR_NAME}`;
    }
    if (this.cacheDir.length === 0) {
      this.cacheDir = context.cacheDir;
    }
  }

  /** 这个尺寸已经解好的 */
  cached(filename: string, pixels: number): EntryPhoto | undefined {
    const pixelMap = this.memory.get(entryPhotoKey(pixels, filename));
    if (pixelMap === undefined) {
      return undefined;
    }
    return new EntryPhoto(pixelMap, this.tints.get(filename) ?? '#808080');
  }

  /** 任何尺寸解好过的（先大后小）：换格子大小、翻页时先拿它顶着，不闪底色 */
  anyCached(filename: string): EntryPhoto | undefined {
    for (const pixels of SIZE_TIERS) {
      const hit = this.cached(filename, pixels);
      if (hit !== undefined) {
        return hit;
      }
    }
    return undefined;
  }

  /** 底色已经算过的（还没解过这张照片就是 undefined） */
  knownTint(filename: string): string | undefined {
    return this.tints.get(filename);
  }

  /**
   * 解到最长边 pixels 像素。小图先找存过的；没有再从原图解，解完存一份。
   * 底色（照片底部 1/3 平均色）解图时顺手算，按文件名缓存。
   */
  async load(filename: string, pixels: number): Promise<EntryPhoto | undefined> {
    const key = entryPhotoKey(pixels, filename);
    const hit = this.cached(filename, pixels);
    if (hit !== undefined) {
      return hit;
    }
    if (this.photosDir.length === 0 || this.cacheDir.length === 0) {
      return undefined;
    }
    await this.gate.acquire();
    try {
      // 排队的时候别人可能已经解好了
      const queued = this.cached(filename, pixels);
      if (queued !== undefined) {
        return queued;
      }
      const decoded = await this.decode(filename, pixels);
      if (decoded === undefined) {
        hilog.warn(DOMAIN, TAG, 'decode failed: %{public}s', filename);
        return undefined;
      }
      const tintHex = this.tints.get(filename) ?? await this.computeTint(decoded);
      this.tints.set(filename, tintHex);
      const info: image.ImageInfo = decoded.getImageInfoSync();
      this.memory.set(key, decoded,
        Math.round(info.size.width * info.size.height * 4));
      return new EntryPhoto(decoded, tintHex);
    } finally {
      this.gate.release();
    }
  }

  /** 提前解好（翻页时把左右两页的照片先解出来，翻过去就有） */
  prefetch(filenames: string[], pixels: number): void {
    for (const name of filenames) {
      if (this.memory.get(entryPhotoKey(pixels, name)) === undefined) {
        this.load(name, pixels).catch((err: Object): void => {
          hilog.warn(DOMAIN, TAG, 'prefetch failed: %{public}s %{public}s',
            name, JSON.stringify(err));
        });
      }
    }
  }

  // ---- 内部 ----

  /** 先找存过的小图；没有再从原图解（等比缩到最长边 ≤ pixels，不放大），解完存一份 */
  private async decode(filename: string, pixels: number):
    Promise<image.PixelMap | undefined> {
    const smallPath = smallPhotoPath(this.cacheDir, pixels, filename);
    let pixelMap = await this.decodeFile(smallPath, pixels, false);
    if (pixelMap === undefined) {
      const originalPath = `${this.photosDir}/${filename}`;
      pixelMap = await this.decodeFile(originalPath, pixels, true);
      if (pixelMap === undefined) {
        return undefined;
      }
      await this.writeSmall(pixelMap, smallPath);
    }
    return pixelMap;
  }

  /** 读一个图片文件，等比缩到最长边 ≤ pixels（不放大）；文件不存在 / 解不出返回 undefined */
  private async decodeFile(path: string, pixels: number, reportMissing: boolean):
    Promise<image.PixelMap | undefined> {
    if (!this.fileExists(path)) {
      if (reportMissing) {
        hilog.warn(DOMAIN, TAG, 'photo not found: %{public}s', path);
      }
      return undefined;
    }
    let source: image.ImageSource | undefined = undefined;
    try {
      source = image.createImageSource(path);
      const info: image.ImageInfo = await source.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      if (width <= 0 || height <= 0) {
        return undefined;
      }
      const scale = Math.min(1, pixels / Math.max(width, height));
      const targetWidth = Math.max(1, Math.round(width * scale));
      const targetHeight = Math.max(1, Math.round(height * scale));
      const desiredSize: image.Size = { width: targetWidth, height: targetHeight };
      const options: image.DecodingOptions = { desiredSize: desiredSize };
      return await source.createPixelMap(options);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'decodeFile failed: %{public}s %{public}s',
        path, JSON.stringify(err));
      return undefined;
    } finally {
      if (source !== undefined) {
        source.release().catch((err: Object): void => {
          hilog.error(DOMAIN, TAG, 'ImageSource release failed: %{public}s', JSON.stringify(err));
        });
      }
    }
  }

  /** 解好的小图编码 JPEG 落盘（失败只记日志：下次再从原图解一遍，不影响显示） */
  private async writeSmall(pixelMap: image.PixelMap, smallPath: string): Promise<void> {
    try {
      const packer = image.createImagePacker();
      try {
        const option: image.PackingOption = { format: 'image/jpeg', quality: SMALL_JPEG_QUALITY };
        const data: ArrayBuffer = await packer.packing(pixelMap, option);
        const dir = smallPath.substring(0, smallPath.lastIndexOf('/'));
        if (!this.fileExists(dir)) {
          fileIo.mkdirSync(dir, true);
        }
        const file = fileIo.openSync(smallPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(file.fd, data);
        } finally {
          fileIo.closeSync(file);
        }
      } finally {
        packer.release();
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'writeSmall failed: %{public}s %{public}s',
        smallPath, JSON.stringify(err));
    }
  }

  /** 照片底部 1/3 的平均色 → 染色（readPixels 固定 BGRA_8888） */
  private async computeTint(pixelMap: image.PixelMap): Promise<string> {
    try {
      const info: image.ImageInfo = pixelMap.getImageInfoSync();
      const width = Math.round(info.size.width);
      const height = Math.round(info.size.height);
      if (width <= 0 || height <= 0) {
        return '#808080';
      }
      const startRow = Math.floor(height / 3) * 2;
      const rows = height - startRow;
      if (rows <= 0) {
        return '#808080';
      }
      const buffer: ArrayBuffer = new ArrayBuffer(width * rows * 4);
      const area: image.PositionArea = {
        pixels: buffer,
        offset: 0,
        stride: width * 4,
        region: { size: { width: width, height: rows }, x: 0, y: startRow }
      };
      await pixelMap.readPixels(area);
      const rgb = averageBgraRegion(buffer, width, rows);
      return normalizedTintHex(rgb[0], rgb[1], rgb[2]);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'computeTint failed: %{public}s', JSON.stringify(err));
      return '#808080';
    }
  }

  private fileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (err) {
      return false;
    }
  }
}
