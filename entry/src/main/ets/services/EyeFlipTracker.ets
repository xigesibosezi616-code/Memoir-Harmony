/**
 * 眼动翻页追踪器（10_BUILD_MANUAL.md 3.5 眼动翻页）。前摄低分辨率预览 +
 * CoreVision faceDetector 轮询检脸，把最大脸的 pitch（抬头低头）喂给回调；
 * 触发判定在 EyeFlipMachine（纯逻辑），本类只管「帧从哪来」。
 *
 * - 会话：前摄（CameraSession 同款 CameraKit 装配，只要预览流不要拍照流）
 * - 帧源：`image.createPixelMapFromSurface`（PaperCameraView 抓取景帧同款，
 *   相纸盖住取景器时仍可抓帧 —— 预览 surface 被页面盖住不影响）
 * - 节奏：`EYE_POLL_INTERVAL_MS` 轮询一帧检一次（~3fps，600ms 抬头判定够用，
 *   省电）；上一帧没检完跳过本帧（detect 串行，不堆积）
 * - 失败即静默：没脸 / 超时 / 抓帧失败 → 回调 undefined（机器按「无脸」处理），
 *   不重试不报错
 * - 生命周期：`start(surfaceId)` 装配 + 起轮询；`stop()` 停轮询 + 释放会话；
 *   页面 aboutToDisappear 必须调 stop（相机是独占资源）
 */
import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { faceDetector } from '@kit.CoreVisionKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { bestPreviewProfile } from './CameraSession';
import { pitchOfLargestFace } from '../models/EyeFlipMachine';

const DOMAIN = 0x0000;
const TAG = 'EyeFlipTracker';

/** 轮询间隔（ms）：faceDetector ~3fps，600ms 抬头判定够用 */
export const EYE_POLL_INTERVAL_MS: number = 350;
/** 预览目标短边（px）：脸占满画面的小档即可，省电（bestPreviewProfile 就近匹配） */
const EYE_PREVIEW_SHORT_SIDE_PX: number = 240;

/** 每帧检测结果回调：pitch（度）；undefined = 没脸 / 检测失败 */
export type EyePitchCallback = (pitchDeg: number | undefined) => void;

export class EyeFlipTracker {
  private context: common.UIAbilityContext;
  private onPitch: EyePitchCallback;
  private manager: camera.CameraManager | undefined = undefined;
  private session: camera.PhotoSession | undefined = undefined;
  private previewOutput: camera.PreviewOutput | undefined = undefined;
  private cameraInput: camera.CameraInput | undefined = undefined;
  private pollTimerId: number = -1;
  /** 上一帧还在检：跳过本帧（detect 串行不堆积） */
  private detectBusy: boolean = false;
  /** 轮询失败计数（首条 + 每 10 条记一条日志） */
  private errorCount: number = 0;
  private surfaceId: string = '';
  private running: boolean = false;

  constructor(context: common.UIAbilityContext, onPitch: EyePitchCallback) {
    this.context = context;
    this.onPitch = onPitch;
  }

