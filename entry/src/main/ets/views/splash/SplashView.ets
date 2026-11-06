/**
 * 开场页（U09 R-APP-10，取代 R-APP-08）。对应 iOS `Views/Splash/SplashView.swift`。
 *
 * ## 时间线（封面 + 一笔写「m.」）
 *
 * ```
 *  封面   ├──淡入 0.2s──┤
 *  写字      0.06s 后 ├─m 四笔 0.42s─┤抬笔┤点┤停 0.35s┤
 *  声音      刷   刷   刷  刷      砰
 *  淡出                                  ├──淡出 0.25s──┤
 *  主界面                                 ░░▒▒▓▓█
 * ```
 *
 * 字形和时间表都在 `HandwrittenMark.ets`（和桌面图标同一份数据）；声音
 * `rawfile/splash_write.wav`（按同一张时间表合成），从写第一笔那一刻开始放，
 * 跟媒体音量、不打断用户在放的音乐（SoundPool 混音，不申请焦点）。
 * 从显示到进主界面约 1.2 秒。
 *
 * 两条兜底，任何一条不成立都不能把用户卡在开场：
 * 1. **当前主题没有封面图** → 立刻进 App（正常情况下 EntryAbility 那层就拦掉了）
 * 2. **用户点一下** → 立即跳过（声音在淡出的 0.25s 里一起淡掉）
 */
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME, STORAGE_KEY_THEME_ID } from '../../theme/ThemeManager';
import { splashImageFor } from './SplashCoverPool';
import { drawHandwrittenMark, MarkScript } from './HandwrittenMark';

/** 封面淡入时长（R-APP-10：0.2s；封面底色和底下垫的主题背景同色，淡入的其实只有「from Sinara」） */
export const SPLASH_FADE_IN_MS = 200;
/** 封面出来多久后落第一笔（写字本身的节奏在 `MarkScript`） */
export const SPLASH_WRITE_DELAY_MS = 60;
/** 写完、停够之后整层淡出的时长（R-APP-08 是 0.3s，R-APP-10 缩到 0.25s） */
export const SPLASH_FADE_OUT_MS = 250;
/** 帧间隔（约 60fps；写字四笔共 0.42s，肉眼连续） */
const FRAME_MS = 16;
/** 字的位置：宽度 = 封面显示宽度的 44%、中心在封面显示高度的 45%（就是原来笔记本的位置） */
const MARK_WIDTH_RATIO = 0.44;
const MARK_CENTER_Y_RATIO = 0.4496;
/** 笔声的音量（iOS `SplashSound` 同值：0.8） */
const SPLASH_SOUND_VOLUME = 0.8;

