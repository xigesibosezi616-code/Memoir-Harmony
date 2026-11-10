/**
 * 应用根视图（10_BUILD_MANUAL.md 1.5）。对应 iOS `MemoirApp.swift` 的 ZStack
 * （主界面常驻 + SplashView 盖顶）+ `ContentView.swift`（主界面 / 引导切换 +
 * 同意页 fullScreenCover）。
 *
 * 层叠顺序（自下而上）：
 * 1. 主界面（1.6 前是占位空状态）或引导页 —— 主界面**常驻在底层**，
 *    开场结束只是把上面那层淡掉，底下是现成的画面，不会有构建卡顿（iOS 注释同款）
 * 2. 隐私同意页 —— **开场完全收干净后隔一拍才登场**（LEGAL_DELAY_AFTER_SPLASH_MS，
 *    再淡入 LEGAL_FADE_IN_MS）：开场淡出的 0.25s 里同意页正在底下浮现，
 *    观感上像被弹窗截断（用户反馈），所以改成等动画彻底结束、空一拍、
 *    再淡入同意页。用户同意之前一切数据处理都免谈（R-APP-01）依旧成立
 *    ——开场只是本地动画+本地音效，不发请求不申请权限
 *    🔴 与 iOS 有意偏差（2026-11-08 用户指令「问题二」）：iOS 的 fullScreenCover
 *    是窗口级展示、首启会盖住开场，用户看不到开机动画；这里改为先播完开场
 *    再走同意流程
 * 3. 开场封面（EntryAbility 已算好本次启动放不放，本页不再判断）—— 最上层
 *
 * 三个状态都由 EntryAbility 启动时写进 AppStorage，本页只观察：
 * - needsLegalConsent：同意后本页写回 false（偏好 + 镜像）
 * - hasCompletedOnboarding：OnboardingView 走完写 true
 * - showSplash：SplashView onFinish 后写 false（摘掉一层已透明的东西）
 */
import {
  AppPrefs,
  PREF_KEY_ACCEPTED_LEGAL_VERSION,
  STORAGE_KEY_NEEDS_LEGAL_CONSENT,
  STORAGE_KEY_HAS_COMPLETED_ONBOARDING,
  STORAGE_KEY_SHOW_SPLASH
} from '../services/AppPrefs';
import { LEGAL_CURRENT_VERSION } from '../views/legal/LegalDocument';
import { LegalConsentView } from '../views/legal/LegalConsentView';
import { OnboardingView } from '../views/onboarding/OnboardingView';
import { SplashView } from '../views/splash/SplashView';
import { MainTabsView } from '../views/main/MainTabsView';
import { STORAGE_KEY_HOME_RELOAD_TICK } from '../data/HomeLogic';
import { STORAGE_KEY_DETAIL_RELOAD_TICK } from '../views/detail/EntryDetailView';
import { AppTheme } from '../theme/AppTheme';
import { BambooTheme } from '../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../theme/ThemeManager';
import { AppEnvironment, STORAGE_KEY_APP_ENVIRONMENT } from '../environment/AppEnvironment';
import { createDefaultErrorPresenter } from '../environment/ErrorPresenter';

/** 开场彻底结束后同意页再等这一拍才登场（问题二：弹窗不压着淡出的尾巴） */
const LEGAL_DELAY_AFTER_SPLASH_MS = 300;
/** 同意页淡入时长 */
const LEGAL_FADE_IN_MS = 250;

