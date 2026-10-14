/**
 * 开场页（10_BUILD_MANUAL.md 1.5）。对应 iOS `Views/Splash/SplashView.swift`。
 * 当前用的是按主题的静态封面（`SplashCoverPool`）。
 *
 * ## 时间线（封面模式，R-APP-08）
 *
 * ```
 *  封面   ├──淡入 250ms──┤────停留────┤
 *  淡出                      ├──淡出 300ms──┤
 *  主界面                     ░░▒▒▓▓█
 * ```
 *
 * `SPLASH_COVER_MS`（700ms）是**从开始淡入到开始淡出**的总时长 ——
 * 也就是「0.7 秒的启动画面」。淡出的 300ms 叠在它后面，不算在 0.7 秒里。
 *
 * 两条兜底，任何一条不成立都不能把用户卡在开场：
 * 1. **当前主题没有封面图** → 立刻进 App（正常情况下 EntryAbility 那层就拦掉了）
 * 2. **用户点一下** → 立即跳过
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME, STORAGE_KEY_THEME_ID } from '../../theme/ThemeManager';
import { splashImageFor } from './SplashCoverPool';

/** 封面淡入时长（R-APP-08：0.25s） */
export const SPLASH_FADE_IN_MS = 250;
/** 「0.7 秒的启动画面」：从开始淡入到开始淡出的总时长（R-APP-08） */
export const SPLASH_COVER_MS = 700;
/** 整层淡出时长，叠在 0.7s 之后，不算在 0.7s 里（R-APP-08：0.3s） */
export const SPLASH_FADE_OUT_MS = 300;

@Component
export struct SplashView {
  onFinish: () => void = () => {};

  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  @State coverImage: Resource | undefined = undefined;
  /** 封面自身的透明度 —— 淡入只作用在图上，底下的主题背景色始终不透明，免得启动瞬间先闪一下白/黑再变成主题色 */
  @State coverOpacity: number = 0;
  /**
   * 整层透明度。**淡出由这一层自己做，做完才通知父视图把自己移除。**
   * iOS 同款：交给父视图的移除过渡实测没有过渡帧（上一帧纯开场、下一帧纯主界面的硬切），
   * 把淡出握在自己手里、等完全透明了再移除，观感就不依赖任何外部行为。
   */
  @State layerOpacity: number = 1;

  private didFinish: boolean = false;
  private coverTimerId: number = -1;
  private fadeOutTimerId: number = -1;

  aboutToAppear(): void {
    const themeId: string = AppStorage.get<string>(STORAGE_KEY_THEME_ID) ?? 'bamboo';
    this.coverImage = splashImageFor(themeId);
    if (this.coverImage === undefined) {
      // 当前主题没配封面：直接进 App，别让用户对着一块纯色背景发呆
      this.finish();
      return;
    }
    this.getUIContext().animateTo({ duration: SPLASH_FADE_IN_MS, curve: Curve.EaseOut }, () => {
      this.coverOpacity = 1;
    });
    this.coverTimerId = setTimeout(() => {
      this.finish();
    }, SPLASH_COVER_MS);
  }

  aboutToDisappear(): void {
    if (this.coverTimerId !== -1) {
      clearTimeout(this.coverTimerId);
    }
    if (this.fadeOutTimerId !== -1) {
      clearTimeout(this.fadeOutTimerId);
    }
  }

  /** 到点淡出 / 点击跳过都走这里，didFinish 保证只生效一次 */
  private finish(): void {
    if (this.didFinish) {
      return;
    }
    this.didFinish = true;
    this.getUIContext().animateTo({ duration: SPLASH_FADE_OUT_MS, curve: Curve.EaseInOut }, () => {
      this.layerOpacity = 0;
    });
    this.fadeOutTimerId = setTimeout(() => {
      this.onFinish();
    }, SPLASH_FADE_OUT_MS);
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
      }
    }
    .width('100%')
    .height('100%')
    .opacity(this.layerOpacity)
    .onClick(() => {
      // 点任意处跳过
      this.finish();
    })
  }
}
