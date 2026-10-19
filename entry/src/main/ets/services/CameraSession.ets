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
 * - 沙盒提取：`requestMovingPhoto` → `MovingPhoto.requestContent` 拿原样字节。
 *   **静图先行**：只探 IMAGE 轨，一到手立刻交付 UI（相纸出纸不等视频）；
 *   视频转后台继续提取（`CameraShot.videoReady`），确认落盘时自然接上，
 *   拿不到 → 落盘退化普通照片。静图全败退 `requestImageData`（R-PHOTO-04
 *   静态兜底），再失败才算拍照失败
 * - 闪光三态 / 变焦（夹设备范围与 5× 上限）/ 前后摄切换（拆会话重建，surface 不变）
 * - 毫秒计时：快门→资产→入库→静图→出纸→视频逐段写 camera_timing.log（CameraPerfLog）
 */
import { camera } from '@kit.CameraKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CameraPerfLog } from './CameraPerfLog';

const DOMAIN = 0x0000;
const TAG = 'CameraSession';

/** 机型变焦范围未知 / 会话异常时的变焦上限兜底值（正常走设备 `getZoomRatioRange` 上沿） */
export const MAX_ZOOM_RATIO: number = 5;

/** 取景目标帧率：实测不显式设置时 HAL 默认 15fps（Mate X6 前后摄皆然），必须拉到 30 */
const PREVIEW_TARGET_FPS: number = 30;

/** 闪光灯意向三态（iOS `FlashSetting`）。UI 三选托盘：自动 / 闪光开 / 闪光关 */
export enum FlashSetting {
  Auto = 'auto',
  On = 'on',
  Off = 'off'
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

/** 离 ratio 最近的预设档（自由拖动时的高亮 / 跨档震动用）；空列表退 1×；骑中间取后档 */
export function nearestZoomPreset(ratio: number, presets: Array<number>): number {
  let best: number = presets.length > 0 ? presets[0] : 1;
  let bestDist: number = Number.MAX_VALUE;
  for (let i = 0; i < presets.length; i++) {
    const dist: number = Math.abs(presets[i] - ratio);
    if (dist <= bestDist) {
      bestDist = dist;
      best = presets[i];
    }
  }
  return best;
}

/** 自由变焦文案：<10 保留一位小数（2.6×），≥10 取整（11×） */
export function formatZoomLabel(ratio: number): string {
  if (ratio >= 9.95) {
    return Math.round(ratio).toFixed(0);
  }
  return (Math.round(ratio * 10) / 10).toFixed(1);
}

/**
 * 华为相机式档位（自适应设备范围）：超广角 0.5×（下限够低才给）+ 1× +
 * 3.5× / 5× / 10×（上限够才给）；设备弱（前摄）退到只剩 1×。
 */
export function zoomPresetsForRange(min: number, max: number): Array<number> {
  const presets: Array<number> = [];
  if (min <= 0.75) {
    presets.push(0.5);
  }
  presets.push(1);
  if (max >= 3.5) {
    presets.push(3.5);
  }
  if (max >= 5) {
    presets.push(5);
  }
  if (max >= 10) {
    presets.push(10);
  }
  return presets;
}

/**
 * 从镜头位姿列表里挑默认镜头：优先后摄（拍照主视角），没有后摄退第一个。
 * 返回索引；列表空返回 -1。`open()` 初次装配用，`flip()` 不走它。
 */
export function defaultCameraIndex(positions: Array<camera.CameraPosition>): number {
  for (let i = 0; i < positions.length; i++) {
    if (positions[i] === camera.CameraPosition.CAMERA_POSITION_BACK) {
      return i;
    }
  }
  return positions.length > 0 ? 0 : -1;
}

/** 位姿相同的镜头在列表里的全部下标（多输入会话挑同位姿镜头组用） */
export function indexesOfPosition(positions: Array<camera.CameraPosition>,
  position: camera.CameraPosition): Array<number> {
  const indexes: Array<number> = [];
  for (let i = 0; i < positions.length; i++) {
    if (positions[i] === position) {
      indexes.push(i);
    }
  }
  return indexes;
}

/**
 * 预览流档位匹配（官方 faqs-camera-7/12：预览分辨率与显示区匹配，过大徒增
 * 合成负担拖不动）。挑短边最接近显示区短边的一个；列表空返回 undefined。
 */
export function bestPreviewProfile(profiles: Array<camera.Profile>,
  targetShortSidePx: number): camera.Profile | undefined {
  let best: camera.Profile | undefined = undefined;
  let bestDiff: number = Number.MAX_VALUE;
  for (const profile of profiles) {
    const shortSide: number = Math.min(profile.size.width, profile.size.height);
    const diff: number = Math.abs(shortSide - targetShortSidePx);
    if (diff < bestDiff) {
      bestDiff = diff;
      best = profile;
    }
  }
  return best;
}

/**
 * 拍照档位选择：挑**像素面积最大**的一档（系统相机同款全分辨率出图）。
 * ⚠️ 实测踩坑：`photoProfiles[0]` 是列表最小档（Mate X6 上 480×480），
 * 直接取首项会把所有照片拍成 480×480 糊图。
 */
export function bestPhotoProfile(profiles: Array<camera.Profile>): camera.Profile | undefined {
  let best: camera.Profile | undefined = undefined;
  let bestArea: number = 0;
  for (const profile of profiles) {
    const area: number = profile.size.width * profile.size.height;
    if (area > bestArea) {
      bestArea = area;
      best = profile;
    }
  }
  return best;
}

/**
 * 一次拍照的产物（iOS `CameraShot`）：原样字节，绝不重编码（R-PHOTO-03）。
 * 静图先行交付出纸；动态视频**后台补齐**——`videoReady` 是提取中的 Promise，
 * 落盘链（saveCameraShot）await 它拿字节，失败 resolve undefined 退化普通照片。
 */
export class CameraShot {
  readonly stillBuffer: ArrayBuffer;
  readonly videoReady: Promise<ArrayBuffer | undefined> | undefined;