@Component
export struct SplashView {
  onFinish: () => void = () => {};

  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_THEME_ID) themeId: string = 'bamboo';

  @State coverImage: Resource | undefined = undefined;
  /** 封面自身的透明度 —— 淡入只作用在图上，底下的主题背景色始终不透明，免得启动瞬间先闪一下白/黑再变成主题色 */
  @State coverOpacity: number = 0;
  /**
   * 整层透明度。**淡出由这一层自己做，做完才通知父视图把自己移除。**
   * iOS 同款：交给父视图的移除过渡实测没有过渡帧（上一帧纯开场、下一帧纯主界面的硬切），
   * 把淡出握在自己手里、等完全透明了再移除，观感就不依赖任何外部行为。
   */
  @State layerOpacity: number = 1;
  /** 写字画布的位置和大小（封面 Contain 之后的框算出来，跟着封面走、不跟屏幕） */
  @State markWidth: number = 0;
  @State markHeight: number = 0;
  @State markLeft: number = 0;
  @State markTop: number = 0;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  private didFinish: boolean = false;
  private writingStartMs: number = -1;
  private writeDelayTimerId: number = -1;
  private frameTimerId: number = -1;
  private fadeOutTimerId: number = -1;

  // ---- 笔声（SoundPool 短音频，低时延） ----
  private soundPool: media.SoundPool | undefined = undefined;
  private soundId: number = -1;
  private streamId: number = -1;
  private fadeVolumeTimerId: number = -1;

  aboutToAppear(): void {
    this.coverImage = splashImageFor(this.themeId);
    if (this.coverImage === undefined) {
      // 当前主题没配封面：直接进 App，别让用户对着一块纯色背景发呆
      this.finish();
      return;
    }
    this.prepareSound();
    this.getUIContext().animateTo({ duration: SPLASH_FADE_IN_MS, curve: Curve.EaseOut }, () => {
      this.coverOpacity = 1;
    });
    this.writeDelayTimerId = setTimeout(() => {
      this.startWriting();
    }, SPLASH_WRITE_DELAY_MS);
  }

  aboutToDisappear(): void {
    if (this.writeDelayTimerId !== -1) {
      clearTimeout(this.writeDelayTimerId);
    }
    if (this.frameTimerId !== -1) {
      clearTimeout(this.frameTimerId);
    }
    if (this.fadeOutTimerId !== -1) {
      clearTimeout(this.fadeOutTimerId);
    }
    if (this.fadeVolumeTimerId !== -1) {
      clearTimeout(this.fadeVolumeTimerId);
    }
    this.releaseSound();
  }

  build() {
    Stack() {
      // 底色：封面淡入前垫住画面，避免闪一下白屏；
      // 图片 `.fit` 的留白处露的也是这一层 —— 图片底色与它一致才看不出接缝
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme.background)

      if (this.coverImage !== undefined) {
        Image(this.coverImage)
          // 🔴 用 fit 而不是 fill：封面底部有 Sinara 标识，
          // fill 在比例不同的机型上会把它裁掉；fit 的留白由底色补齐
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
          .opacity(this.coverOpacity)

        // 写字的画布：字跟着封面走（不跟屏幕），比例不同的机型上也落在原来笔记本的位置
        if (this.markWidth > 0 && this.markHeight > 0) {
          Canvas(this.canvasCtx)
            .width(this.markWidth)
            .height(this.markHeight)
            .position({ x: this.markLeft, y: this.markTop })
            .onReady(() => {
              this.drawFrame();
            })
        }
      }
    }
    .width('100%')
    .height('100%')
    .opacity(this.layerOpacity)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.layoutMark(newValue);
    })
    .onClick(() => {
      // 点任意处跳过
      this.finish();
    })
  }

  // ---- 封面 Contain 之后实际占的框 → 字的位置 ----

  private layoutMark(area: Area): void {
    const areaWidth = Number(area.width) || 0;
    const areaHeight = Number(area.height) || 0;
    if (areaWidth <= 0 || areaHeight <= 0 || this.coverImage === undefined) {
      return;
    }
    // 封面 1290×2796 Contain 进屏幕：先算封面实际显示框，再按 R-APP-10 的比例放字
    const coverAspect = 1290 / 2796;
    let coverWidth = areaWidth;
    let coverHeight = areaWidth / coverAspect;
    if (coverHeight > areaHeight) {
      coverHeight = areaHeight;
      coverWidth = areaHeight * coverAspect;
    }
    const coverLeft = (areaWidth - coverWidth) / 2;
    const coverTop = (areaHeight - coverHeight) / 2;
    // 字（含句点）的宽高比照 HandwrittenMark 的 bounds
    const markAspect = 321.9 / (255.7 - 128.9);
    this.markWidth = coverWidth * MARK_WIDTH_RATIO;
    this.markHeight = this.markWidth / markAspect;
    this.markLeft = coverLeft + coverWidth / 2 - this.markWidth / 2;
    this.markTop = coverTop + coverHeight * MARK_CENTER_Y_RATIO - this.markHeight / 2;
  }

  // ---- 写字 ----

  private startWriting(): void {
    if (this.didFinish) {
      return;
    }
    this.writingStartMs = Date.now();
    this.playSound();
    this.scheduleFrame();
  }

  private scheduleFrame(): void {
    this.frameTimerId = setTimeout(() => {
      this.drawFrame();
    }, FRAME_MS);
  }

  private drawFrame(): void {
    if (this.didFinish || this.writingStartMs < 0 || this.markWidth <= 0) {
      return;
    }
    const time = (Date.now() - this.writingStartMs) / 1000;
    const ctx = this.canvasCtx;
    ctx.clearRect(0, 0, this.markWidth, this.markHeight);
    drawHandwrittenMark(ctx, this.markWidth, this.markHeight, time, this.theme.markInk);
    if (time < MarkScript.total()) {
      this.scheduleFrame();
    } else {
      this.finish();
    }
  }

  // ---- 退场 ----

  /** 到点淡出 / 点击跳过都走这里，didFinish 保证只生效一次；声音跟着一起淡掉 */
  private finish(): void {
    if (this.didFinish) {
      return;
    }
    this.didFinish = true;
    this.getUIContext().animateTo({ duration: SPLASH_FADE_OUT_MS, curve: Curve.EaseInOut }, () => {
      this.layerOpacity = 0;
    });
    this.fadeOutSound();
    this.fadeOutTimerId = setTimeout(() => {
      this.onFinish();
    }, SPLASH_FADE_OUT_MS);
  }

  // ---- 笔声：prepare 先载好，写第一笔时直接响不慢半拍 ----

  private async prepareSound(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      const rendererInfo: audio.AudioRendererInfo = {
        // 音乐流：跟媒体音量、SoundPool 混音不申请焦点，不打断用户在放的音乐
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      };
      this.soundPool = await media.createSoundPool(1, rendererInfo);
      const fd = await context.resourceManager.getRawFd('sounds/splash_write.wav');
      this.soundId = await this.soundPool.load(fd.fd, fd.offset, fd.length);
    } catch (error) {
      const err = error as BusinessError;
      hilog.warn(0x0000, 'Splash', 'sound prepare failed, code: %{public}d', err.code);
    }
  }

  private playSound(): void {
    if (this.soundPool === undefined || this.soundId < 0) {
      return;
    }
    const params: media.PlayParameters = {
      loop: 0,
      priority: 0,
      leftVolume: SPLASH_SOUND_VOLUME,
      rightVolume: SPLASH_SOUND_VOLUME
    };
    this.soundPool.play(this.soundId, params)
      .then((streamId: number) => {
        this.streamId = streamId;
      })
      .catch((error: BusinessError) => {
        hilog.warn(0x0000, 'Splash', 'sound play failed, code: %{public}d', error.code);
      });
  }

  /** 跳过/退场时声音跟着淡掉（0.25s 里分五步降到底），别在主界面上还响着 */
  private fadeOutSound(): void {
    if (this.soundPool === undefined || this.streamId < 0) {
      return;
    }
    let step = 0;
    const totalSteps = 5;
    this.fadeVolumeTimerId = setInterval(() => {
      step += 1;
      const volume = SPLASH_SOUND_VOLUME * (1 - step / totalSteps);
      if (this.soundPool !== undefined && this.streamId >= 0) {
        this.soundPool.setVolume(this.streamId, Math.max(volume, 0), Math.max(volume, 0))
          .catch((_error: BusinessError) => {
          });
      }
      if (step >= totalSteps) {
        clearInterval(this.fadeVolumeTimerId);
        this.fadeVolumeTimerId = -1;
        this.stopSound();
      }
    }, SPLASH_FADE_OUT_MS / totalSteps);
  }

  private stopSound(): void {
    if (this.soundPool !== undefined && this.streamId >= 0) {
      this.soundPool.stop(this.streamId)
        .catch((_error: BusinessError) => {
        });
    }
  }

  /** 开场结束放掉播放器 */
  private releaseSound(): void {
    if (this.fadeVolumeTimerId !== -1) {
      clearInterval(this.fadeVolumeTimerId);
      this.fadeVolumeTimerId = -1;
    }
    if (this.soundPool !== undefined) {
      this.soundPool.release()
        .catch((_error: BusinessError) => {
        });
      this.soundPool = undefined;
    }
  }
}
