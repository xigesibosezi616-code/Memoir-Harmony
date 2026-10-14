/**
 * 应用根视图（10_BUILD_MANUAL.md 1.5）。对应 iOS `MemoirApp.swift` 的 ZStack
 * （主界面常驻 + SplashView 盖顶）+ `ContentView.swift`（主界面 / 引导切换 +
 * 同意页 fullScreenCover）。
 *
 * 层叠顺序（自下而上，与 iOS 一致）：
 * 1. 主界面（1.6 前是占位空状态）或引导页 —— 主界面**常驻在底层**，
 *    开场结束只是把上面那层淡掉，底下是现成的画面，不会有构建卡顿（iOS 注释同款）
 * 2. 开场封面（EntryAbility 已算好本次启动放不放，本页不再判断）
 * 3. 隐私同意页 —— 盖在最上层（iOS fullScreenCover 是窗口级展示，天然在最上）。
 *    首启时它会先盖住开场：用户同意之前一切数据处理都免谈（R-APP-01）
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
import { MainPlaceholderView } from '../views/main/MainPlaceholderView';

@Entry
@Component
struct Index {
  @StorageProp(STORAGE_KEY_HAS_COMPLETED_ONBOARDING) hasCompletedOnboarding: boolean = false;
  @StorageLink(STORAGE_KEY_NEEDS_LEGAL_CONSENT) needsLegalConsent: boolean = true;
  @StorageLink(STORAGE_KEY_SHOW_SPLASH) showSplash: boolean = false;

  build() {
    Stack() {
      if (this.hasCompletedOnboarding) {
        // 1.6 主框架落地时换成真实 Tabs，这里现在是空状态占位 + 调试入口
        MainPlaceholderView()
      } else {
        OnboardingView()
      }

      if (this.showSplash) {
        // 不需要再包过渡：淡出是 SplashView 自己做的，
        // 回调进来时它已完全透明，这一步只是摘掉一层看不见的东西（iOS 同款）
        SplashView({
          onFinish: () => {
            this.showSplash = false;
          }
        })
      }

      if (this.needsLegalConsent) {
        LegalConsentView({
          onAccept: () => {
            // 🔴 存版本号而不是布尔值（R-APP-02）：政策更新（改
            // LEGAL_CURRENT_VERSION）后老用户会重新看到这一页
            AppPrefs.putString(PREF_KEY_ACCEPTED_LEGAL_VERSION, LEGAL_CURRENT_VERSION);
            this.needsLegalConsent = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