  constructor(stillBuffer: ArrayBuffer,
    videoReady: Promise<ArrayBuffer | undefined> | undefined) {
    this.stillBuffer = stillBuffer;
    this.videoReady = videoReady;
  }

  get isMovingPhoto(): boolean {
    return this.videoReady !== undefined;
  }
}

/** 一次拍照的毫秒计时（快门按下为 0 点；各阶段写 CameraPerfLog） */
class CaptureTiming {
  readonly id: number;
  private readonly startMs: number;

  constructor(id: number) {
    this.id = id;
    this.startMs = Date.now();
  }

  elapsedMs(): number {
    return Date.now() - this.startMs;
  }
}

/**
 * `requestMovingPhoto` / `requestImageData` 的数据回调收口工厂。
 * ⚠️ 实测真机 jscrash：native 侧回调 `onDataPrepared` 时接收者丢失
 * （this === undefined），类字段写法（this.deliver）直接崩进程。
 * 回调体必须不碰 this —— 用闭包捕获 deliver 交付。
 */
function mediaHandlerOf<T>(deliver: (data: T) => void): photoAccessHelper.MediaAssetDataHandler<T> {
  const handler: photoAccessHelper.MediaAssetDataHandler<T> = {
    onDataPrepared: (data: T): void => {
      deliver(data);
    }
  };
  return handler;
}

export class CameraSession {
  /** 拍到一张（静态图原样字节 + 动态视频原样字节，普通照片 video 为 undefined） */
  onShot: (shot: CameraShot) => void = (_shot: CameraShot): void => {};
  /** 拍照失败 / 提取失败（视图提示重试，取景不中断） */
  onCaptureFailed: () => void = (): void => {};

