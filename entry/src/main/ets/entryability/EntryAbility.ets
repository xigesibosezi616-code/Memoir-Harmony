import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ThemeManager, STORAGE_KEY_THEME_ID, STORAGE_KEY_THEME_MANAGER } from '../theme/ThemeManager';
import { LanguageManager } from '../services/LanguageManager';
import { AppPrefs, PREF_KEY_ACCEPTED_LEGAL_VERSION, PREF_KEY_HAS_COMPLETED_ONBOARDING,
  PREF_KEY_SHOW_SPLASH_ANIMATION, STORAGE_KEY_NEEDS_LEGAL_CONSENT,
  STORAGE_KEY_HAS_COMPLETED_ONBOARDING, STORAGE_KEY_SHOW_SPLASH } from '../services/AppPrefs';
import { needsLegalConsent } from '../views/legal/LegalDocument';
import { splashImageFor } from '../views/splash/SplashCoverPool';
import { MigrationRunner } from '../services/MigrationRunner';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    this.initThenLoad(windowStage);
  }

  /**
   * 先把主题、语言、首启状态初始化完，再加载首页 —— 保证首帧就是正确的
   * 颜色模式、语言和该出现的那一层（同意页 / 引导 / 开场封面，10_BUILD_MANUAL.md 1.5）：
   * - 主题：读偏好 → 归一 → 应用明暗（R-THEME-01/03）
   * - 语言：读偏好 → 空则按系统语言解析并立刻落盘（R-LANG-02）→ 设 App 首选语言，
   *   `$r` 从第一屏起就按所选语言解析（R-LANG-03/08）
   * - 首启状态（AppPrefs）：是否需要同意（版本比对 R-APP-02）、引导走完没有、
   *   本次启动放不放开场（R-APP-08：主题封面图存在 **且** 用户开关开着才放）
   * 以上全部只读写本机，不发请求、不申请权限（R-APP-01）——
   * 同意之前除这些本地初始化外什么都不能做。
   */
  private async initThenLoad(windowStage: window.WindowStage): Promise<void> {
    try {
      const manager = await ThemeManager.create(this.context);
      AppStorage.setOrCreate(STORAGE_KEY_THEME_MANAGER, manager);
    } catch (err) {
      // 主题初始化失败不拦启动：AppStorage 里已有默认素笺兜底（@StorageProp 初值）
      hilog.error(DOMAIN, TAG, 'theme init failed: %{public}s', JSON.stringify(err));
    }
    try {
      await LanguageManager.create(this.context);
    } catch (err) {
      // 语言初始化失败不拦启动：资源回退按系统语言解析，调试页可再切换
      hilog.error(DOMAIN, TAG, 'language init failed: %{public}s', JSON.stringify(err));
    }

    let needsConsent = true;
    let hasCompletedOnboarding = false;
    let showSplash = false;
    try {
      await AppPrefs.load(this.context);
      needsConsent = needsLegalConsent(AppPrefs.getString(PREF_KEY_ACCEPTED_LEGAL_VERSION, ''));
      hasCompletedOnboarding = AppPrefs.getBool(PREF_KEY_HAS_COMPLETED_ONBOARDING, false);
      // 开场封面在这里就判断掉（iOS 在 MemoirApp @State 初值里做同样的事）：
      // 当前主题没配封面图时，连一帧封面背景都不该闪
      const themeId: string = AppStorage.get<string>(STORAGE_KEY_THEME_ID) ?? 'bamboo';
      showSplash = splashImageFor(themeId) !== undefined
        && AppPrefs.getBool(PREF_KEY_SHOW_SPLASH_ANIMATION, true);
    } catch (err) {
      // 🔴 偏好打不开 = 不知道用户同意过没有 → 按「没同意过」处理：
      // 宁可重弹一次同意页，不能跳过合规告知（R-APP-01 失败要落在保守侧）
      hilog.error(DOMAIN, TAG, 'prefs init failed, fail closed to consent: %{public}s', JSON.stringify(err));
      needsConsent = true;
    }
    AppStorage.setOrCreate(STORAGE_KEY_NEEDS_LEGAL_CONSENT, needsConsent);
    AppStorage.setOrCreate(STORAGE_KEY_HAS_COMPLETED_ONBOARDING, hasCompletedOnboarding);
    AppStorage.setOrCreate(STORAGE_KEY_SHOW_SPLASH, showSplash);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
    });

    // 一次性数据迁移：不挡首帧，首页加载后在后台跑（当前任务表为空，框架先立着）
    MigrationRunner.runPendingMigrations(this.context).catch((err: Object) => {
      hilog.error(DOMAIN, TAG, 'runPendingMigrations failed: %{public}s', JSON.stringify(err));
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
