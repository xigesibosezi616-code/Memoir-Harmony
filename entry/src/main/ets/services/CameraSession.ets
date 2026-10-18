/**
 * 尺素相机会话封装（10_BUILD_MANUAL.md 2.9）。对应 iOS `Views/Camera/CameraSession.swift`。
 *
 * - 自建会话（CameraKit PhotoSession）：预览走 XComponent surface，成像走系统默认管线
 *   —— 不加滤镜、不做后期，等同原相机直出
 * - 动态照片：会话启动后 `isMovingPhotoSupported` 查询 → `enableMovingPhoto(true)` 使能
 *   （拍摄动态照片需要麦克风权限，否则视频没声音；权限由页面在开相机前申请）
 * - 一次拍照产物（CameraShot）：静态图 / 动态视频一律**原样字节**（R-PHOTO-03：
 *   重编码会丢配对标识，且失败是静默的）；方形裁切只用于显示，由视图层另做
 * - 存相册（R-PHOTO-06）：`photoAssetAvailable` 给的 PhotoAsset 走官方相机链路
 *   `MediaAssetChangeRequest.saveCameraPhoto`（免权限），失败只记日志不影响日记
 * - 沙盒提取：`requestMovingPhoto` → `MovingPhoto.requestContent` 把原图 + 视频写进
 *   cacheDir 临时文件再读回；动态链路失败退 `requestImageData` 拿静态图（R-PHOTO-04
 *   静态兜底），再失败才算拍照失败
 * - 闪光三态 / 变焦（夹设备范围与 5× 上限）/ 前后摄切换（拆会话重建，surface 不变）
 */
import { camera } from '@kit.CameraKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'CameraSession';

/** 变焦上限（iOS 同款 5×：数码放大再高画质劣化明显，不给用户踩坑的机会） */
export const MAX_ZOOM_RATIO: number = 5;

/** 闪光灯意向三态（iOS `FlashSetting`）。UI 循环顺序：自动 → 开 → 关 */
export enum FlashSetting {
  Auto = 'auto',
  On = 'on',
  Off = 'off'
}

/** 点一下走到下一个状态（自动最常用、关闭最少用，iOS 同序） */
export function nextFlashSetting(cur: FlashSetting): FlashSetting {
  switch (cur) {
    case FlashSetting.Auto:
      return FlashSetting.On;
    case FlashSetting.On:
      return FlashSetting.Off;
    default:
      return FlashSetting.Auto;
  }
}

/** 三态 → 相机会话闪光模式（枚举成员是 FLASH_MODE_CLOSE/OPEN/AUTO） */
export function flashModeOf(setting: FlashSetting): camera.FlashMode {
  switch (setting) {
    case FlashSetting.On:
      return camera.FlashMode.FLASH_MODE_OPEN;
    case FlashSetting.Off:
      return camera.FlashMode.FLASH_MODE_CLOSE;
    default:
      return camera.FlashMode.FLASH_MODE_AUTO;
  }
}

/** 把倍率夹进 [range[0], range[1]]；range 不足两位原样退回（兜底） */
export function clampZoomRatio(ratio: number, range: Array<number>): number {
  if (range.length < 2) {
    return ratio;
  }
  const min = Math.min(range[0], range[1]);
  const max = Math.max(range[0], range[1]);
  return Math.min(Math.max(ratio, min), max);
}

/** 一次拍照的产物（iOS `CameraShot`）：原样字节，绝不重编码（R-PHOTO-03） */
export class CameraShot {
  readonly stillBuffer: ArrayBuffer;
  readonly videoBuffer: ArrayBuffer | undefined;

  constructor(stillBuffer: ArrayBuffer, videoBuffer: ArrayBuffer | undefined) {
    this.stillBuffer = stillBuffer;
    this.videoBuffer = videoBuffer;
  }

  get isMovingPhoto(): boolean {
    return this.videoBuffer !== undefined;
  }
}

/** 动态照片提取结果（cacheDir 临时文件读回的两份字节） */
class MovingPhotoFiles {
  readonly still: ArrayBuffer;
  readonly video: ArrayBuffer | undefined;

  constructor(still: ArrayBuffer, video: ArrayBuffer | undefined) {
    this.still = still;
    this.video = video;
  }
}

/** `requestMovingPhoto` 的数据回调 → Promise 收口 */
class MovingPhotoDataHandler implements photoAccessHelper.MediaAssetDataHandler<photoAccessHelper.MovingPhoto> {
  private deliver: (movingPhoto: photoAccessHelper.MovingPhoto) => void;