  private context: common.UIAbilityContext | undefined = undefined;
  private manager: camera.CameraManager | undefined = undefined;
  private session: camera.PhotoSession | undefined = undefined;
  private cameraInputs: Array<camera.CameraInput> = [];
  private previewOutput: camera.PreviewOutput | undefined = undefined;
  private photoOutput: camera.PhotoOutput | undefined = undefined;
  private device: camera.CameraDevice | undefined = undefined;
  private surfaceId: string = '';
  private movingPhotoEnabled: boolean = false;
  /** 取景画面宽高比（会话起来后 = 实际预览流比例；未开 = 4:3 兜底） */
  private previewAspectValue: number = 4 / 3;
  /**
   * 变焦范围缓存 [min, max]：会话启动后查一次 `getZoomRatioRange` 存下，
   * 热路径（拖动 / 捏合每次手势更新）只读缓存——官方示例同款，避免高频 JNI。
   */
  private zoomRangeCache: Array<number> = [1, MAX_ZOOM_RATIO];
  /** 预览显示区短边（px）：setupSession 挑预览档位用（匹配显示区） */
  private previewShortSidePx: number = 1080;
  /** 当前拍照的毫秒计时（capture() 置位；各阶段埋点读它） */
  private timing: CaptureTiming | undefined = undefined;
  private timingSeq: number = 0;

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
   * `previewShortSidePx` = 取景显示区短边（px，预览流档位按它匹配显示区，
   * 官方 faqs-camera-7/12：分辨率过大合成负担重，预览拖不动）。
   * `context` = 页面宿主上下文。失败返回 false（视图渲染「相机不可用」）。
   */
  async open(context: common.UIAbilityContext, surfaceId: string,
    previewShortSidePx: number): Promise<boolean> {
    this.context = context;
    this.surfaceId = surfaceId;
    this.previewShortSidePx = previewShortSidePx > 0 ? previewShortSidePx : 1080;
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
    this.timing = new CaptureTiming(++this.timingSeq);
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
      hilog.warn(DOMAIN, TAG, 'hasFlash failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 变焦范围 [min, max]：启动后查一次并缓存（前置 / 后摄范围不同，翻转后重建）。
   * 热路径（拖动 / 捏合手势更新）只读缓存；官方模式：范围查询一次，不逐帧查。
   */
  zoomRange(): Array<number> {
    return [this.zoomRangeCache[0], this.zoomRangeCache[1]];
  }

  /**
   * 取景帧率拉升（官方 `PreviewOutput.setFrameRate`，API 12+，PhotoSession 下有效）。
   * 策略：查 `getSupportedFrameRates`，有「包含 30」的区间就锁 (30, 30)；
   * 没有则下发 maxFps 最大的整段区间；全失败保持默认（15fps 仍可用，不挡功能）。
   */
  private applyPreviewFrameRate(previewOutput: camera.PreviewOutput,
    context: common.UIAbilityContext): void {
    try {
      const rates = previewOutput.getSupportedFrameRates();
      let fallback: camera.FrameRateRange | undefined = undefined;
      let containsTarget: camera.FrameRateRange | undefined = undefined;
      for (const range of rates) {
        if (range.min <= PREVIEW_TARGET_FPS && range.max >= PREVIEW_TARGET_FPS) {
          containsTarget = range;
          break;
        }
        if (fallback === undefined || range.max > fallback.max) {
          fallback = range;
        }
      }
      if (containsTarget !== undefined) {
        previewOutput.setFrameRate(PREVIEW_TARGET_FPS, PREVIEW_TARGET_FPS);
      } else if (fallback !== undefined) {
        previewOutput.setFrameRate(fallback.min, fallback.max);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'applyPreviewFrameRate failed, keep default: %{public}s',
        JSON.stringify(err));
    }
  }

  /** 会话启动成功后刷新变焦范围缓存（整机多摄范围；查不到退 [1, 5] 兜底） */
  private refreshZoomRangeCache(session: camera.PhotoSession): void {
    try {
      const range = session.getZoomRatioRange();
      if (range.length >= 2) {
        this.zoomRangeCache = [Math.min(range[0], range[1]), Math.max(range[0], range[1])];
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getZoomRatioRange failed, keep fallback: %{public}s',
        JSON.stringify(err));
    }
  }

  /**
   * 华为相机式平滑变焦：官方 `setSmoothZoom`（贝塞尔曲线缓动），点档位用它缓过去；
   * 机型 / 会话不支持时退普通 `setZoomRatio`（跳变，保功能）。
   */
  smoothZoomTo(ratio: number): void {
    const session = this.session;
    if (session === undefined) {
      return;
    }
    let target = ratio;
    try {
      // 直接读缓存范围（不走 zoomRange() 的逐次数组分配，热路径零开销）
      target = clampZoomRatio(ratio, this.zoomRangeCache);
      session.setSmoothZoom(target);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setSmoothZoom failed, fallback setZoom: %{public}s',
        JSON.stringify(err));
      this.setZoom(target);
    }
  }

  /** 设置变焦倍率（内部按设备范围夹取，越界不抛） */
  setZoom(ratio: number): void {
    const session = this.session;
    if (session === undefined) {
      return;
    }
    try {
      // 夹取走缓存范围（零分配）：拖动热路径不逐次查会话（官方模式，避免高频 JNI 卡 UI）
      session.setZoomRatio(clampZoomRatio(ratio, this.zoomRangeCache));
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
    if (context === undefined || this.surfaceId.length === 0) {
      hilog.error(DOMAIN, TAG, 'setupSession missing context/surface');
      return false;
    }
    try {
      const manager = camera.getCameraManager(context);
      this.manager = manager;
      // 目标位姿的整组镜头（主摄 + 广角 + 长焦……）：全部挂进会话后
      // getZoomRatioRange 才是整机变焦范围，setZoomRatio 自动在镜头间切换
      const devices = manager.getSupportedCameras();
      let active: camera.CameraDevice | undefined = undefined;
      if (device !== undefined) {
        for (const candidate of devices) {
          if (candidate.cameraId === device.cameraId) {
            active = candidate;
            break;
          }
        }
      }
      if (active === undefined) {
        const positions: Array<camera.CameraPosition> = [];
        for (const candidate of devices) {
          positions.push(candidate.cameraPosition);
        }
        const index = defaultCameraIndex(positions);
        if (index < 0) {
          hilog.error(DOMAIN, TAG, 'no camera device');
          return false;
        }
        active = devices[index];
        this.device = active;
      }
      const positions: Array<camera.CameraPosition> = [];
      for (const candidate of devices) {
        positions.push(candidate.cameraPosition);
      }
      const groupIndexes = indexesOfPosition(positions, active.cameraPosition);
      const group: Array<camera.CameraDevice> = [];
      for (const index of groupIndexes) {
        group.push(devices[index]);
      }
      const capability = manager.getSupportedOutputCapability(active);
      if (capability.previewProfiles.length === 0 || capability.photoProfiles.length === 0) {
        hilog.error(DOMAIN, TAG, 'no preview/photo profile');
        return false;
      }
      const previewProfileMatched = bestPreviewProfile(
        capability.previewProfiles, this.previewShortSidePx);
      if (previewProfileMatched === undefined) {
        hilog.error(DOMAIN, TAG, 'no preview profile');
        return false;
      }
      const previewProfile = previewProfileMatched;
      const photoProfileMatched = bestPhotoProfile(capability.photoProfiles);
      if (photoProfileMatched === undefined) {
        hilog.error(DOMAIN, TAG, 'no photo profile');
        return false;
      }
      const photoProfile = photoProfileMatched;
      let previewOutput = manager.createPreviewOutput(previewProfile, this.surfaceId);
      let photoOutput = manager.createPhotoOutput(photoProfile);
      // 同组镜头全开：单颗起不来跳过（长焦挂不上不影响主摄），主摄起不来才算失败
      const inputs: Array<camera.CameraInput> = [];
      let primaryInput: camera.CameraInput | undefined = undefined;
      for (const candidate of group) {
        try {
          const input = manager.createCameraInput(candidate);
          await input.open();
          inputs.push(input);
          if (candidate.cameraId === active.cameraId) {
            primaryInput = input;
          }
        } catch (err) {
          hilog.error(DOMAIN, TAG, 'open camera %{public}s failed: %{public}s',
            candidate.cameraId, JSON.stringify(err));
        }
      }
      if (primaryInput === undefined) {
        hilog.error(DOMAIN, TAG, 'primary camera open failed');
        return false;
      }
      let session = manager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
      let committed = false;
      try {
        session.beginConfig();
        for (const input of inputs) {
          session.addInput(input);
        }
        session.addOutput(previewOutput);
        session.addOutput(photoOutput);
        await session.commitConfig();
        committed = true;
      } catch (err) {
        // 多输入提交失败（个别机型 / 场景限制）：退单主摄重试，保住基础可用
        hilog.error(DOMAIN, TAG, 'multi-input commit failed, fallback single: %{public}s',
          JSON.stringify(err));
      }
      if (!committed) {
        previewOutput = manager.createPreviewOutput(previewProfile, this.surfaceId);
        photoOutput = manager.createPhotoOutput(photoProfile);
        session = manager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
        session.beginConfig();
        session.addInput(primaryInput);
        session.addOutput(previewOutput);
        session.addOutput(photoOutput);
        await session.commitConfig();
      }
      await session.start();
      // 取景帧率：HAL 默认只给 15fps（实测），显式拉到支持的 30fps 档
      this.applyPreviewFrameRate(previewOutput, context);
      this.refreshZoomRangeCache(session);
      // 动态照片：会话提交并启动之后查询使能（官方顺序，先查后开）
      let moving = false;
      let movingSupported = false;
      try {
        movingSupported = photoOutput.isMovingPhotoSupported();
        if (movingSupported) {
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
            active.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT);
        }
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'enableMirror failed: %{public}s', JSON.stringify(err));
      }
      this.cameraInputs = inputs;
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
    const cameraInputs = this.cameraInputs;
    this.session = undefined;
    this.previewOutput = undefined;
    this.photoOutput = undefined;
    this.cameraInputs = [];
    this.movingPhotoEnabled = false;
    this.zoomRangeCache = [1, MAX_ZOOM_RATIO];
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
    for (const input of cameraInputs) {
      input.close().catch((): void => {
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
        const timing = this.timing;
        if (timing !== undefined) {
          CameraPerfLog.mark(this.context, `cap#${timing.id} asset=+${timing.elapsedMs()}ms`);
        }
        this.saveAndExtract(asset);
      });
  }

  /**
   * 先落库再提取（串行）：`saveCameraPhoto` 把相机资产提交进媒体库之后，
   * `requestContent` 才有底层资源可读——并发提取实测 14000011 inner fail
   * （photoAssetAvailable 回调里资产还只在相机管线里，未进媒体库）。
   */
  private async saveAndExtract(asset: photoAccessHelper.PhotoAsset): Promise<void> {
    const context = this.context;
    if (context === undefined) {
      this.onCaptureFailed();
      return;
    }
    await this.saveToGallery(asset);
    const timing = this.timing;
    if (timing !== undefined) {
      CameraPerfLog.mark(context, `cap#${timing.id} gallery=+${timing.elapsedMs()}ms`);
    }
    await this.extractShot(asset);
  }

  /** 拍下就存：官方相机链路 `saveCameraPhoto`，二阶段图就绪后媒体库自动替换（免权限） */
  private async saveToGallery(asset: photoAccessHelper.PhotoAsset): Promise<boolean> {
    const context = this.context;
    if (context === undefined) {
      return false;
    }
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const request = new photoAccessHelper.MediaAssetChangeRequest(asset);
      request.saveCameraPhoto();
      await helper.applyChanges(request);
      return true;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'saveCameraPhoto failed: %{public}d %{public}s', e.code, e.message);
      return false;
    }
  }

