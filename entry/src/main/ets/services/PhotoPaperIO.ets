/**
 * 照片文件的落盘、读取、删除（10_BUILD_MANUAL.md 1.4）。对应 iOS
 * `Views/Components/PhotoPaper/PhotoPaperHelpers.swift` 里的 `PhotoPaperIO`。
 *
 * - 目录：应用沙箱 filesDir 下 `journal_photos/`（05 §8；iOS 是 Documents/journal_photos/）
 * - `loadImage`：带进程级内存缓存（ImageCache），miss 时读盘 + 解码缩到最长边 600（正文照片）
 * - `loadCoverImage`：目标 1400（大屏展示），与 600 分开缓存（键加 `cover:` 前缀）——
 *   同一文件名两处按不同尺寸取用，共用一个键会互相覆盖（iOS 同款坑）
 * - `saveImage`：PixelMap 编码 JPEG（默认质量 85，对应 iOS 0.85）原子落盘
 * - `saveData`：任意字节**原样**落盘（动态照片视频 / 未裁原图走它）。
 *   🔴 R-PHOTO-03：动态照片的静态图、视频一律原样字节，**绝不重编码**——重编码会丢配对标识，且失败是静默的
 * - iOS 读取是同步的（UIImage(contentsOfFile:)），鸿蒙解码只能异步，调用方自行 await；
 *   命中缓存时 Promise 立即返回
 * - 缩放策略：等比缩到最长边 ≤ 目标，**不放大**（iOS loadCoverImage 明确不放大；
 *   loadImage 的 preparingThumbnail 会放大小图，鸿蒙统一不放大——省内存且小图更清晰，记为偏差）
 */
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ImageCache, COVER_CACHE_KEY_PREFIX } from './ImageCache';
import { PHOTO_DIR_NAME } from './MediaStorage';

const DOMAIN = 0x0000;
const TAG = 'PhotoPaperIO';

/** 正文照片缩略图的最长边（iOS 同值） */
const THUMBNAIL_EDGE = 600;

/** 大屏封面图的最长边（iOS 同值） */
const COVER_EDGE = 1400;

/** 默认 JPEG 质量（0-100；对应 iOS compressionQuality 0.85） */
const DEFAULT_JPEG_QUALITY = 85;

export class PhotoPaperIO {
  /** 照片存放目录（应用沙箱 filesDir/journal_photos/） */
  readonly photosDir: string;

  /** 按应用沙箱 filesDir 建实例（目录常量见 MediaStorage.PHOTO_DIR_NAME） */
  static forFilesDir(filesDir: string): PhotoPaperIO {
    return new PhotoPaperIO(`${filesDir}/${PHOTO_DIR_NAME}`);
  }

  constructor(photosDir: string) {
    this.photosDir = photosDir;
    this.ensureDir();
  }

  /**
   * 从 journal_photos/&lt;filename&gt; 加载正文照片（最长边 600），**带进程级内存缓存**。
   * 策略：内存命中 → 直接返回；否则读盘 + 解码缩放 + 入缓存（cost = 像素数 × 4 字节 RGBA）。
   * 文件不存在 / 解码失败 → undefined（调用方渲染占位图）。
   */
  async loadImage(filename: string | undefined): Promise<image.PixelMap | undefined> {
    return this.decodeFit(filename, THUMBNAIL_EDGE);
  }

  /** 大屏展示封面用的加载（最长边 1400），与 loadImage 分开缓存（键加 cover: 前缀） */
  async loadCoverImage(filename: string | undefined): Promise<image.PixelMap | undefined> {
    return this.decodeFit(filename, COVER_EDGE, COVER_CACHE_KEY_PREFIX);
  }

