/**
 * 系统照片选择器封装（10_BUILD_MANUAL.md 2.6 / 2.9）。对应 iOS `PhotoInsertFlow` 里的
 * `photosPicker`（PhotosUI）。
 *
 * - 用图库选择器（`photoAccessHelper.PhotoViewPicker`）：**系统 Picker，无需任何权限**
 *   （R-PHOTO：相册选图不读媒体库，用户选哪张才拿到哪张的临时句柄）
 * - 单选、只图片（maxSelectNumber 1；拍照入口属 2.9，这里关掉 Picker 内的拍照按钮）
 * - 2.9 动态照片：选中后拿 URI 换 `PhotoAsset` 查 `PHOTO_SUBTYPE`，是动态照片就走
 *   `requestMovingPhoto` → `requestContent`（cacheDir 临时文件）把**原图 + 视频原样字节**
 *   提出来（R-PHOTO-03：绝不重编码）；链路失败退普通静态图（R-PHOTO-04 兜底）
 * - 解码上限：最长边 2048（等比缩小、不放大）。iOS 把相册选的图全尺寸重编码存 JPEG，
 *   鸿蒙截到 2048 —— 正文卡片宽 ~230vp、全屏 600px 缩略图都在这个精度内，
 *   50MP 原图全量解码只是白占内存（偏差记 PROGRESS 追记）。
 *   普通照片**走重编码**（PixelMap → saveImage q85）；动态照片的静态图走原样字节落盘
 * - `PickedLibraryPhoto.pixelMap` 只做相纸预览 / 静态落盘；动态照片落盘用
 *   `stillBuffer` / `videoBuffer`（saveData 原样）
 */
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { dataSharePredicates } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { COVER_SOURCE_MAX_EDGE } from '../models/CoverEdit';

const DOMAIN = 0x0000;
const TAG = 'PhotoLibraryPicker';

/** 解码上限：最长边 2048px（等比缩小、不放大） */
const DECODE_MAX_EDGE = 2048;

/**
 * 一次相册选取的产物。
 * - 普通照片：只有 `pixelMap`（落盘时重编码 JPEG q85）
 * - 动态照片：`pixelMap`（预览 / 兜底用）+ `stillBuffer` / `videoBuffer`（原样字节，
 *   落盘走 `PhotoPaperIO.saveData`，R-PHOTO-03）
 */
export class PickedLibraryPhoto {
  readonly pixelMap: image.PixelMap;
  /** 动态照片原图字节（原样；普通照片为 undefined） */
  readonly stillBuffer: ArrayBuffer | undefined;
  /** 动态照片视频字节（原样；普通照片为 undefined） */
  readonly videoBuffer: ArrayBuffer | undefined;

  constructor(pixelMap: image.PixelMap, stillBuffer: ArrayBuffer | undefined,
    videoBuffer: ArrayBuffer | undefined) {
    this.pixelMap = pixelMap;
    this.stillBuffer = stillBuffer;
    this.videoBuffer = videoBuffer;
  }

  get isMovingPhoto(): boolean {
    return this.stillBuffer !== undefined && this.videoBuffer !== undefined;
  }
}

/**
 * `requestMovingPhoto` 的数据回调 → Promise 收口。
 * ⚠️ 实测真机 jscrash：native 侧回调 `onDataPrepared` 时接收者丢失
 * （this === undefined），类字段写法（this.deliver）直接崩进程。
 * 回调体必须不碰 this —— 用闭包捕获 deliver 交付。
 */
function movingPhotoHandlerOf(deliver: (movingPhoto: photoAccessHelper.MovingPhoto) => void):
  photoAccessHelper.MediaAssetDataHandler<photoAccessHelper.MovingPhoto> {
  const handler: photoAccessHelper.MediaAssetDataHandler<photoAccessHelper.MovingPhoto> = {
    onDataPrepared: (data: photoAccessHelper.MovingPhoto): void => {
      deliver(data);
    }
  };
  return handler;
}

function readFileOrNull(path: string): ArrayBuffer | undefined {
  try {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const size = fileIo.statSync(file.fd).size;
      const buffer = new ArrayBuffer(size);
      fileIo.readSync(file.fd, buffer);
      return buffer;
    } finally {
      fileIo.closeSync(file);
    }
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'readFileOrNull failed: %{public}s', path);
    return undefined;
  }
}

function quietUnlink(path: string): void {
  try {
    fileIo.unlinkSync(path);
  } catch (err) {
    // 不存在 / 删不掉都不往上抛
  }
}

