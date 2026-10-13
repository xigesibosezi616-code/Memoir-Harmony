import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ThemeManager, STORAGE_KEY_THEME_MANAGER } from '../theme/ThemeManager';
import { LanguageManager } from '../services/LanguageManager';

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
   * 先把主题、语言初始化完，再加载首页 —— 保证首帧就是正确的颜色模式和语言：
   * - 主题：读偏好 → 归一 → 应用明暗（R-THEME-01/03）
   * - 语言：读偏好 → 空则按系统语言解析并立刻落盘（R-LANG-02）→ 设 App 首选语言，
   *   `$r` 从第一屏起就按所选语言解析（R-LANG-03/08）
   * 两者都只读写本机，不发请求、不申请权限（R-APP-01）。
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
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
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