  /**
   * 沙盒提取：**静图先行**——只探 IMAGE 轨，一到手立刻交付 UI（相纸出纸不等视频）；
   * 视频转后台继续提取（`CameraShot.videoReady`），确认落盘时自然接上，
   * 拿不到 → 落盘退化普通照片。静图全败退 `requestImageData`（R-PHOTO-04 静态兜底）。
   */
  private async extractShot(asset: photoAccessHelper.PhotoAsset): Promise<void> {
    const context = this.context;
    if (context === undefined) {
      this.onCaptureFailed();
      return;
    }
    const timing = this.timing;
    let still: ArrayBuffer | undefined = undefined;
    let videoReady: Promise<ArrayBuffer | undefined> | undefined = undefined;
    if (this.movingPhotoEnabled) {
      still = await CameraSession.extractMovingStill(context, asset);
      if (still !== undefined) {
        // 视频后台补齐：探针循环自跑，成功 / 失败都不阻塞出纸
        videoReady = CameraSession.extractMovingVideo(context, asset).then(
          (video: ArrayBuffer | undefined): ArrayBuffer | undefined => {
            if (timing !== undefined) {
              CameraPerfLog.mark(context, `cap#${timing.id} video=+${timing.elapsedMs()}ms`);
            }
            return video;
          });
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
    if (timing !== undefined) {
      CameraPerfLog.mark(context, `cap#${timing.id} still=+${timing.elapsedMs()}ms`);
    }
    this.onShot(new CameraShot(still, videoReady));
  }

  /** 相纸出片上屏时刻（视图 handleShot 解码完成后调；毫秒计时用） */
  markPaperShown(): void {
    const context = this.context;
    const timing = this.timing;
    if (context !== undefined && timing !== undefined) {
      CameraPerfLog.mark(context, `cap#${timing.id} paper=+${timing.elapsedMs()}ms`);
    }
  }

  /** 真片落到相纸时刻（快照先行后换真片；毫秒计时用） */
  markPhotoOnPaper(): void {
    const context = this.context;
    const timing = this.timing;
    if (context !== undefined && timing !== undefined) {
      CameraPerfLog.mark(context, `cap#${timing.id} photo=+${timing.elapsedMs()}ms`);
    }
  }

  /**
   * 静图原样字节提取（BALANCE 密集探针 + HIGH_QUALITY 背水一战）。
   * 资产两阶段写入竞态下 BALANCE 失败快（14000011 / undefined 秒回），
   * 适合密集轮询——IMAGE 轨（第一阶段）典型几十毫秒~1s 就绪。
   */
  private static async extractMovingStill(context: common.UIAbilityContext,
    asset: photoAccessHelper.PhotoAsset): Promise<ArrayBuffer | undefined> {
    const balanceWaits: number[] = [300, 600, 1000, 1500, 2200, 3000, 4000, 5000];
    for (let attempt = 0; attempt <= balanceWaits.length; attempt++) {
      try {
        const movingPhoto = await CameraSession.requestMovingPhotoObject(
          context, asset, photoAccessHelper.DeliveryMode.BALANCE_MODE);
        if (movingPhoto !== undefined) {
          return await movingPhoto.requestContent(
            photoAccessHelper.ResourceType.IMAGE_RESOURCE);
        }
      } catch (err) {
        // 资产未就绪（14000011）/ 秒回 undefined：按节奏重试
      }
      if (attempt < balanceWaits.length) {
        await new Promise<void>((resolve: () => void): void => {
          setTimeout(resolve, balanceWaits[attempt]);
        });
      }
    }
    // 背水一战：HIGH_QUALITY 内部等两阶段写入（自带 ~4.5s 超时）
    try {
      const movingPhoto = await CameraSession.requestMovingPhotoObject(
        context, asset, photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE);
      if (movingPhoto !== undefined) {
        return await movingPhoto.requestContent(
          photoAccessHelper.ResourceType.IMAGE_RESOURCE);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'extractMovingStill hq fallback failed: %{public}s',
        JSON.stringify(err));
    }
    return undefined;
  }

  /**
   * 视频原样字节提取（IMAGE 之后的第二阶段，就绪更晚）：
   * 同款 BALANCE 探针 + HIGH_QUALITY 背水一战；全失败 resolve undefined
   * → 落盘链退化普通照片（R-PHOTO-04）。后台跑，不阻塞出纸。
   */
  private static async extractMovingVideo(context: common.UIAbilityContext,
    asset: photoAccessHelper.PhotoAsset): Promise<ArrayBuffer | undefined> {
    const balanceWaits: number[] = [300, 600, 1000, 1500, 2200, 3000, 4000, 5000];
    for (let attempt = 0; attempt <= balanceWaits.length; attempt++) {
      try {
        const movingPhoto = await CameraSession.requestMovingPhotoObject(
          context, asset, photoAccessHelper.DeliveryMode.BALANCE_MODE);
        if (movingPhoto !== undefined) {
          return await movingPhoto.requestContent(
            photoAccessHelper.ResourceType.VIDEO_RESOURCE);
        }
      } catch (err) {
        // 视频轨未就绪：按节奏重试
      }
      if (attempt < balanceWaits.length) {
        await new Promise<void>((resolve: () => void): void => {
          setTimeout(resolve, balanceWaits[attempt]);
        });
      }
    }
    // 背水一战：HIGH_QUALITY 内部等两阶段写入（自带 ~4.5s 超时）
    try {
      const movingPhoto = await CameraSession.requestMovingPhotoObject(
        context, asset, photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE);
      if (movingPhoto !== undefined) {
        return await movingPhoto.requestContent(
          photoAccessHelper.ResourceType.VIDEO_RESOURCE);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'extractMovingVideo hq fallback failed: %{public}s',
        JSON.stringify(err));
    }
    return undefined;
  }

  private static requestMovingPhotoObject(context: common.UIAbilityContext,
    asset: photoAccessHelper.PhotoAsset,
    deliveryMode: photoAccessHelper.DeliveryMode):
  Promise<photoAccessHelper.MovingPhoto | undefined> {
    return new Promise<photoAccessHelper.MovingPhoto | undefined>(
      (resolve: (movingPhoto: photoAccessHelper.MovingPhoto | undefined) => void,
        reject: (reason: BusinessError) => void): void => {
        const handler = mediaHandlerOf<photoAccessHelper.MovingPhoto>(resolve);
        const options: photoAccessHelper.RequestOptions = {
          deliveryMode: deliveryMode
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
        const handler = mediaHandlerOf<ArrayBuffer>((data: ArrayBuffer): void => {
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