@Entry
@Component
struct Index {
  /**
   * 应用级依赖容器（10_BUILD_MANUAL.md 1.6）：EntryAbility 在 loadContent 前已把
   * 实例写进 AppStorage，这里取出 @Provide 下发，View 端 `@Consume` 取用；
   * 取不到（异常路径）时兜底一个只有 errors 的实例，保证提示链路始终可用。
   */
  @Provide env: AppEnvironment =
    AppStorage.get<AppEnvironment>(STORAGE_KEY_APP_ENVIRONMENT)
      ?? new AppEnvironment(createDefaultErrorPresenter());
  @StorageProp(STORAGE_KEY_THEME) @Watch('onThemeChanged') theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_HAS_COMPLETED_ONBOARDING) hasCompletedOnboarding: boolean = false;
  @StorageLink(STORAGE_KEY_NEEDS_LEGAL_CONSENT) needsLegalConsent: boolean = true;
  @StorageLink(STORAGE_KEY_SHOW_SPLASH) showSplash: boolean = false;
  /**
   * 同意页是否已到登场时刻：有开场时 = 开场摘除后再等 LEGAL_DELAY_AFTER_SPLASH_MS；
   * 没开场 = aboutToAppear 直接置 true（同意页立即出现，不空等）。
   * 只在 needsLegalConsent 为真时有意义。
   */
  @State private legalShown: boolean = false;
  private legalDelayTimerId: number = -1;

  aboutToAppear(): void {
    // @Watch 首值不保证触发：挂载后手动同步一次系统栏配色（沉浸式下内容色随主题）
    this.onThemeChanged();
    this.legalShown = !this.showSplash;
  }

  aboutToDisappear(): void {
    if (this.legalDelayTimerId !== -1) {
      clearTimeout(this.legalDelayTimerId);
      this.legalDelayTimerId = -1;
    }
  }

  /**
   * 页面（重新）可见时 bump 重查信号：路由返回（保存日记 / 编辑返回）、
   * 冷启动、后台回前台都会触发。主页 / 详情页此时可见，重查后立即渲染——
   * RDB 无观察机制，用这个补 iOS `@Query` 的自动响应（见 HomeLogic）。
   * 详情页已迁入 Tab 内 Navigation 栈（不再是独立路由页），原路由壳
   * onPageShow 的 detail tick 广播移到这里。
   */
  onPageShow(): void {
    AppStorage.setOrCreate(STORAGE_KEY_HOME_RELOAD_TICK,
      (AppStorage.get<number>(STORAGE_KEY_HOME_RELOAD_TICK) ?? 0) + 1);
    AppStorage.setOrCreate(STORAGE_KEY_DETAIL_RELOAD_TICK,
      (AppStorage.get<number>(STORAGE_KEY_DETAIL_RELOAD_TICK) ?? 0) + 1);
  }

  /** 主题变化 → 系统栏内容色随主题背景亮度重算（ImmersiveChrome） */
  onThemeChanged(): void {
    const chrome = this.env.chrome;
    if (chrome !== undefined) {
      chrome.syncSystemBarColors(this.theme);
    }
  }

  build() {
    Stack() {
      if (this.hasCompletedOnboarding) {
        // 1.6 主框架：四 tab + 全局 toast 顶部层
        MainTabsView()
      } else {
        OnboardingView()
      }

      if (this.needsLegalConsent && this.legalShown) {
        // 开场收干净后隔一拍才淡入登场（见文件头层叠说明，问题二）；
        // 淡入由 onFinish 里包着 legalShown 置位的 animateTo 驱动
        LegalConsentView({
          onAccept: () => {
            // 🔴 存版本号而不是布尔值（R-APP-02）：政策更新（改
            // LEGAL_CURRENT_VERSION）后老用户会重新看到这一页
            AppPrefs.putString(PREF_KEY_ACCEPTED_LEGAL_VERSION, LEGAL_CURRENT_VERSION);
            this.needsLegalConsent = false;
          }
        })
          .transition(TransitionEffect.OPACITY)
      }

      if (this.showSplash) {
        // 不需要再包过渡：淡出是 SplashView 自己做的，
        // 回调进来时它已完全透明，这一步只是摘掉一层看不见的东西（iOS 同款）
        SplashView({
          onFinish: () => {
            this.showSplash = false;
            // 有同意页要弹时：等一拍再淡入，别压着开场淡出的尾巴（问题二）
            if (this.needsLegalConsent) {
              this.legalDelayTimerId = setTimeout(() => {
                this.getUIContext().animateTo(
                  { duration: LEGAL_FADE_IN_MS, curve: Curve.EaseOut },
                  () => {
                    this.legalShown = true;
                  });
              }, LEGAL_DELAY_AFTER_SPLASH_MS);
            }
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    // 系统 OTA（2026-10-21 前后）后 ArkUI 默认把整棵组件树渲染避让到状态栏
    // 下面（布局仍全屏、渲染 [0,122] 起），getWindowAvoidArea(TYPE_SYSTEM)
    // 随之报 0——应用手动让位链路全断，状态栏底下露出窗口底色（其他颜色
    // 日记本主页顶部出现白色色块的根因）。显式扩展回边缘到边：渲染回到
    // [0,0] 起，TYPE_SYSTEM 重新报真实状态栏高，各页 safeAreaTopVp 让位
    // 重新生效（Tabs 自带的 expandSafeArea(BOTTOM) 同理保住了底缘）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
