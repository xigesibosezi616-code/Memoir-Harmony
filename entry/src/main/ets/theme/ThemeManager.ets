/**
 * 主题管理（10_BUILD_MANUAL.md 1.1）。对应 iOS `Theme/ThemeManager.swift`。
 *
 * - 当前主题 id 存偏好 `selectedTheme`（与 iOS 同名，方便对照）
 * - 旧 id 归一：`washi` → `bamboo`、`nordic` → `kent`，读出来先归一再用，
 *   归一结果写回（R-THEME-01；鸿蒙是首版没有存量旧值，但映射表留着与 iOS 对齐）
 * - 切换即时生效：主题对象放 AppStorage（`theme` / `themeId`），整体替换触发刷新，
 *   页面里用 `@StorageLink` / `@StorageProp` 取（1.1 验收：切换当场变，不重启）
 * - 深色主题（皮革）在应用级统一设 `COLOR_MODE_DARK`，其余恢复跟随系统（R-THEME-03）
 *
 * App 图标（R-THEME-06，6.2）：`appIconSelection` 空串 = 跟随主题（默认），否则固定该 id。
 * 切换走 AGC 图标管理服务（`appInfoManager`，5.0.3(15)+；上架后在 AGC「图标管理」
 * 按主题 id 同名创建动态图标即生效）。开发期未上架服务不可用：调用失败只回调给
 * 调用方提示，**主题不回滚**（R-THEME-06 原文）。
 */