  /** 保存 PixelMap 到 journal_photos/&lt;filename&gt;，JPEG 压缩后**原子**落盘 */
  async saveImage(pixelMap: image.PixelMap, filename: string,
    quality: number = DEFAULT_JPEG_QUALITY): Promise<boolean> {
    const packer = image.createImagePacker();
    try {
      const option: image.PackingOption = { format: 'image/jpeg', quality: quality };
      const data: ArrayBuffer = await packer.packing(pixelMap, option);
      return this.atomicWriteBytes(`${this.photosDir}/${filename}`, data);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveImage packing failed: %{public}s %{public}s',
        filename, JSON.stringify(err));
      return false;
    } finally {
      packer.release();
    }
  }

  /**
   * 保存任意字节到 journal_photos/&lt;filename&gt;，**原样**原子落盘。
   * 用于动态照片视频与相机未裁原图（R-PHOTO-03：原样字节，不许重编码）。
   */
  async saveData(data: ArrayBuffer, filename: string): Promise<boolean> {
    return this.atomicWriteBytes(`${this.photosDir}/${filename}`, data);
  }

  /** 删除指定文件名的照片文件，并清掉两个尺寸的缓存条目（防渲染出已删除的旧图） */
  deleteImage(filename: string | undefined): void {
    if (filename === undefined || filename.length === 0) {
      return;
    }
    try {
      fileIo.unlinkSync(`${this.photosDir}/${filename}`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'unlinkSync failed: %{public}s %{public}s',
        filename, JSON.stringify(err));
    }
    const cache = ImageCache.shared();
    cache.remove(filename);
    cache.remove(COVER_CACHE_KEY_PREFIX + filename);
  }

  // ---- 内部 ----

  /** 目录不存在则递归创建（对应 iOS photosDirectory getter 的建目录逻辑） */
  private ensureDir(): void {
    try {
      if (!fileIo.accessSync(this.photosDir)) {
        fileIo.mkdirSync(this.photosDir, true);
      }
      return;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'accessSync failed: %{public}s %{public}s',
        this.photosDir, JSON.stringify(err));
    }
    try {
      fileIo.mkdirSync(this.photosDir, true);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'mkdirSync failed: %{public}s %{public}s',
        this.photosDir, JSON.stringify(err));
    }
  }

  /**
   * 读盘 + 等比缩到最长边 ≤ targetEdge（不放大）+ 入缓存。
   * cacheKeyPrefix：正文小图为空串，封面为 "cover:"（两档尺寸分开缓存，见类注释）。
   */
  private async decodeFit(filename: string | undefined, targetEdge: number,
    cacheKeyPrefix: string = ''): Promise<image.PixelMap | undefined> {
    if (filename === undefined || filename.length === 0) {
      return undefined;
    }
    const cacheKey = cacheKeyPrefix + filename;
    const cache = ImageCache.shared();
    const cached = cache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    const path = `${this.photosDir}/${filename}`;
    if (!this.fileExists(path)) {
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
      // 等比缩放，不放大；desiredSize 按比例给，长宽比不失真
      const scale = Math.min(1, targetEdge / Math.max(width, height));
      let pixelMap: image.PixelMap;
      if (scale < 1) {
        const targetWidth = Math.max(1, Math.round(width * scale));
        const targetHeight = Math.max(1, Math.round(height * scale));
        const desiredSize: image.Size = { width: targetWidth, height: targetHeight };
        const options: image.DecodingOptions = { desiredSize: desiredSize };
        pixelMap = await source.createPixelMap(options);
        cache.set(cacheKey, pixelMap, targetWidth * targetHeight * 4);
      } else {
        pixelMap = await source.createPixelMap();
        cache.set(cacheKey, pixelMap, Math.round(width * height) * 4);
      }
      return pixelMap;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'decodeFit failed: %{public}s %{public}s',
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

  private fileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (err) {
      return false;
    }
  }

  /** 字节落盘（先写 .tmp 再改名，对齐 iOS 的 .atomic；失败清掉半成品） */
  private atomicWriteBytes(path: string, data: ArrayBuffer): boolean {
    const tmpPath = `${path}.tmp`;
    this.quietUnlink(tmpPath);
    try {
      const file = fileIo.openSync(tmpPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, data);
      } finally {
        fileIo.closeSync(file);
      }
      this.quietUnlink(path);
      fileIo.renameSync(tmpPath, path);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'atomicWriteBytes failed: %{public}s %{public}s',
        path, JSON.stringify(err));
      this.quietUnlink(tmpPath);
      return false;
    }
  }

  private quietUnlink(path: string): void {
    try {
      fileIo.unlinkSync(path);
    } catch (err) {
      // 不存在 / 删不掉都不往上抛
    }
  }
}
