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
 * 主题介绍弹窗（R-THEME-04/05）与桌面图标（R-THEME-06，阻塞 Q5）是 6.2 卡片的事。
 */
import { preferences } from '@kit.ArkData';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from './AppTheme';
import { BambooTheme } from './BambooTheme';
import { LeatherTheme } from './LeatherTheme';
import { KentTheme } from './KentTheme';

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

  /** 2026-09-16 主题改名时的旧 id 映射（R-THEME-01）。上架后可与 iOS 一起删 */
  static readonly LEGACY_IDS: Record<string, string> = {
    'washi': 'bamboo',
    'nordic': 'kent'
  };

  private readonly prefs: preferences.Preferences;
  private appContext: Context;

  currentThemeId: string = 'bamboo';
  current: AppTheme = new BambooTheme();

  private constructor(prefs: preferences.Preferences, appContext: Context) {
    this.prefs = prefs;
    this.appContext = appContext;
  }

  /**
   * 创建并完成初始化：读偏好 → 归一 → 写回 → 应用明暗 → 写 AppStorage。
   * 异步（读偏好），在 EntryAbility.onCreate 里 await 调用。
   */
  static async create(appContext: Context): Promise<ThemeManager> {
    const prefs = await preferences.getPreferences(appContext, ThemeManager.PREFS_NAME);
    const mgr = new ThemeManager(prefs, appContext);
    const raw = prefs.getSync(ThemeManager.PREF_KEY, 'bamboo');
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
    mgr.applyColorMode();
    AppStorage.setOrCreate(STORAGE_KEY_THEME, mgr.current);
    AppStorage.setOrCreate(STORAGE_KEY_THEME_ID, mgr.currentThemeId);
    return mgr;
  }

  /** 把可能是旧值的 id 归一成当前用的 id（纯函数，单测覆盖） */
  static canonicalThemeId(id: string): string {
    return ThemeManager.LEGACY_IDS[id] ?? id;
  }

  /** 按 id 取主题实例，不改变当前生效的主题（主题介绍弹窗预览用） */
  static themeFor(id: string): AppTheme {
    switch (ThemeManager.canonicalThemeId(id)) {
      case 'leather':
        return new LeatherTheme();
      case 'kent':
        return new KentTheme();
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

  /**
   * 按当前主题的 `colorMode` 设置应用级明暗（R-THEME-03）：
   * 深色主题 → `COLOR_MODE_DARK`（状态栏、系统弹窗、底栏全走深色）；
   * 其余 → `COLOR_MODE_NOT_SET`（恢复跟随系统）。
   */
  private applyColorMode(): void {
    const mode = this.current.colorMode === 'dark'
      ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    try {
      this.appContext.getApplicationContext().setColorMode(mode);
    } catch (err) {
      hilog.error(0x0000, 'ThemeManager', 'Failed to set colorMode %{public}s', JSON.stringify(err));
    }
  }
}