/**
 * 相册封面选取的产物（10_BUILD_MANUAL.md 3.4）。对应 iOS
 * `BookCustomizerView.load` 的 `data + downsample(data, maxPixels: 2400)`。
 * - `buffer`：静态图**原始字节**（动态照片取 still）。构图重裁从它现解干净源，
 *   不在裁过的图上再裁（iOS `pickedOriginal` 同款）
 * - `previewPixelMap`：长边 ≤2400 的解码（构图页显示用）
 */
export class PickedCoverSource {
  readonly buffer: ArrayBuffer;
  readonly previewPixelMap: image.PixelMap;

  constructor(buffer: ArrayBuffer, previewPixelMap: image.PixelMap) {
    this.buffer = buffer;
    this.previewPixelMap = previewPixelMap;
  }
}

/**
 * 从字节解码 PixelMap（等比缩到最长边 ≤ maxEdge，**不放大**）。
 * 正文选图走 2048（本文件），封面源走 2400（`COVER_SOURCE_MAX_EDGE`）。
 */
export async function decodeImageFromBuffer(buffer: ArrayBuffer,
  maxEdge: number): Promise<image.PixelMap | undefined> {
  let source: image.ImageSource | undefined = undefined;
  try {
    source = image.createImageSource(buffer);
    const info: image.ImageInfo = await source.getImageInfo();
    const width = info.size.width;
    const height = info.size.height;
    if (width <= 0 || height <= 0) {
      return undefined;
    }
    const scale = Math.min(1, maxEdge / Math.max(width, height));
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
    hilog.error(DOMAIN, TAG, 'decodeImageFromBuffer failed: %{public}s', JSON.stringify(err));
    return undefined;
  } finally {
    if (source !== undefined) {
      source.release().catch((err: Object): void => {
        hilog.error(DOMAIN, TAG, 'ImageSource release failed: %{public}s', JSON.stringify(err));
      });
    }
  }
}

export class PhotoLibraryPicker {
  /**
   * 拉起系统图库选择一张图片。
   * 用户取消 / 选图失败 / 解码失败 → undefined（调用方静默收场，不打扰用户）。
   * 选中动态照片 → 原图 + 视频原样字节；提取链路失败退普通静态图（R-PHOTO-04）。
   */
  static async pick(context: common.Context): Promise<PickedLibraryPhoto | undefined> {
    const uris = await PhotoLibraryPicker.pickUri();
    if (uris.length === 0) {
      return undefined;
    }
    const uri = uris[0];
    // 动态照片：URI → PhotoAsset 查子类型，是动态照片走原样提取链
    if (await PhotoLibraryPicker.isMovingPhotoUri(context, uri)) {
      const picked = await PhotoLibraryPicker.pickMovingPhoto(context, uri);
      if (picked !== undefined) {
        return picked;
      }
      // 提取失败：退静态图（下面照常走 uri 解码）
    }
    const pixelMap = await PhotoLibraryPicker.decodeFromUri(uri);
    if (pixelMap === undefined) {
      return undefined;
    }
    return new PickedLibraryPhoto(pixelMap, undefined, undefined);
  }

