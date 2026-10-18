/**
 * 沉浸式全屏（10_BUILD_MANUAL.md 1.6）。
 *
 * - `setWindowLayoutFullScreen(true)`：内容延伸到状态栏 / 手势条下面
 * - 避让区（状态栏、手势条）换算成 vp 发布到 AppStorage，页面自行让位
 *   （px / `display.densityPixels`，避让区回调时重算——折叠屏密度会变）
 * - 挖孔（灵动岛）矩形单独查 `display.getCutoutInfo` 发布（挖孔不属于避让区，
 *   faqs-arkui-1244；相机等异形屏页面按精确矩形贴合，faqs-arkui-274）
 * - 系统栏背景全透明、内容色随主题背景的感知亮度推导（BT.601，R-HOME-06 同法）
 *
 * EntryAbility 拿主窗口构造；Index 观察主题变化时调 `syncSystemBarColors`。
 * 纯函数（vpFromPx / perceivedLuminance / systemBarContentColorFor）单测覆盖
 * （`ImmersiveChrome.test.ets`）。
 */
import { window, display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../theme/AppTheme';
import { BusinessError, SuppressWarnings, SuppressWarningsType } from '@kit.BasicServicesKit';

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
/** AppStorage key：挖孔（灵动岛）左边（vp，距屏幕左；无挖孔 = 0） */
export const STORAGE_KEY_CUTOUT_LEFT_VP = 'cutoutLeftVp';
/** AppStorage key：挖孔顶边（vp，距屏幕顶；无挖孔 = 0） */
export const STORAGE_KEY_CUTOUT_TOP_VP = 'cutoutTopVp';
/** AppStorage key：挖孔宽（vp；无挖孔 = 0） */
export const STORAGE_KEY_CUTOUT_WIDTH_VP = 'cutoutWidthVp';
/** AppStorage key：挖孔高（vp；无挖孔 = 0。>0 即灵动岛机型） */
export const STORAGE_KEY_CUTOUT_HEIGHT_VP = 'cutoutHeightVp';
/**
 * AppStorage key：照片全屏查看期间藏主框架浮动 Tab 栏。
 * 页面内浮层（弃用 bindContentCover 后）盖不住 HdsTabs 的 barOverlap 层，
 * 全屏打开的页面置 true、关闭置 false，MainTabsView 读它把 barOpacity 置 0。
 */
export const STORAGE_KEY_HIDE_TAB_BAR = 'hideTabBar';

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
  // 先四舍五入消浮点误差：灰 0x80 数学上恰为 128（黑字），
  // 直接比较会算成 127.999…→ 误判白字
  return Math.round(perceivedLuminance(backgroundArgb)) < 128 ? '#FFFFFF' : '#000000';
}

/**
 * 挖孔（灵动岛）相机机身几何（全 vp，纯计算。iOS `PaperCameraView.swift` 同款逻辑）：
 * 机身顶边只比挖孔顶高 2（框沿高过岛沿，岛不可能凸出来）、
 * 画面顶边越过挖孔底再留 9、悬浮机身、收起态药丸整圈包住挖孔。
 * 无挖孔机型（平板等）不构这个类，调用方走普通布局。
 */
export class IslandBodyGeometry {
  /** 展开态机身顶边（距屏幕顶） */
  readonly bodyTop: number;
  /** 顶黑边（机身顶边 → 画面顶边） */
  readonly topBezel: number;
  /** 收起态药丸顶边（距屏幕顶） */
  readonly pillTop: number;
  /** 收起态药丸左边（距屏幕左） */
  readonly pillLeft: number;
  readonly pillWidth: number;
  readonly pillHeight: number;

  private constructor(bodyTop: number, topBezel: number, pillTop: number,
    pillLeft: number, pillWidth: number, pillHeight: number) {
    this.bodyTop = bodyTop;
    this.topBezel = topBezel;
    this.pillTop = pillTop;
    this.pillLeft = pillLeft;
    this.pillWidth = pillWidth;
    this.pillHeight = pillHeight;
  }

  static compute(screenWidthVp: number, cutoutLeftVp: number, cutoutTopVp: number,
    cutoutWidthVp: number, cutoutHeightVp: number): IslandBodyGeometry {
    // 机身顶边高出挖孔顶 2（iOS frameTopNudge -2 同款）
    const bodyTop = Math.max(0, cutoutTopVp - 2);
    // 画面顶边越过挖孔底再留 9（iOS topBezel 余量同款）；极端扁挖孔也保底不窄于侧黑边
    const topBezel = Math.max(cutoutTopVp + cutoutHeightVp + 9 - bodyTop, VIEWFINDER_MIN_TOP_BEZEL);
    // 药丸整圈包住挖孔：上下左右各留 4 黑边（Apple 药丸 = 岛大小，我们挖孔小，贴身包即可）
    const pillWidth = cutoutWidthVp + 8;
    const pillHeight = cutoutHeightVp + 8;
    const pillTop = Math.max(0, cutoutTopVp - 4);
    // 挖孔贴边时药丸不出屏（左右夹取）
    const pillLeft = Math.min(Math.max(0, cutoutLeftVp + cutoutWidthVp / 2 - pillWidth / 2),
      Math.max(0, screenWidthVp - pillWidth));
    return new IslandBodyGeometry(bodyTop, topBezel, pillTop, pillLeft, pillWidth, pillHeight);
  }
}

/** 顶黑边保底（vp）：极端几何下顶黑边不允许薄过它 */
const VIEWFINDER_MIN_TOP_BEZEL: number = 12;

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
      this.publishCutout(density);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'publishAvoidAreas failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 挖孔（灵动岛）矩形发布（faqs-arkui-274 官方范式：display.getCoutoutInfo 拿精确矩形）。
   * 挖孔不属于窗口避让区（faqs-arkui-1244），避让区高度≠挖孔位置——必须单独查。
   * 无挖孔设备四个值全 0（调用方据此走普通布局）。
   */
  private publishCutout(density: number): void {
    try {
      display.getDefaultDisplaySync().getCutoutInfo()
        .then((info: display.CutoutInfo): void => {
          let left = 0;
          let top = 0;
          let width = 0;
          let height = 0;
          if (info.boundingRects.length > 0) {
            const rect: display.Rect = info.boundingRects[0];
            left = vpFromPx(rect.left, density);
            top = vpFromPx(rect.top, density);
            width = vpFromPx(rect.width, density);
            height = vpFromPx(rect.height, density);
          }
          AppStorage.setOrCreate(STORAGE_KEY_CUTOUT_LEFT_VP, left);
          AppStorage.setOrCreate(STORAGE_KEY_CUTOUT_TOP_VP, top);
          AppStorage.setOrCreate(STORAGE_KEY_CUTOUT_WIDTH_VP, width);
          AppStorage.setOrCreate(STORAGE_KEY_CUTOUT_HEIGHT_VP, height);
        })
        .catch((err: BusinessError): void => {
          hilog.error(DOMAIN, TAG, 'getCutoutInfo rejected: %{public}d %{public}s', err.code, err.message);
        });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'getCutoutInfo failed: %{public}s', JSON.stringify(err));
    }
  }
}
