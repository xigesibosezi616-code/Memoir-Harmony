/**
 * 系统照片选择器封装（10_BUILD_MANUAL.md 2.6）。对应 iOS `PhotoInsertFlow` 里的
 * `photosPicker`（PhotosUI）。
 *
 * - 用图库选择器（`photoAccessHelper.PhotoViewPicker`）：**系统 Picker，无需任何权限**
 *   （R-PHOTO：相册选图不读媒体库，用户选哪张才拿到哪张的临时句柄）
 * - 单选、只图片（maxSelectNumber 1；拍照入口属 2.9，这里关掉 Picker 内的拍照按钮）
 * - 解码上限：最长边 2048（等比缩小、不放大）。iOS 把相册选的图全尺寸重编码存 JPEG，
 *   鸿蒙截到 2048 —— 正文卡片宽 ~230vp、全屏 600px 缩略图都在这个精度内，
 *   50MP 原图全量解码只是白占内存（偏差记 PROGRESS 追记）
 * - 解码成 PixelMap 交回：相纸选择器预览、落盘（PhotoPaperIO.saveImage JPEG 质量 85）
 *   都用它；相册选的普通照片**走重编码**，不受 R-PHOTO-03「原样落盘」约束
 *   （那条只管动态照片素材，2.9）
 */
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'PhotoLibraryPicker';

/** 解码上限：最长边 2048px（等比缩小、不放大） */
const DECODE_MAX_EDGE = 2048;

export class PhotoLibraryPicker {
  /**
   * 拉起系统图库选择一张图片，解码成 PixelMap。
   * 用户取消 / 选图失败 / 解码失败 → undefined（调用方静默收场，不打扰用户）。
   */
  static async pick(): Promise<image.PixelMap | undefined> {
    const uris = await PhotoLibraryPicker.pickUri();
    if (uris.length === 0) {
      return undefined;
    }
    return PhotoLibraryPicker.decodeFromUri(uris[0]);
  }

  /** 拉起系统图库选择器；取消 / 出错返回空数组 */
  private static async pickUri(): Promise<string[]> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.maxSelectNumber = 1;
      options.isPhotoTakingSupported = false;
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      return result.photoUris;
    } catch (err) {
      hilog.info(DOMAIN, TAG, 'select cancelled or failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  /** 从 uri 读文件 → 解码 PixelMap（最长边 ≤2048，等比缩小、不放大） */
  private static async decodeFromUri(uri: string): Promise<image.PixelMap | undefined> {
    let file: fileIo.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const size = fileIo.statSync(file.fd).size;
      const buffer = new ArrayBuffer(size);
      fileIo.readSync(file.fd, buffer);
      source = image.createImageSource(buffer);
      const info: image.ImageInfo = await source.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      if (width <= 0 || height <= 0) {
        return undefined;
      }
      const scale = Math.min(1, DECODE_MAX_EDGE / Math.max(width, height));
      if (scale < 1) {
        const desiredSize: image.Size = {
          width: Math.max(1, Math.round(width * scale)),
          height: Math.max(1, Math.round(height * scale))
        };
        const options: image.DecodingOptions = { desiredSize: desiredSize };
        return await source.createPixelMap(options);
      }
      return await source.createPixelMap();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'decodeFromUri failed: %{public}s', JSON.stringify(err));
      return undefined;
    } finally {
      if (source !== undefined) {
        source.release().catch((err: Object): void => {
          hilog.error(DOMAIN, TAG, 'ImageSource release failed: %{public}s', JSON.stringify(err));
        });
      }
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (err) {
          hilog.error(DOMAIN, TAG, 'closeSync failed: %{public}s', JSON.stringify(err));
        }
      }
    }
  }
}
