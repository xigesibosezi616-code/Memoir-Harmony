import { displaySync } from '@kit.ArkGraphics2D';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { ContentBlock } from '../../../models/ContentBlock';
import { ReaderGeometry, ReaderPage } from '../../../models/ReaderPages';
import { SpringSimulation } from '../../../models/SpringSimulation';
import { ReaderTextAdapter } from '../ReaderTextAdapter';
import { ReaderPageView } from '../ReaderPageView';
import { NativeCurl } from './NativeCurl';

const DOMAIN = 0x0000;
const TAG = 'NativeBookCurl';
const DIRECTION_THRESHOLD_VP = 6;
const COMMIT_PROGRESS = 0.42;
const FLICK_VELOCITY_VP = 600;
const GUARD_TIMEOUT_MS = 1600;

function nativePaperArgb(theme: AppTheme): number {
  const fallback = theme.colorMode === 'dark' ? 0xFF1C1410 : 0xFFFAF7F2;
  const color = theme.background;
  if (typeof color === 'number') {
    return color;
  }
  if (typeof color === 'string') {
    const hex = color.startsWith('#') ? color.substring(1) : color;
    if (/^[0-9a-fA-F]{6}$/.test(hex) || /^[0-9a-fA-F]{8}$/.test(hex)) {
      const value = parseInt(hex, 16);
      return hex.length === 6 ? 0xFF000000 + value : value;
    }
  }
  return fallback;
}

function progressSettled(value: number, velocity: number): boolean {
  return Math.abs(value) < 0.002 && Math.abs(velocity) < 0.08;
}

class NativeSurfaceController extends XComponentController {
  onCreated: (surfaceId: string) => void = (_surfaceId: string) => {};
  onChanged: (width: number, height: number) => void = (_width: number, _height: number) => {};
  onDestroyed: () => void = () => {};

  onSurfaceCreated(surfaceId: string): void {
    this.onCreated(surfaceId);
  }

  onSurfaceChanged(_surfaceId: string, rect: SurfaceRect): void {
    this.onChanged(rect.surfaceWidth, rect.surfaceHeight);
  }

  onSurfaceDestroyed(_surfaceId: string): void {
    this.onDestroyed();
  }
}

export class NativeBookController {
  forward: () => void = () => {};
  backward: () => void = () => {};
  reload: () => void = () => {};
  cancel: () => void = () => {};
  isAnimating: () => boolean = () => false;
}

@Component
export struct NativeBookCurlView {
  @Prop @Watch('onContentChanged') pages: ReaderPage[] = [];
  @Prop @Watch('onContentChanged') currentIndex: number = 0;
  @Prop geometry: ReaderGeometry = new ReaderGeometry(390, 844, 47, 34);
  @Prop adapter: ReaderTextAdapter | undefined = undefined;
  @Prop looseAudioBlocks: ContentBlock[] = [];
  @Prop theme: AppTheme = new BambooTheme();
  @Prop controller: NativeBookController = new NativeBookController();
  onPageCommit: (nextIndex: number) => void = (_nextIndex: number) => {};

  private density: number = 3;
  private surfaceReady: boolean = false;
  @State private sourceVisible: boolean = true;
  @State private nativeVisible: boolean = false;
  private pendingCaptures: number = 0;
  private reloadGeneration: number = 0;
  private surfaceController: NativeSurfaceController = new NativeSurfaceController();
  private flipDir: number = 0;
  private corner: number = 0;
  private boundary: boolean = false;
  private progress: number = 0;
  private startXpx: number = 0;
  private startYpx: number = 0;
  private samplePrevXpx: number = 0;
  private samplePrevTimeMs: number = 0;
  private sampleLastXpx: number = 0;
  private sampleLastTimeMs: number = 0;
  private releaseVelocity: number = 0;
  private animating: boolean = false;
  private flipCommit: boolean = false;
  private flipDriver: displaySync.DisplaySync | undefined = undefined;
  private flipSpring: SpringSimulation | undefined = undefined;
  private flipVelocity: number = 0;
  private flipTarget: number = 0;
  private flipLastFrameNs: number = -1;
  private flipGuardTimer: number = -1;

