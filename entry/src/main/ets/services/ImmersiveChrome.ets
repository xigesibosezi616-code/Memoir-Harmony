/**
 * 沉浸式全屏（10_BUILD_MANUAL.md 1.6）。
 *
 * - `setWindowLayoutFullScreen(true)`：内容延伸到状态栏 / 手势条下面
 * - 避让区（状态栏、手势条）换算成 vp 发布到 AppStorage，页面自行让位
 *   （px / `display.densityPixels`，避让区回调时重算——折叠屏密度会变）
 * - 系统栏背景全透明、内容色随主题背景的感知亮度推导（BT.601，R-HOME-06 同法）
 *
 * EntryAbility 拿主窗口构造；Index 观察主题变化时调 `syncSystemBarColors`。
 * 纯函数（vpFromPx / perceivedLuminance / systemBarContentColorFor）单测覆盖
 * （`ImmersiveChrome.test.ets`）。
 */
import { window, display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../theme/AppTheme';
import { SuppressWarnings, SuppressWarningsType } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;
const TAG = 'ImmersiveChrome';

/** AppStorage key：顶部避让高度（vp，沉浸式下页面顶部让位用） */
export const STORAGE_KEY_SAFE_AREA_TOP_VP = 'safeAreaTopVp';
/** AppStorage key：底部避让高度（vp，手势条高度，浮动底栏让位用） */
export const STORAGE_KEY_SAFE_AREA_BOTTOM_VP = 'safeAreaBottomVp';
/** AppStorage key：左侧避让宽度（vp，横屏挖孔 / 圆角让位用） */
export const STORAGE_KEY_SAFE_AREA_LEFT_VP = 'safeAreaLeftVp';
/** AppStorage key：右侧避让宽度（vp） */
export const STORAGE_KEY_SAFE_AREA_RIGHT_VP = 'safeAreaRightVp';

/** px → vp（`display.densityPixels`；密度非法时返回 0 兜底。纯函数） */
export function vpFromPx(px: number, densityPixels: number): number {
  if (densityPixels <= 0) {
    return 0;
  }
  return px / densityPixels;
}

/** BT.601 感知亮度（0~255；R-HOME-06 同法。纯函数） */
export function perceivedLuminance(argb: number): number {
  const r: number = (argb >> 16) & 0xFF;
  const g: number = (argb >> 8) & 0xFF;
  const b: number = argb & 0xFF;
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

/** 系统栏内容色：背景感知亮度低于 128 用白字，否则黑字（纯函数） */
export function systemBarContentColorFor(backgroundArgb: number): string {
  return perceivedLuminance(backgroundArgb) < 128 ? '#FFFFFF' : '#000000';
}

@SuppressWarnings({ rules: [SuppressWarningsType.SYSCAP] })
export class ImmersiveChrome {
  private readonly mainWindow: window.Window;

  constructor(mainWindow: window.Window) {
    this.mainWindow = mainWindow;
  }

  /** 开启沉浸式全屏 + 订阅避让区变化。onWindowStageCreate 调一次；失败只记日志，不拦启动 */
  async setup(): Promise<void> {
    try {
      await this.mainWindow.setWindowLayoutFullScreen(true);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', JSON.stringify(err));
    }
    this.publishAvoidAreas();
    try {
      this.mainWindow.on('avoidAreaChange', (): void => {
        this.publishAvoidAreas();
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'on avoidAreaChange failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 系统栏配色随主题（背景全透明、内容色按主题背景亮度）。主题切换 / 首帧时调 */
  syncSystemBarColors(theme: AppTheme): void {
    let contentColor = '#000000';
    if (typeof theme.background === 'number') {
      contentColor = systemBarContentColorFor(theme.background);
    } else if (theme.colorMode === 'dark') {
      // 背景不是数字色值时按明暗模式兜底：深色主题配白字
      contentColor = '#FFFFFF';
    }
    try {
      this.mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: contentColor,
        navigationBarColor: '#00000000',
        navigationBarContentColor: contentColor
      })
        .catch((err: Object): void => {
          hilog.error(DOMAIN, TAG, 'setWindowSystemBarProperties rejected: %{public}s', JSON.stringify(err));
        });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', JSON.stringify(err));
    }
  }

  private publishAvoidAreas(): void {
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels;
      // getWindowAvoidArea（since 9，同步）——getAvoidArea 已弃用
      const systemArea: window.AvoidArea =
        this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicatorArea: window.AvoidArea =
        this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate(STORAGE_KEY_SAFE_AREA_TOP_VP, vpFromPx(systemArea.topRect.height, density));
      AppStorage.setOrCreate(STORAGE_KEY_SAFE_AREA_BOTTOM_VP, vpFromPx(indicatorArea.bottomRect.height, density));
      AppStorage.setOrCreate(STORAGE_KEY_SAFE_AREA_LEFT_VP, vpFromPx(systemArea.leftRect.width, density));
      AppStorage.setOrCreate(STORAGE_KEY_SAFE_AREA_RIGHT_VP, vpFromPx(systemArea.rightRect.width, density));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'publishAvoidAreas failed: %{public}s', JSON.stringify(err));
    }
  }
}