import { preferences } from '@kit.ArkData';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { appInfoManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from './AppTheme';
import { BambooTheme } from './BambooTheme';
import { LeatherTheme } from './LeatherTheme';
import { KentTheme } from './KentTheme';
import { PolarTheme } from './PolarTheme';

/** AppStorage key：当前主题对象（整体替换） */
export const STORAGE_KEY_THEME = 'theme';
/** AppStorage key：当前主题 id */
export const STORAGE_KEY_THEME_ID = 'themeId';
/** AppStorage key：ThemeManager 实例（1.6 接 AppEnvironment @Provide 后移除） */
export const STORAGE_KEY_THEME_MANAGER = 'themeManager';

export class ThemeManager {
  /** 偏好文件名（1.3 起数据层统一用它，RDB 之外的小状态都放这里） */
  static readonly PREFS_NAME = 'memoir_prefs';
  static readonly PREF_KEY = 'selectedTheme';
  /** App 图标选择偏好键（与 iOS 同名）：空串 = 跟随主题 */
  static readonly PREF_KEY_APP_ICON = 'appIconSelection';
  /** 默认图标对应素笺：它是上架时的主图标，切回它 = 恢复默认（disableDynamicIcon） */
  static readonly ICON_ID_DEFAULT = 'bamboo';

  /** 2026-09-16 主题改名时的旧 id 映射（R-THEME-01）。上架后可与 iOS 一起删 */
  static readonly LEGACY_IDS: Record<string, string> = {
    'washi': 'bamboo',
    'nordic': 'kent'
  };

  private readonly prefs: preferences.Preferences;
  private appContext: Context;

  currentThemeId: string = 'bamboo';
  current: AppTheme = new BambooTheme();
  /** 用户选的图标 id；空串 = 跟随主题（默认）。存偏好 `appIconSelection` */
  appIconSelection: string = '';

  private constructor(prefs: preferences.Preferences, appContext: Context) {
    this.prefs = prefs;
    this.appContext = appContext;
  }

  /**
   * 创建并完成初始化：读偏好 → 归一 → 写回 → 应用明暗 → 写 AppStorage。
   * 异步（读偏好），在 EntryAbility.onCreate 里 await 调用。
   */
  static async create(appContext: Context): Promise<ThemeManager> {
    let prefs: preferences.Preferences;
    try {
      prefs = await preferences.getPreferences(appContext, ThemeManager.PREFS_NAME);
    } catch (err) {
      // 偏好打不开：抛给调用方（EntryAbility 已 catch，启动不拦，AppStorage 里有素笺兜底）
      hilog.error(0x0000, 'ThemeManager', 'getPreferences failed: %{public}s', JSON.stringify(err));
      throw new Error('ThemeManager.getPreferences failed');
    }
    const mgr = new ThemeManager(prefs, appContext);
    let raw: preferences.ValueType = 'bamboo';
    try {
      raw = prefs.getSync(ThemeManager.PREF_KEY, 'bamboo');
    } catch (err) {
      // 读失败当没存过：走素笺兜底
      hilog.error(0x0000, 'ThemeManager', 'read selectedTheme failed: %{public}s', JSON.stringify(err));
    }
    const saved = typeof raw === 'string' ? raw : 'bamboo';
    const canonical = ThemeManager.canonicalThemeId(saved);
    if (canonical !== saved) {
      try {
        prefs.putSync(ThemeManager.PREF_KEY, canonical);
        prefs.flush();
      } catch (err) {
        hilog.error(0x0000, 'ThemeManager', 'Failed to persist legacy id: %{public}s', JSON.stringify(err));
      }
    }
    mgr.currentThemeId = canonical;
    mgr.current = ThemeManager.themeFor(canonical);
    mgr.appIconSelection = ThemeManager.readAndCanonicalizeIconSelection(prefs);
    mgr.applyColorMode();
    AppStorage.setOrCreate(STORAGE_KEY_THEME, mgr.current);
    AppStorage.setOrCreate(STORAGE_KEY_THEME_ID, mgr.currentThemeId);
    return mgr;
  }

  /** 把可能是旧值的 id 归一成当前用的 id（纯函数，单测覆盖） */
  static canonicalThemeId(id: string): string {
    return ThemeManager.LEGACY_IDS[id] ?? id;
  }

  /** 读图标选择偏好并归一（旧 id 映射 + 非法值回跟随；归一结果写回） */
  private static readAndCanonicalizeIconSelection(prefs: preferences.Preferences): string {
    let saved = '';
    try {
      const raw: preferences.ValueType = prefs.getSync(ThemeManager.PREF_KEY_APP_ICON, '');
      if (typeof raw === 'string') {
        saved = raw;
      }
    } catch (err) {
      hilog.error(0x0000, 'ThemeManager', 'read appIconSelection failed: %{public}s', JSON.stringify(err));
    }
    // 认识的（含旧 id）归一；不认识的一律当「跟随主题」处理，与 iOS「删图标退回跟随」同款
    const known = ['', 'bamboo', 'leather', 'kent', 'polar'];
    const canonical = known.includes(saved) ? ThemeManager.canonicalThemeId(saved) : '';
    if (canonical !== saved) {
      try {
        prefs.putSync(ThemeManager.PREF_KEY_APP_ICON, canonical);
        prefs.flush();
      } catch (err) {
        hilog.error(0x0000, 'ThemeManager', 'Failed to persist icon selection: %{public}s', JSON.stringify(err));
      }
    }
    return canonical;
  }

  // ---- App 图标规则（R-THEME-06；纯函数，单测覆盖） ----

  /** 是否「跟随主题」模式（没手动固定过图标） */
  static isFollowingIcon(selection: string): boolean {
    return selection === '';
  }

  /** 当前该用哪个图标：选了用选的，没选跟主题走 */
  static resolvedIconId(selection: string, themeId: string): string {
    if (ThemeManager.isFollowingIcon(selection)) {
      return themeId;
    }
    return selection;
  }

  /** 切主题后图标选择变成什么：一并换 = 回跟随；仅换主题 = 跟随态先把当前图标固定 */
  static iconSelectionAfterSwitch(selection: string, themeId: string, alsoIcon: boolean): string {
    if (alsoIcon) {
      return '';
    }
    if (ThemeManager.isFollowingIcon(selection)) {
      return ThemeManager.resolvedIconId(selection, themeId);
    }
    return selection;
  }

  /** 按 id 取主题实例，不改变当前生效的主题（主题介绍弹窗预览用） */
  static themeFor(id: string): AppTheme {
    switch (ThemeManager.canonicalThemeId(id)) {
      case 'leather':
        return new LeatherTheme();
      case 'kent':
        return new KentTheme();
      case 'polar':
        return new PolarTheme();
      default:
        return new BambooTheme();
    }
  }

  /** 切换主题：归一 → 替换 AppStorage 对象 → 应用明暗 → 落盘。当场生效；落盘失败只记日志（本次会话仍生效） */
  setTheme(id: string): void {
    const canonical = ThemeManager.canonicalThemeId(id);
    this.currentThemeId = canonical;
    this.current = ThemeManager.themeFor(canonical);
    try {
      this.prefs.putSync(ThemeManager.PREF_KEY, canonical);
      this.prefs.flush();
    } catch (err) {
      hilog.error(0x0000, 'ThemeManager', 'Failed to persist theme: %{public}s', JSON.stringify(err));
    }
    AppStorage.setOrCreate(STORAGE_KEY_THEME, this.current);
    AppStorage.setOrCreate(STORAGE_KEY_THEME_ID, canonical);
    this.applyColorMode();
  }

  // ---- App 图标（R-THEME-06） ----

  /** 是否「跟随主题」模式 */
  isFollowingThemeIcon(): boolean {
    return ThemeManager.isFollowingIcon(this.appIconSelection);
  }

  /** 当前该用的图标 id（选了用选的，没选跟主题走） */
  resolvedAppIconId(): string {
    return ThemeManager.resolvedIconId(this.appIconSelection, this.currentThemeId);
  }

  /**
   * 主题介绍弹窗那两个按钮统一走这里（iOS switchTheme 同款时序）：
   * 先换主题、最后才动图标 —— 反过来会先切旧主题的图标再切新的，多一次系统提示。
   * - `alsoIcon` = true：一并更换图标（回「跟随主题」），换完主题切图标
   * - `alsoIcon` = false：仅换主题，图标保持现在这个不动（跟随态先把当前图标固定下来）
   * - `onIconFailure`：图标没换成时的回调。**主题不回滚**（R-THEME-06）
   */
  switchTheme(id: string, alsoIcon: boolean, onIconFailure?: (error: BusinessError) => void): void {
    this.appIconSelection =
      ThemeManager.iconSelectionAfterSwitch(this.appIconSelection, this.currentThemeId, alsoIcon);
    this.persistIconSelection();
    this.setTheme(id);
    if (alsoIcon) {
      this.applyAppIcon(onIconFailure);
    }
  }

  /**
   * 图标选择页用：记下用户的选择并只切换一次（iOS selectAppIcon 同款；`''` = 回跟随主题）。
   * 🔴 不能先赋值再调 applyAppIcon —— 那样 apply 里 resolved 值已经变了，无法判断「目标与当前相同」。
   */
  selectAppIcon(id: string, onIconFailure?: (error: BusinessError) => void): void {
    this.appIconSelection = id;
    this.persistIconSelection();
    this.applyAppIcon(onIconFailure);
  }

  /** 把 `resolvedAppIconId` 真正应用到系统（AGC 图标管理服务，5.0.3(15)+）。 */
  private applyAppIcon(onIconFailure?: (error: BusinessError) => void): void {
    const target = this.resolvedAppIconId();
    try {
      if (target === ThemeManager.ICON_ID_DEFAULT) {
        // 素笺 = 上架时的主图标：恢复默认（与 iOS bamboo alternateName=nil 同义）
        appInfoManager.disableDynamicIcon().catch((error: BusinessError) => {
          this.reportIconFailure('disableDynamicIcon', error, onIconFailure);
        });
      } else {
        appInfoManager.selectDynamicIcon(target).catch((error: BusinessError) => {
          this.reportIconFailure('selectDynamicIcon', error, onIconFailure);
        });
      }
    } catch (err) {
      // 同步异常（设备无此接口等），按失败回调处理
      const be = err as BusinessError;
      this.reportIconFailure('applyAppIcon', be, onIconFailure);
    }
  }

  /** 图标切换失败：记日志 + 回调给调用方提示（主题不回滚，R-THEME-06） */
  private reportIconFailure(api: string, error: BusinessError,
    onIconFailure?: (error: BusinessError) => void): void {
    hilog.error(0x0000, 'ThemeManager', '%{public}s failed, code: %{public}d, message: %{public}s',
      api, error.code, error.message);
    if (onIconFailure !== undefined) {
      onIconFailure(error);
    }
  }

  /** 图标选择落盘；失败只记日志（本次会话仍生效） */
  private persistIconSelection(): void {
    try {
      this.prefs.putSync(ThemeManager.PREF_KEY_APP_ICON, this.appIconSelection);
      this.prefs.flush();
    } catch (err) {
      hilog.error(0x0000, 'ThemeManager', 'Failed to persist icon selection: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 按当前主题的 `colorMode` 设置应用级明暗（R-THEME-03）：
   * 深色主题 → `COLOR_MODE_DARK`；浅色主题 → `COLOR_MODE_LIGHT`。
   * 浅色主题必须**显式**切浅色而不是跟随系统：设备在系统深色模式下，
   * 系统玻璃（HdsTabs 材质面板、键盘）会按深色渲染，浅色页面上
   * tab bar 下方出现深灰带（2026-10-15 真机反馈）；显式 LIGHT 让
   * 系统玻璃与浅色主题一致。
   */
  private applyColorMode(): void {
    const mode = this.current.colorMode === 'dark'
      ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    try {
      this.appContext.getApplicationContext().setColorMode(mode);
    } catch (err) {
      hilog.error(0x0000, 'ThemeManager', 'Failed to set colorMode %{public}s', JSON.stringify(err));
    }
  }
}