  /**
   * 拉起系统图库选一张**封面源图**（3.4）：拿静态图原始字节 + ≤2400 预览解码。
   * 用户取消 / 读不到 / 解码失败 → undefined（调用方静默收场，与 2.6 拍板一致）。
   * 动态照片取 still 原始字节（R-PHOTO-03 的意图：不重编码原始数据）；
   * 提取失败退普通静态图（R-PHOTO-04 兜底）。
   */
  static async pickCoverSource(context: common.Context): Promise<PickedCoverSource | undefined> {
    const uris = await PhotoLibraryPicker.pickUri();
    if (uris.length === 0) {
      return undefined;
    }
    const uri = uris[0];
    if (await PhotoLibraryPicker.isMovingPhotoUri(context, uri)) {
      const moving = await PhotoLibraryPicker.pickMovingPhoto(context, uri);
      if (moving !== undefined && moving.stillBuffer !== undefined) {
        const preview = await decodeImageFromBuffer(moving.stillBuffer, COVER_SOURCE_MAX_EDGE);
        if (preview !== undefined) {
          return new PickedCoverSource(moving.stillBuffer, preview);
        }
      }
      // 提取失败：退普通静态图（下面照常走 uri 原始字节）
    }
    const buffer = PhotoLibraryPicker.readUriBytes(uri);
    if (buffer === undefined) {
      return undefined;
    }
    const preview = await decodeImageFromBuffer(buffer, COVER_SOURCE_MAX_EDGE);
    if (preview === undefined) {
      return undefined;
    }
    return new PickedCoverSource(buffer, preview);
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

  /** URI 对应资产是不是动态照片（查不到资产一律按普通照片处理） */
  private static async isMovingPhotoUri(context: common.Context, uri: string): Promise<boolean> {
    try {
      const asset = await PhotoLibraryPicker.assetFromUri(context, uri);
      if (asset === undefined) {
        return false;
      }
      const subtype = asset.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE);
      return subtype === photoAccessHelper.PhotoSubtype.MOVING_PHOTO;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'isMovingPhotoUri failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 动态照片原样提取（iOS `PhotoInsertFlow` 动态分支同款意图）：
   * `requestMovingPhoto` → `MovingPhoto.requestContent` 写 cacheDir 临时文件 → 读回字节 →
   * 清临时文件。静态图解码 ≤2048 做预览；失败返回 undefined（退普通照片）。
   */
  private static async pickMovingPhoto(context: common.Context,
    uri: string): Promise<PickedLibraryPhoto | undefined> {
    const asset = await PhotoLibraryPicker.assetFromUri(context, uri);
    if (asset === undefined) {
      return undefined;
    }
    let movingPhoto: photoAccessHelper.MovingPhoto;
    try {
      movingPhoto = await new Promise<photoAccessHelper.MovingPhoto>(
        (resolve: (movingPhoto: photoAccessHelper.MovingPhoto) => void,
          reject: (reason: BusinessError) => void): void => {
          const handler = movingPhotoHandlerOf(resolve);
          const options: photoAccessHelper.RequestOptions = {
            deliveryMode: photoAccessHelper.DeliveryMode.BALANCE_MODE
          };
          photoAccessHelper.MediaAssetManager.requestMovingPhoto(context, asset, options, handler)
            .catch((err: BusinessError): void => {
              reject(err);
            });
        });
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'requestMovingPhoto failed: %{public}d %{public}s', e.code, e.message);
      return undefined;
    }
    const stillPath = `${context.cacheDir}/picker_moving_still.tmp`;
    const videoPath = `${context.cacheDir}/picker_moving_video.tmp`;
    quietUnlink(stillPath);
    quietUnlink(videoPath);
    try {
      await movingPhoto.requestContent(stillPath, videoPath);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'requestContent failed: %{public}d %{public}s', e.code, e.message);
      quietUnlink(stillPath);
      quietUnlink(videoPath);
      return undefined;
    }
    const still = readFileOrNull(stillPath);
    const video = readFileOrNull(videoPath);
    quietUnlink(stillPath);
    quietUnlink(videoPath);
    if (still === undefined || video === undefined) {
      hilog.error(DOMAIN, TAG, 'moving photo temp file missing');
      return undefined;
    }
    const pixelMap = await decodeImageFromBuffer(still, DECODE_MAX_EDGE);
    if (pixelMap === undefined) {
      return undefined;
    }
    return new PickedLibraryPhoto(pixelMap, still, video);
  }

  /** Picker 临时授权的 URI → PhotoAsset（官方 `getAssets` + URI 谓词查询） */
  private static async assetFromUri(context: common.Context,
    uri: string): Promise<photoAccessHelper.PhotoAsset | undefined> {
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const predicates = new dataSharePredicates.DataSharePredicates();
      predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri);
      const fetchOption: photoAccessHelper.FetchOptions = {
        fetchColumns: [photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE],
        predicates: predicates
      };
      const fetchResult = await helper.getAssets(fetchOption);
      try {
        return await fetchResult.getFirstObject();
      } finally {
        fetchResult.close();
      }
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'assetFromUri failed: %{public}d %{public}s', e.code, e.message);
      return undefined;
    }
  }

  /** 从 uri 读出原始字节（选图 / 封面源共用） */
  private static readUriBytes(uri: string): ArrayBuffer | undefined {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const size = fileIo.statSync(file.fd).size;
      const buffer = new ArrayBuffer(size);
      fileIo.readSync(file.fd, buffer);
      return buffer;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'readUriBytes failed: %{public}s', JSON.stringify(err));
      return undefined;
    } finally {
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (err) {
          hilog.error(DOMAIN, TAG, 'closeSync failed: %{public}s', JSON.stringify(err));
        }
      }
    }
  }

  /** 从 uri 读文件 → 解码 PixelMap（最长边 ≤2048，等比缩小、不放大） */
  private static async decodeFromUri(uri: string): Promise<image.PixelMap | undefined> {
    const buffer = PhotoLibraryPicker.readUriBytes(uri);
    if (buffer === undefined) {
      return undefined;
    }
    return decodeImageFromBuffer(buffer, DECODE_MAX_EDGE);
  }
}