  aboutToAppear(): void {
    this.density = ReaderTextAdapter.screenDensity();
    this.controller.forward = (): void => this.flipProgrammatically(1);
    this.controller.backward = (): void => this.flipProgrammatically(-1);
    this.controller.reload = (): void => this.reloadTextures();
    this.controller.cancel = (): void => this.finishAnimation();
    this.controller.isAnimating = (): boolean => this.animating;
    this.surfaceController.onCreated = (surfaceId: string): void => {
      this.surfaceReady = NativeCurl.createSurface(BigInt(surfaceId));
      if (this.surfaceReady) {
        this.reloadTextures();
      } else {
        hilog.error(DOMAIN, TAG, 'create native surface failed');
      }
    };
    this.surfaceController.onChanged = (width: number, height: number): void => {
      NativeCurl.setSize(width, height);
      this.reloadTextures();
    };
    this.surfaceController.onDestroyed = (): void => {
      this.surfaceReady = false;
      NativeCurl.destroySurface();
    };
    setTimeout((): void => this.reloadTextures(), 0);
  }

  aboutToDisappear(): void {
    this.stopFlipDriver();
    NativeCurl.destroySurface();
  }

  private onContentChanged(): void {
    setTimeout((): void => this.reloadTextures(), 0);
  }

  private nextIndex(): number {
    return this.currentIndex + 1;
  }

  private previousIndex(): number {
    return this.currentIndex - 1;
  }

  private reloadTextures(): void {
    if (!this.surfaceReady || this.pages.length === 0) {
      return;
    }
    this.sourceVisible = true;
    this.nativeVisible = false;
    this.reloadGeneration += 1;
    const generation = this.reloadGeneration;
    setTimeout((): void => {
      if (generation !== this.reloadGeneration) {
        return;
      }
      this.capturePage('nativeCurrentPage', 0, generation);
      const targetId = this.flipDir < 0 && this.currentIndex > 0 ? 'nativePreviousPage' : 'nativeNextPage';
      this.capturePage(targetId, 1, generation);
    }, 0);
  }

