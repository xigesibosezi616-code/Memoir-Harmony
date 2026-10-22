/**
 * 日记本照片封面的解码与烤盘（10_BUILD_MANUAL.md 3.4）。对应 iOS
 * `Shelf/NotebookCoverStore.swift`。
 *
 * - 烤盘：取景框换算回原图的区域（`CoverCropRect`，像素坐标）→ `PixelMap.crop`
 *   （原地）→ `scale` 到 `coverRenderSize`（宽 ≤1200，不放大）→ JPEG q85
 *   原子落盘（复用 `PhotoPaperIO.saveImage`），文件名 `cover_<UUID>.jpg`
 * - 🔴 `crop` / `scale` 都是**原地修改**：每次烤盘都从原始字节 / 文件现解一份
 *   干净源，烤完 `release`，绝不在裁过的图上再裁
 * - 已有封面的「调整构图」：文件本身就是 ≤1200 的成品，全尺寸解码再裁
 *   （iOS `fullImage` 同款；`PhotoPaperIO.loadCoverImage` 会缩到 1400 且走缓存，
 *   缓存实例被 crop 改掉会污染别处显示，不能用）
 * - 删：换 / 移除 / 删本时旧文件连删（R-BOOK-16 的本地部分；云端副本等 Q3
 *   云同步，`MediaStorageService` 头注释同款口径）
 */
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PhotoPaperIO } from './PhotoPaperIO';
import { PHOTO_DIR_NAME, coverFilenameFor } from './MediaStorage';
import { decodeImageFromBuffer } from './PhotoLibraryPicker';
import { COVER_SOURCE_MAX_EDGE, CoverCropRect, coverRenderSize } from '../models/CoverEdit';
import { generateUuid } from '../models/Uuid';

const DOMAIN = 0x0000;
const TAG = 'NotebookCoverStore';

export class NotebookCoverStore {
  /** 照片存放目录（应用沙箱 filesDir/journal_photos/） */
  readonly photosDir: string;
  private readonly io: PhotoPaperIO;

  /** 按应用沙箱 filesDir 建实例 */
  static forFilesDir(filesDir: string): NotebookCoverStore {
    return new NotebookCoverStore(`${filesDir}/${PHOTO_DIR_NAME}`);
  }

  constructor(photosDir: string) {
    this.photosDir = photosDir;
    this.io = new PhotoPaperIO(photosDir);
  }

  /**
   * 相册原始字节 → 长边 ≤2400 的干净源（构图页显示 + 烤盘解码共用参数）。
   * 4800 万像素原图全解近 200MB，2400 绰绰有余（iOS `downsample` 同值）。
   */
  async decodeSourceFromBuffer(buffer: ArrayBuffer): Promise<image.PixelMap | undefined> {
    return decodeImageFromBuffer(buffer, COVER_SOURCE_MAX_EDGE);
  }

  /**
   * 已有封面文件 → 全尺寸干净源（「调整构图」用）。
   * 不走 `PhotoPaperIO` 的缓存：crop / scale 原地改，缓存实例被改掉会污染别处。
   */
  async decodeSourceFromFile(filename: string | undefined): Promise<image.PixelMap | undefined> {
    if (filename === undefined || filename.length === 0) {
      return undefined;
    }
    const path = `${this.photosDir}/${filename}`;
    let source: image.ImageSource | undefined = undefined;
    try {
      source = image.createImageSource(path);
      return await source.createPixelMap();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'decodeSourceFromFile failed: %{public}s %{public}s',
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

  /** 新选照片（原始字节）按 `rect` 烤盘，成功返回文件名 */
  async renderCoverFromBuffer(buffer: ArrayBuffer,
    rect: CoverCropRect): Promise<string | undefined> {
    const source = await this.decodeSourceFromBuffer(buffer);
    if (source === undefined) {
      return undefined;
    }
    return this.renderDecodedSource(source, rect);
  }

  /** 已有封面文件按 `rect` 重烤（在已裁那张里再调构图），成功返回新文件名 */
  async renderCoverFromFile(filename: string,
    rect: CoverCropRect): Promise<string | undefined> {
    const source = await this.decodeSourceFromFile(filename);
    if (source === undefined) {
      return undefined;
    }
    return this.renderDecodedSource(source, rect);
  }

  /** 删封面文件并清图片缓存（两档尺寸，`PhotoPaperIO.deleteImage` 同款效果） */
  deleteCover(filename: string | undefined): void {
    this.io.deleteImage(filename);
  }

  // ---- 内部 ----

  /** 现解的干净源 → 裁 → 缩 → 存，返回文件名；源无论成败都释放 */
  private async renderDecodedSource(source: image.PixelMap,
    rect: CoverCropRect): Promise<string | undefined> {
    try {
      if (!await this.cropAndScale(source, rect)) {
        return undefined;
      }
      const filename = coverFilenameFor(generateUuid());
      if (await this.io.saveImage(source, filename)) {
        return filename;
      }
      return undefined;
    } finally {
      source.release().catch((err: Object): void => {
        hilog.error(DOMAIN, TAG, 'PixelMap release failed: %{public}s', JSON.stringify(err));
      });
    }
  }

  /** 原地裁 + 缩（iOS `render`：outSize 宽 ≤1200 不放大，高按封面比例推） */
  private async cropAndScale(source: image.PixelMap, rect: CoverCropRect): Promise<boolean> {
    try {
      const info: image.ImageInfo = await source.getImageInfo();
      const sourceWidth = info.size.width;
      const sourceHeight = info.size.height;
      if (sourceWidth <= 0 || sourceHeight <= 0 || rect.width <= 0 || rect.height <= 0) {
        return false;
      }
      // 裁块夹回图内（取景几何已保证在界内，这里挡浮点 / 舍入误差）
      const x = Math.max(0, Math.min(Math.round(rect.x), sourceWidth - 1));
      const y = Math.max(0, Math.min(Math.round(rect.y), sourceHeight - 1));
      const cropWidth = Math.max(1, Math.min(Math.round(rect.width), sourceWidth - x));
      const cropHeight = Math.max(1, Math.min(Math.round(rect.height), sourceHeight - y));
      const region: image.Region = {
        x: x,
        y: y,
        size: { width: cropWidth, height: cropHeight }
      };
      await source.crop(region);
      const out = coverRenderSize(cropWidth);
      await source.scale(out.width / cropWidth, out.height / cropHeight);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'cropAndScale failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }
}
