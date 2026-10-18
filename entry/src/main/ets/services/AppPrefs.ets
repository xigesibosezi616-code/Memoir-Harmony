/**
 * 应用偏好读写（10_BUILD_MANUAL.md 1.5）。对应 iOS 各处 `@AppStorage` 的 UserDefaults 键。
 *
 * - 偏好文件与 ThemeManager / LanguageManager 同一个（`memoir_prefs`），
 *   `preferences.getPreferences` 按名缓存实例，多处获取拿到的是同一份
 * - 键名与 iOS 同名，方便对照（`hasCompletedOnboarding`、`acceptedLegalVersion`…）
 * - 写入 putSync 后立刻 flush（异步、失败只记日志）——鸿蒙 preferences
 *   不显式 flush 就不落盘；极端的「同意后立刻杀进程」场景丢一条记录，
 *   后果只是下次重弹同意页（合规上偏保守），可接受
 * - UI 需要即时反映的状态由调用方自行镜像进 AppStorage（整体替换驱动重渲染）
 */
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

// ---- 偏好键（与 iOS 同名）----

/** 引导是否走完（对应 iOS `hasCompletedOnboarding`） */
export const PREF_KEY_HAS_COMPLETED_ONBOARDING = 'hasCompletedOnboarding';
/** 用户同意过的协议版本号。空串 = 从没同意过（R-APP-02） */
export const PREF_KEY_ACCEPTED_LEGAL_VERSION = 'acceptedLegalVersion';
/** 笔友名（对应 iOS `penPalName`，默认「青鸟」） */
export const PREF_KEY_PEN_PAL_NAME = 'penPalName';
/** 开场封面开关（对应 iOS `showSplashAnimation`，默认开） */
export const PREF_KEY_SHOW_SPLASH_ANIMATION = 'showSplashAnimation';
/** 插照片预选的相纸（对应 iOS `defaultPaperStyle`，默认 polaroid；05 §3.5） */
export const PREF_KEY_DEFAULT_PAPER_STYLE = 'defaultPaperStyle';

// ---- AppStorage 镜像 key（EntryAbility 启动时由偏好算好写入，UI 用 @StorageLink/@StorageProp 观察）----

/** 是否需要展示同意页（acceptedLegalVersion ≠ 当前版本）。同意后 Index 写 false */
export const STORAGE_KEY_NEEDS_LEGAL_CONSENT = 'needsLegalConsent';
/** 引导是否走完（镜像 `hasCompletedOnboarding` 偏好，OnboardingView 写 true 时 Index 切走引导页） */
export const STORAGE_KEY_HAS_COMPLETED_ONBOARDING = 'hasCompletedOnboarding';
/**
 * 本次启动是否放开场封面。EntryAbility 已合并完三件事：主题封面图存不存在、
 * `showSplashAnimation` 用户开关、首启不查 —— UI 直接照这个值显示，不再自行判断
 */
export const STORAGE_KEY_SHOW_SPLASH = 'showSplash';

export class AppPrefs {
  static readonly PREFS_NAME = 'memoir_prefs';

  private static prefs: preferences.Preferences | null = null;

  /** 打开（或复用系统缓存的）偏好实例。启动序列里 await 一次，之后读写全同步 */
  static async load(context: Context): Promise<void> {
    if (AppPrefs.prefs !== null) {
      return;
    }
    try {
      AppPrefs.prefs = await preferences.getPreferences(context, AppPrefs.PREFS_NAME);
    } catch (err) {
      hilog.error(0x0000, 'AppPrefs', 'getPreferences failed: %{public}s', JSON.stringify(err));
      // 抛给 EntryAbility：偏好打不开按「没同意过」处理，不能跳过合规告知
      throw new Error('AppPrefs.getPreferences failed');
    }
  }

  /** 未 load 时的兜底：拿不到偏好就返回默认值并记日志（读失败不影响启动） */
  static getString(key: string, def: string): string {
    if (AppPrefs.prefs === null) {
      hilog.error(0x0000, 'AppPrefs', 'read before load, key=%{public}s', key);
      return def;
    }
    try {
      const raw: preferences.ValueType = AppPrefs.prefs.getSync(key, def);
      return typeof raw === 'string' ? raw : def;
    } catch (err) {
      hilog.error(0x0000, 'AppPrefs', 'getString failed key=%{public}s err=%{public}s', key, JSON.stringify(err));
      return def;
    }
  }

  static putString(key: string, value: string): void {
    if (AppPrefs.prefs === null) {
      hilog.error(0x0000, 'AppPrefs', 'write before load, key=%{public}s', key);
      return;
    }
    try {
      AppPrefs.prefs.putSync(key, value);
      AppPrefs.prefs.flush();
    } catch (err) {
      hilog.error(0x0000, 'AppPrefs', 'putString failed key=%{public}s err=%{public}s', key, JSON.stringify(err));
    }
  }

  static getBool(key: string, def: boolean): boolean {
    if (AppPrefs.prefs === null) {
      hilog.error(0x0000, 'AppPrefs', 'read before load, key=%{public}s', key);
      return def;
    }
    try {
      const raw: preferences.ValueType = AppPrefs.prefs.getSync(key, def);
      return typeof raw === 'boolean' ? raw : def;
    } catch (err) {
      hilog.error(0x0000, 'AppPrefs', 'getBool failed key=%{public}s err=%{public}s', key, JSON.stringify(err));
      return def;
    }
  }

  static putBool(key: string, value: boolean): void {
    if (AppPrefs.prefs === null) {
      hilog.error(0x0000, 'AppPrefs', 'write before load, key=%{public}s', key);
      return;
    }
    try {
      AppPrefs.prefs.putSync(key, value);
      AppPrefs.prefs.flush();
    } catch (err) {
      hilog.error(0x0000, 'AppPrefs', 'putBool failed key=%{public}s err=%{public}s', key, JSON.stringify(err));
    }
  }
}