  /** 装配前摄会话 + 起轮询。surfaceId 来自页面 XComponent；失败返回 false（页面负责回滚开关） */
  async start(surfaceId: string): Promise<boolean> {
    if (this.running) {
      return true;
    }
    this.surfaceId = surfaceId;
    try {
      await faceDetector.init();
    } catch (err) {
      // init 失败不拦启动：detect 报错按「无脸」走
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'faceDetector init: %{public}d %{public}s', e.code, e.message);
    }
    const ok = await this.setupSession();
    if (!ok) {
      await this.teardownSession();
      return false;
    }
    this.running = true;
    this.pollTimerId = setInterval((): void => {
      this.pollOnce();
    }, EYE_POLL_INTERVAL_MS);
    return true;
  }

  /** 停轮询 + 释放会话（相机独占资源，页面消失必须调） */
  async stop(): Promise<void> {
    this.running = false;
    if (this.pollTimerId >= 0) {
      clearInterval(this.pollTimerId);
      this.pollTimerId = -1;
    }
    await this.teardownSession();
    // 官方生命周期：init 过的 detector 要 release，避免下次 init 复用脏状态
    try {
      await faceDetector.release();
    } catch (err) {
      // 未 init / 已释放：静默
    }
  }

  // ---- 内部 ----

  private async setupSession(): Promise<boolean> {
    try {
      const manager = camera.getCameraManager(this.context);
      this.manager = manager;
      const devices = manager.getSupportedCameras();
      let front: camera.CameraDevice | undefined = undefined;
      for (const candidate of devices) {
        if (candidate.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT) {
          front = candidate;
          break;
        }
      }
      if (front === undefined) {
        hilog.error(DOMAIN, TAG, 'no front camera');
        return false;
      }
      const capability = manager.getSupportedOutputCapability(front);
      const profile = bestPreviewProfile(capability.previewProfiles, EYE_PREVIEW_SHORT_SIDE_PX);
      if (profile === undefined) {
        hilog.error(DOMAIN, TAG, 'no preview profile');
        return false;
      }
      const input = manager.createCameraInput(front);
      await input.open();
      this.cameraInput = input;
      this.previewOutput = manager.createPreviewOutput(profile, this.surfaceId);
      const session = manager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
      session.beginConfig();
      session.addInput(input);
      session.addOutput(this.previewOutput);
      await session.commitConfig();
      await session.start();
      this.session = session;
      return true;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'setupSession: %{public}d %{public}s', e.code, e.message);
      return false;
    }
  }

  /** 会话拆卸（CameraSession.teardownSession 同款顺序与吞错） */
  private async teardownSession(): Promise<void> {
    const session = this.session;
    const previewOutput = this.previewOutput;
    const cameraInput = this.cameraInput;
    this.session = undefined;
    this.previewOutput = undefined;
    this.cameraInput = undefined;
    this.manager = undefined;
    this.detectBusy = false;
    if (session !== undefined) {
      session.release().catch((): void => {
      });
    }
    if (previewOutput !== undefined) {
      previewOutput.release().catch((): void => {
      });
    }
    if (cameraInput !== undefined) {
      cameraInput.close().catch((): void => {
      });
    }
  }

  private async pollOnce(): Promise<void> {
    if (!this.running || this.detectBusy || this.surfaceId.length === 0) {
      return;
    }
    this.detectBusy = true;
    let frame: image.PixelMap | undefined = undefined;
    try {
      frame = await image.createPixelMapFromSurface(this.surfaceId);
      // VisionInfo 只吃 RGBA_8888（CoreVision 文档），surface 抓帧给的是预览
      // 缓冲原生格式（NV12 一类 YUV）—— 不转格式 detect 永远一张脸都检不出
      const info = frame.getImageInfoSync();
      if (info.pixelFormat !== image.PixelMapFormat.RGBA_8888) {
        await frame.convertPixelFormat(image.PixelMapFormat.RGBA_8888);
      }
      const vision: faceDetector.VisionInfo = { pixelMap: frame };
      const faces = await faceDetector.detect(vision);
      if (this.running) {
        this.onPitch(pitchOfLargestFace(faces));
      }
    } catch (err) {
      // 抓帧 / 转格式 / detect 失败：按「无脸」喂，不重试；区别于真没脸，记一条日志
      const e = err as BusinessError;
      this.errorCount++;
      if (this.errorCount === 1 || this.errorCount % 10 === 0) {
        hilog.warn(DOMAIN, TAG, 'poll error #%{public}d: %{public}d %{public}s',
          this.errorCount, e.code, e.message);
      }
      if (this.running) {
        this.onPitch(undefined);
      }
    } finally {
      if (frame !== undefined) {
        frame.release().catch((): void => {
        });
      }
      this.detectBusy = false;
    }
  }
}