  constructor(deliver: (movingPhoto: photoAccessHelper.MovingPhoto) => void) {
    this.deliver = deliver;
  }

  onDataPrepared(data: photoAccessHelper.MovingPhoto): void {
    this.deliver(data);
  }
}

/** `requestImageData` 的数据回调 → Promise 收口 */
class ImageDataHandler implements photoAccessHelper.MediaAssetDataHandler<ArrayBuffer> {
  private deliver: (data: ArrayBuffer) => void;

  constructor(deliver: (data: ArrayBuffer) => void) {
    this.deliver = deliver;
  }

  onDataPrepared(data: ArrayBuffer): void {
    this.deliver(data);
  }
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

export class CameraSession {
  /** 拍到一张（静态图原样字节 + 动态视频原样字节，普通照片 video 为 undefined） */
  onShot: (shot: CameraShot) => void = (_shot: CameraShot): void => {};
  /** 拍照失败 / 提取失败（视图提示重试，取景不中断） */
  onCaptureFailed: () => void = (): void => {};

  private context: common.UIAbilityContext | undefined = undefined;
  private manager: camera.CameraManager | undefined = undefined;
  private session: camera.PhotoSession | undefined = undefined;
  private cameraInput: camera.CameraInput | undefined = undefined;
  private previewOutput: camera.PreviewOutput | undefined = undefined;
  private photoOutput: camera.PhotoOutput | undefined = undefined;
  private device: camera.CameraDevice | undefined = undefined;
  private surfaceId: string = '';
  private movingPhotoEnabled: boolean = false;
  /** 取景画面宽高比（会话起来后 = 实际预览流比例；未开 = 4:3 兜底） */
  private previewAspectValue: number = 4 / 3;

  get previewAspect(): number {
    return this.previewAspectValue;
  }

  /** 当前是否前摄（视图决定翻转图标 / 提示） */
  isFrontCamera(): boolean {
    return this.device !== undefined &&
      this.device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT;
  }

  /**
   * 打开相机会话。`surfaceId` = 取景 XComponent 的 surface；
   * `context` = 页面宿主上下文。失败返回 false（视图渲染「相机不可用」）。
   */
  async open(context: common.UIAbilityContext, surfaceId: string): Promise<boolean> {
    this.context = context;
    this.surfaceId = surfaceId;
    return this.setupSession();
  }

  /** 关闭并释放整条会话链（视图退场 / 页面销毁必调，相机是独占资源） */
  async close(): Promise<void> {
    await this.teardownSession();
    this.device = undefined;
    this.manager = undefined;
    this.movingPhotoEnabled = false;
  }

