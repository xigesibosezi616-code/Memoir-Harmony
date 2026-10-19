/**
 * 相机照片的裁切与落盘链（10_BUILD_MANUAL.md 2.9）。对应 iOS `PhotoInsertFlow.insert`
 * 的相机分支 + `PaperCameraView.capture` 里的 `squareCropped`。
 *
 * - 裁切**只用于显示**：拍照产物（原图 / 动态视频）原样字节由 CameraSession 交回，
 *   这里把原图字节解码成**中心方形** PixelMap（等比缩到最长边 ≤2048，与相册选图
 *   2.6 的解码上限一致）供相纸预览与正文显示
 * - 落盘链（R-PHOTO-03）：显示图 `photo_<uuid8>.jpg` 走 saveImage（JPEG q85 重编码）；
 *   动态照片配对文件 `photo_<同>_full.jpg`（原图）+ `photo_<同>.mp4`（视频）走
 *   saveData **原样字节**——重编码会丢配对标识且失败是静默的
 * - 动态配对落盘失败 → 退化成普通照片（删除半成品，只交显示图），
 *   iOS「相机 Live Photo 落盘失败，按普通照片处理」同款
 */
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PhotoPaperIO } from './PhotoPaperIO';
import { CameraShot } from './CameraSession';
import { generateUuid } from '../models/Uuid';

const DOMAIN = 0x0000;
const TAG = 'CameraPhotoFiles';

/** 方形显示图最长边（2048 与相册选图解码上限一致，见 PhotoLibraryPicker） */
const SQUARE_MAX_EDGE = 2048;

/** 中心方形裁切区域（纯逻辑，可单测注入） */
export class SquareRegion {
  readonly x: number;
  readonly y: number;
  readonly side: number;

  constructor(x: number, y: number, side: number) {
    this.x = x;
    this.y = y;
    this.side = side;
  }
}

/** 取 w×h 图像的中心正方形区域（边长 = 短边，左上角居中偏移） */
export function centerSquareRegion(width: number, height: number): SquareRegion {
  const side = Math.min(width, height);
  return new SquareRegion(Math.floor((width - side) / 2), Math.floor((height - side) / 2), side);
}

/** 相机一次拍照落盘后的文件三件套 */
export class CameraPhotoFiles {
  /** 方形裁切显示图 photo_&lt;uuid8&gt;.jpg */
  readonly displayFilename: string;
  /** 动态照片原图 photo_&lt;uuid8&gt;_full.jpg（原样字节；普通照片 undefined） */
  readonly fullStillFilename: string | undefined;
  /** 动态照片视频 photo_&lt;uuid8&gt;.mp4（原样字节；普通照片 undefined） */
  readonly videoFilename: string | undefined;

  constructor(displayFilename: string, fullStillFilename: string | undefined,
    videoFilename: string | undefined) {
    this.displayFilename = displayFilename;
    this.fullStillFilename = fullStillFilename;
    this.videoFilename = videoFilename;
  }

  /** 全部落盘的文件名（调用方记账：放弃 / 删除时清理） */
  allFilenames(): string[] {
    const names: string[] = [this.displayFilename];
    if (this.fullStillFilename !== undefined) {
      names.push(this.fullStillFilename);
    }
    if (this.videoFilename !== undefined) {
      names.push(this.videoFilename);
    }
    return names;
  }
}

/**
 * 原图字节 → 中心方形显示图（最长边 ≤2048）。
 * 解码失败 / 尺寸非法 → undefined（调用方按拍照失败收场）。
 */
export async function decodeCenterSquare(buffer: ArrayBuffer): Promise<image.PixelMap | undefined> {
  let source: image.ImageSource | undefined = undefined;
  try {
    source = image.createImageSource(buffer);
    const info: image.ImageInfo = await source.getImageInfo();
    const width = info.size.width;
    const height = info.size.height;
    if (width <= 0 || height <= 0) {
      return undefined;
    }
    const region = centerSquareRegion(width, height);
    const scale = Math.min(1, SQUARE_MAX_EDGE / region.side);
    const options: image.DecodingOptions = {
      desiredRegion: {
        x: region.x,
        y: region.y,
        size: { width: region.side, height: region.side }
      },
      // 先裁方再缩到 ≤2048（同帧缩放会把裁切窗口一起等比缩，区域语义就错了）
      cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST
    };
    if (scale < 1) {
      options.desiredSize = {
        width: Math.max(1, Math.round(region.side * scale)),
        height: Math.max(1, Math.round(region.side * scale))
      };
    }
    return await source.createPixelMap(options);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'decodeCenterSquare failed: %{public}s', JSON.stringify(err));
    return undefined;
  } finally {
    if (source !== undefined) {
      source.release().catch((): void => {
      });
    }
  }
}

/**
 * 相机落盘链（iOS `PhotoInsertFlow.insert` 相机分支）：
 * 显示图（裁过的方图）重编码落盘；动态照片的原图 + 视频原样落盘配对。
 * 显示图落盘失败 → undefined（整体算失败）；配对失败 → 退化普通照片。
 */
export async function saveCameraShot(io: PhotoPaperIO, shot: CameraShot,
  squarePixelMap: image.PixelMap): Promise<CameraPhotoFiles | undefined> {
  const base = generateUuid().substring(0, 8);
  const displayFilename = `photo_${base}.jpg`;
  if (!await io.saveImage(squarePixelMap, displayFilename)) {
    hilog.error(DOMAIN, TAG, 'display save failed %{public}s', displayFilename);
    return undefined;
  }
  let fullStillFilename: string | undefined = undefined;
  let videoFilename: string | undefined = undefined;
  let videoBuffer: ArrayBuffer | undefined = undefined;
  if (shot.videoReady !== undefined) {
    // 动态视频后台提取在此接上（通常审阅期间已就绪；失败 resolve undefined）
    videoBuffer = await shot.videoReady;
  }
  if (videoBuffer !== undefined) {
    const stillName = `photo_${base}_full.jpg`;
    const movieName = `photo_${base}.mp4`;
    const stillOk = await io.saveData(shot.stillBuffer, stillName);
    const videoOk = await io.saveData(videoBuffer, movieName);
    if (stillOk && videoOk) {
      fullStillFilename = stillName;
      videoFilename = movieName;
    } else {
      // 配对文件缺一份就配不起来：删掉半成品，按普通照片处理（iOS 同款）
      hilog.error(DOMAIN, TAG, 'moving pair save failed, fallback to still %{public}s', base);
      if (stillOk) {
        io.deleteImage(stillName);
      }
      if (videoOk) {
        io.deleteImage(movieName);
      }
    }
  }
  return new CameraPhotoFiles(displayFilename, fullStillFilename, videoFilename);
}