  private capturePage(id: string, slot: number, generation: number): void {
    this.pendingCaptures += 1;
    const task = async (): Promise<void> => {
      let pm: image.PixelMap | undefined = undefined;
      try {
        pm = this.getUIContext().getComponentSnapshot().getSync(id);
        const info = pm.getImageInfoSync();
        if (info.pixelFormat !== image.PixelMapFormat.RGBA_8888) {
          await pm.convertPixelFormat(image.PixelMapFormat.RGBA_8888);
        }
        const pixels = new ArrayBuffer(pm.getPixelBytesNumber());
        await pm.readAllPixelsToBuffer(pixels);
        if (generation === this.reloadGeneration && this.surfaceReady) {
          NativeCurl.setPage(slot, info.size.width, info.size.height, pixels);
          NativeCurl.setFrame(this.progress, this.flipDir === 0 ? 1 : this.flipDir,
            this.corner, nativePaperArgb(this.theme));
        }
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'capture %{public}s failed: %{public}s', id, JSON.stringify(err));
      } finally {
        if (pm !== undefined) {
          try {
            pm.release();
          } catch (_err) {
          }
        }
        this.pendingCaptures = Math.max(0, this.pendingCaptures - 1);
        if (this.pendingCaptures === 0 && generation === this.reloadGeneration) {
          this.sourceVisible = false;
          this.nativeVisible = true;
        }
      }
    };
    task().catch((err: Object): void => {
      hilog.error(DOMAIN, TAG, 'upload page failed: %{public}s', JSON.stringify(err));
    });
  }

  private flipProgrammatically(direction: number): void {
    if (this.animating) {
      return;
    }
    const hasTarget = direction > 0
      ? this.currentIndex + 1 < this.pages.length
      : this.currentIndex - 1 >= 0;
    if (!hasTarget) {
      return;
    }
    this.flipDir = direction;
    this.corner = 0;
    this.boundary = false;
    this.releaseVelocity = 0;
    this.startAnimation(true);
  }

  private startAnimation(commit: boolean): void {
    this.stopFlipDriver();
    this.animating = true;
    this.flipCommit = commit;
    this.flipTarget = commit ? 1 : 0;
    this.flipVelocity = this.releaseVelocity / Math.max(1, this.getUIContext().vp2px(this.geometry.pageWidth));
    this.flipLastFrameNs = -1;
    this.flipSpring = new SpringSimulation(commit ? 0.32 : 0.34, 1);
    const driver = displaySync.create();
    driver.setExpectedFrameRateRange({ min: 30, max: 120, expected: 120 });
    driver.on('frame', (info: displaySync.IntervalInfo): void => {
      const spring = this.flipSpring;
      if (spring === undefined) {
        return;
      }
      const dtSec = this.flipLastFrameNs < 0 ? 1 / 120
        : (info.timestamp - this.flipLastFrameNs) / 1e9;
      this.flipLastFrameNs = info.timestamp;
      const next = spring.step(this.progress, this.flipTarget, this.flipVelocity, dtSec);
      this.progress = next[0];
      this.flipVelocity = next[1];
      NativeCurl.setFrame(this.progress, this.flipDir, this.corner, nativePaperArgb(this.theme));
      if (progressSettled(this.progress - this.flipTarget, this.flipVelocity)) {
        this.finishAnimation();
      }
    });
    this.flipDriver = driver;
    driver.start();
    this.flipGuardTimer = setTimeout((): void => this.finishAnimation(), GUARD_TIMEOUT_MS);
  }

  private finishAnimation(): void {
    if (!this.animating) {
      return;
    }
    this.stopFlipDriver();
    this.animating = false;
    const committed = this.flipCommit && !this.boundary;
    const nextIndex = this.currentIndex + this.flipDir;
    this.progress = 0;
    this.flipDir = 0;
    this.corner = 0;
    this.releaseVelocity = 0;
    if (committed) {
      this.onPageCommit(nextIndex);
    } else {
      this.reloadTextures();
    }
  }

  private stopFlipDriver(): void {
    if (this.flipDriver !== undefined) {
      this.flipDriver.stop();
      this.flipDriver = undefined;
    }
    if (this.flipGuardTimer >= 0) {
      clearTimeout(this.flipGuardTimer);
      this.flipGuardTimer = -1;
    }
    this.flipSpring = undefined;
    this.flipLastFrameNs = -1;
  }

  private flickVelocity(): number {
    const dt = this.sampleLastTimeMs - this.samplePrevTimeMs;
    if (dt <= 0 || dt > 160) {
      return 0;
    }
    return (this.sampleLastXpx - this.samplePrevXpx) / dt * 1000;
  }

  build() {
    Stack() {
      ForEach([this.previousIndex()], (idx: number): void => {
        if (idx >= 0) {
          ReaderPageView({
            page: this.pages[idx],
            geometry: this.geometry,
            adapter: this.adapter,
            looseAudioBlocks: this.looseAudioBlocks
          })
            .id('nativePreviousPage')
            .zIndex(-1)
        }
      }, (idx: number): string => `nativePrevious_${idx}`)

      ForEach([this.nextIndex()], (idx: number): void => {
        if (idx < this.pages.length) {
          ReaderPageView({
            page: this.pages[idx],
            geometry: this.geometry,
            adapter: this.adapter,
            looseAudioBlocks: this.looseAudioBlocks
          })
            .id('nativeNextPage')
            .visibility(this.sourceVisible ? Visibility.Visible : Visibility.Hidden)
        }
      }, (idx: number): string => `nativeNext_${idx}`)

      ForEach([this.currentIndex], (idx: number): void => {
        // 首帧 pages 还没装好：不下界判断会先建出兜底页（1970 页眉），
        // key 不变时普通成员 page 不再刷新，装载后仍是兜底页（真机实证）。
        // 与 next/prev 槽同款 if 守卫：pages 就绪后才建，建的即是真数据
        if (idx >= 0 && idx < this.pages.length) {
          ReaderPageView({
            page: this.pages[idx],
            geometry: this.geometry,
            adapter: this.adapter,
            looseAudioBlocks: this.looseAudioBlocks
          })
            .id('nativeCurrentPage')
            .visibility(this.sourceVisible ? Visibility.Visible : Visibility.Hidden)
        }
      }, (idx: number): string => `nativeCurrent_${idx}`)

      XComponent({ type: XComponentType.SURFACE, controller: this.surfaceController })
        .opacity(this.nativeVisible ? 1 : 0)
        .width('100%')
        .height('100%')
        .gesture(
          PanGesture({ fingers: 1 })
            .onActionStart((event: GestureEvent): void => {
              if (this.animating) {
                return;
              }
              const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
              if (finger === undefined) {
                return;
              }
              this.flipDir = 0;
              this.progress = 0;
              this.startXpx = finger.localX * this.density;
              this.startYpx = finger.localY * this.density;
              this.samplePrevXpx = this.startXpx;
              this.samplePrevTimeMs = Date.now();
              this.sampleLastXpx = this.startXpx;
              this.sampleLastTimeMs = Date.now();
            })
            .onActionUpdate((event: GestureEvent): void => {
              if (this.animating) {
                return;
              }
              const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
              if (finger === undefined) {
                return;
              }
              const x = finger.localX * this.density;
              if (this.flipDir === 0) {
                if (Math.abs(x - this.startXpx) < DIRECTION_THRESHOLD_VP * this.density) {
                  return;
                }
                this.flipDir = x < this.startXpx ? 1 : -1;
                const heightPx = this.getUIContext().vp2px(this.geometry.pageHeight);
                this.corner = this.startYpx < heightPx / 3 ? -1
                  : this.startYpx > heightPx * 2 / 3 ? 1 : 0;
                this.boundary = this.flipDir > 0
                  ? this.currentIndex + 1 >= this.pages.length
                  : this.currentIndex - 1 < 0;
                this.reloadTextures();
              }
              const widthPx = this.getUIContext().vp2px(this.geometry.pageWidth);
              this.progress = Math.min(1, Math.abs(x - this.startXpx) / Math.max(1, widthPx));
              if (this.boundary) {
                this.progress = Math.min(0.16, this.progress);
              }
              const now = Date.now();
              if (now - this.sampleLastTimeMs >= 8) {
                this.samplePrevXpx = this.sampleLastXpx;
                this.samplePrevTimeMs = this.sampleLastTimeMs;
                this.sampleLastXpx = x;
                this.sampleLastTimeMs = now;
              }
              NativeCurl.setFrame(this.progress, this.flipDir, this.corner,
                nativePaperArgb(this.theme));
            })
            .onActionEnd((_event: GestureEvent): void => {
              if (this.animating || this.flipDir === 0) {
                return;
              }
              this.releaseVelocity = this.flickVelocity();
              const flick = this.flipDir > 0
                ? this.releaseVelocity < -FLICK_VELOCITY_VP * this.density
                : this.releaseVelocity > FLICK_VELOCITY_VP * this.density;
              this.startAnimation(!this.boundary && (this.progress >= COMMIT_PROGRESS || flick));
            })
            .onActionCancel((): void => {
              if (!this.animating && this.flipDir !== 0) {
                this.startAnimation(false);
              }
            })
        )
    }
    .width(this.geometry.pageWidth)
    .height(this.geometry.pageHeight)
  }
}