  /** 拍一张（产物经 onShot / onCaptureFailed 回来；iOS `capture` 同款异步收口） */
  capture(): void {
    const photoOutput = this.photoOutput;
    if (photoOutput === undefined) {
      return;
    }
    try {
      const setting: camera.PhotoCaptureSetting = {
        quality: camera.QualityLevel.QUALITY_LEVEL_HIGH
      };
      photoOutput.capture(setting).catch((err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'capture failed: %{public}d %{public}s', err.code, err.message);
        this.onCaptureFailed();
      });
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'capture threw: %{public}d %{public}s', e.code, e.message);
      this.onCaptureFailed();
    }
  }

  /** 闪光三态（会话级设置，iOS `setFlash` 同款「意向」—— 能不能闪由设备决定） */
  setFlash(setting: FlashSetting): void {
    const session = this.session;
    if (session === undefined) {
      return;
    }
    try {
      session.setFlashMode(flashModeOf(setting));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setFlashMode failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 当前镜头有没有闪光单元（前摄通常没有；视图据此决定显不显示闪光键） */
  hasFlashUnit(): boolean {
    const session = this.session;
    if (session === undefined) {
      return false;
    }
    try {
      return session.hasFlash();
    } catch (err) {
      return false;
    }
  }

  /** 变焦可调上限：设备范围上沿与 5× 取小（拖动条行程用） */
  maxZoomRatio(): number {
    const session = this.session;
    if (session === undefined) {
      return MAX_ZOOM_RATIO;
    }
    try {
      return clampZoomRatio(MAX_ZOOM_RATIO, session.getZoomRatioRange());
    } catch (err) {
      return MAX_ZOOM_RATIO;
    }
  }

  /** 设置变焦倍率（内部按设备范围夹取，越界不抛） */
  setZoom(ratio: number): void {
    const session = this.session;
    if (session === undefined) {
      return;
    }
    try {
      session.setZoomRatio(clampZoomRatio(ratio, session.getZoomRatioRange()));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setZoomRatio failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 当前镜头是否支持动态照片（闪光 / 相纸条旁的说明用；能力查询） */
  isMovingPhotoSupported(): boolean {
    const photoOutput = this.photoOutput;
    if (photoOutput === undefined) {
      return false;
    }
    try {
      return photoOutput.isMovingPhotoSupported();
    } catch (err) {
      return false;
    }
  }

  /**
   * 前后摄切换：拆掉当前会话换另一颗镜头（surface 不变，预览自动接回）。
   * 换失败时尽力回滚原镜头；两头都起不来返回 false（视图渲染「相机不可用」）。
   */
  async flip(): Promise<boolean> {
    const manager = this.manager;
    const current = this.device;
    if (manager === undefined || current === undefined) {
      return false;
    }
    let next: camera.CameraDevice | undefined = undefined;
    try {
      const devices = manager.getSupportedCameras();
      for (const candidate of devices) {
        if (candidate.cameraPosition !== current.cameraPosition) {
          next = candidate;
          break;
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'flip getSupportedCameras failed: %{public}s', JSON.stringify(err));
      return false;
    }
    if (next === undefined) {
      return false; // 单摄设备：安静地不响应
    }
    await this.teardownSession();
    this.device = next;
    const ok = await this.setupSession();
    if (!ok) {
      // 新镜头起不来：回滚旧镜头，避免留下黑屏预览
      this.device = current;
      await this.setupSession();
    }
    return ok;
  }

  // ---- 内部：会话装配 / 拆卸 ----

  private async setupSession(): Promise<boolean> {
    const context = this.context;
    const device = this.device;
    if (context === undefined || device === undefined || this.surfaceId.length === 0) {
      return false;
    }
    try {
      const manager = camera.getCameraManager(context);
      this.manager = manager;
      const capability = manager.getSupportedOutputCapability(device);
      if (capability.previewProfiles.length === 0 || capability.photoProfiles.length === 0) {
        hilog.error(DOMAIN, TAG, 'no preview/photo profile');
        return false;
      }
      const previewProfile = capability.previewProfiles[0];
      const photoProfile = capability.photoProfiles[0];
      const previewOutput = manager.createPreviewOutput(previewProfile, this.surfaceId);
      const photoOutput = manager.createPhotoOutput(photoProfile);
      const cameraInput = manager.createCameraInput(device);
      await cameraInput.open();
      const session = manager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
      session.beginConfig();
      session.addInput(cameraInput);
      session.addOutput(previewOutput);
      session.addOutput(photoOutput);
      await session.commitConfig();
      await session.start();
      // 动态照片：会话提交并启动之后查询使能（官方顺序，先查后开）
      let moving = false;
      try {
        if (photoOutput.isMovingPhotoSupported()) {
          photoOutput.enableMovingPhoto(true);
          moving = true;
        }
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'enableMovingPhoto failed: %{public}s', JSON.stringify(err));
      }
      this.movingPhotoEnabled = moving;
      // 前摄按预览镜像出图（iOS 同款：拍出来和看到的左右一致）
      try {
        if (photoOutput.isMirrorSupported()) {
          photoOutput.enableMirror(
            device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT);
        }
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'enableMirror failed: %{public}s', JSON.stringify(err));
      }
      this.cameraInput = cameraInput;
      this.previewOutput = previewOutput;
      this.photoOutput = photoOutput;
      this.session = session;
      if (previewProfile.size.height > 0) {
        this.previewAspectValue = previewProfile.size.width / previewProfile.size.height;
      }
      this.registerPhotoListener(photoOutput);
      hilog.info(DOMAIN, TAG, 'session started moving=%{public}d', moving ? 1 : 0);
      return true;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'setupSession failed: %{public}d %{public}s', e.code, e.message);
      return false;
    }
  }

  private async teardownSession(): Promise<void> {
    const session = this.session;
    const previewOutput = this.previewOutput;
    const photoOutput = this.photoOutput;
    const cameraInput = this.cameraInput;
    this.session = undefined;
    this.previewOutput = undefined;
    this.photoOutput = undefined;
    this.cameraInput = undefined;
    this.movingPhotoEnabled = false;
    if (session !== undefined) {
      session.release().catch((): void => {
      });
    }
    if (previewOutput !== undefined) {
      previewOutput.release().catch((): void => {
      });
    }
    if (photoOutput !== undefined) {
      photoOutput.release().catch((): void => {
      });
    }
    if (cameraInput !== undefined) {
      cameraInput.close().catch((): void => {
      });
    }
  }

  /** 拍照回调：存相册（官方相机链路，免权限）+ 沙盒提取后交 CameraShot */
  private registerPhotoListener(photoOutput: camera.PhotoOutput): void {
    photoOutput.on('photoAssetAvailable',
      (err: BusinessError, asset: photoAccessHelper.PhotoAsset): void => {
        if (err) {
          hilog.error(DOMAIN, TAG, 'photoAssetAvailable err: %{public}s', JSON.stringify(err));
          this.onCaptureFailed();
          return;
        }
        this.saveToGallery(asset);
        this.extractShot(asset);
      });
  }

  /** 拍下就存：官方相机链路 `saveCameraPhoto`，二阶段图就绪后媒体库自动替换（免权限） */
  private saveToGallery(asset: photoAccessHelper.PhotoAsset): void {
    const context = this.context;
    if (context === undefined) {
      return;
    }
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const request = new photoAccessHelper.MediaAssetChangeRequest(asset);
      request.saveCameraPhoto();
      helper.applyChanges(request).then((): void => {
        hilog.info(DOMAIN, TAG, 'saveCameraPhoto ok');
      }).catch((err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'saveCameraPhoto failed: %{public}d %{public}s', err.code, err.message);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveToGallery threw: %{public}s', JSON.stringify(err));
    }
  }

  /** 沙盒提取：动态链路（原图+视频）优先，失败退静态图（R-PHOTO-04 兜底） */
  private async extractShot(asset: photoAccessHelper.PhotoAsset): Promise<void> {
    const context = this.context;
    if (context === undefined) {
      this.onCaptureFailed();
      return;
    }
    let still: ArrayBuffer | undefined = undefined;
    let video: ArrayBuffer | undefined = undefined;
    if (this.movingPhotoEnabled) {
      const files = await CameraSession.extractMovingPhoto(context, asset);
      if (files !== undefined) {
        still = files.still;
        video = files.video;
      }
    }
    if (still === undefined) {
      still = await CameraSession.requestStillData(context, asset);
    }
    if (still === undefined) {
      hilog.error(DOMAIN, TAG, 'extractShot: no still data');
      this.onCaptureFailed();
      return;
    }
    this.onShot(new CameraShot(still, video));
  }

  /** 动态照片 → cacheDir 临时文件 → 读回字节 → 清临时文件；失败返回 undefined */
  private static async extractMovingPhoto(context: common.UIAbilityContext,
    asset: photoAccessHelper.PhotoAsset): Promise<MovingPhotoFiles | undefined> {
    let movingPhoto: photoAccessHelper.MovingPhoto;
    try {
      movingPhoto = await CameraSession.requestMovingPhotoObject(context, asset);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'requestMovingPhoto failed: %{public}d %{public}s', e.code, e.message);
      return undefined;
    }
    const stillPath = `${context.cacheDir}/camera_moving_still.tmp`;
    const videoPath = `${context.cacheDir}/camera_moving_video.tmp`;
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
    if (still === undefined) {
      return undefined;
    }
    return new MovingPhotoFiles(still, video);
  }

  private static requestMovingPhotoObject(context: common.UIAbilityContext,
    asset: photoAccessHelper.PhotoAsset): Promise<photoAccessHelper.MovingPhoto> {
    return new Promise<photoAccessHelper.MovingPhoto>(
      (resolve: (movingPhoto: photoAccessHelper.MovingPhoto) => void,
        reject: (reason: BusinessError) => void): void => {
        const handler = new MovingPhotoDataHandler(resolve);
        const options: photoAccessHelper.RequestOptions = {
          deliveryMode: photoAccessHelper.DeliveryMode.BALANCE_MODE
        };
        photoAccessHelper.MediaAssetManager.requestMovingPhoto(context, asset, options, handler)
          .catch((err: BusinessError): void => {
            reject(err);
          });
      });
  }

  /** 静态图兜底（官方相机文档「处理方式二」；拿原始静态字节） */
  private static requestStillData(context: common.UIAbilityContext,
    asset: photoAccessHelper.PhotoAsset): Promise<ArrayBuffer | undefined> {
    return new Promise<ArrayBuffer | undefined>(
      (resolve: (data: ArrayBuffer | undefined) => void): void => {
        const handler = new ImageDataHandler((data: ArrayBuffer): void => {
          resolve(data);
        });
        const options: photoAccessHelper.RequestOptions = {
          deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE
        };
        photoAccessHelper.MediaAssetManager.requestImageData(context, asset, options, handler)
          .catch((err: BusinessError): void => {
            hilog.error(DOMAIN, TAG, 'requestImageData failed: %{public}d %{public}s',
              err.code, err.message);
            resolve(undefined);
          });
      });
  }
}
