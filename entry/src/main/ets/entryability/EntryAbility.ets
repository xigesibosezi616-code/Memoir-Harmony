import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ThemeManager, STORAGE_KEY_THEME_MANAGER } from '../theme/ThemeManager';

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
    this.initThemeThenLoad(windowStage);
  }

  /**
   * 先把主题初始化完（读偏好 → 旧 id 归一并写回 → 按主题设应用明暗），
   * 再加载首页 —— 保证首帧就是正确的颜色模式，深色主题不闪浅色。
   * 主题初始化只读写本机偏好，不发请求、不申请权限（R-APP-01）。
   */
  private async initThemeThenLoad(windowStage: window.WindowStage): Promise<void> {
    try {
      const manager = await ThemeManager.create(this.context);
      AppStorage.setOrCreate(STORAGE_KEY_THEME_MANAGER, manager);
    } catch (err) {
      // 主题初始化失败不拦启动：AppStorage 里已有默认素笺兜底（@StorageProp 初值）
      hilog.error(DOMAIN, TAG, 'theme init failed: %{public}s', JSON.stringify(err));
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
