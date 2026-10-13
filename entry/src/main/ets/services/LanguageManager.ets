/**
 * 多语言管理（10_BUILD_MANUAL.md 1.2）。对应 iOS `Services/LanguageManager.swift`。
 *
 * - 当前语言存偏好 `appLanguage`（与 iOS 同名 key）
 * - 七种语言顺序固定（R-LANG-01）；**没有「跟随系统」**（R-LANG-02：
 *   首启按系统语言定一个并立刻落盘，之后就是一个明确的语言）
 * - App 级首选语言走 `i18n.System.setAppPreferredLanguage`，
 *   `$r('app.string.*')` 会按它解析（替代 iOS 的 `Bundle.appLanguage`）
 * - 切换当场生效（R-LANG-03）：除设置首选语言外，把语言 id 写进
 *   AppStorage `appLanguage`（整体替换）——**含用户可见文字的页面都挂
 *   `@StorageProp('appLanguage')`**，key 一变整页重渲染，`$r` 按新语言解析。
 *   不重建导航栈、不重启。
 * - 日期、数字格式跟 App 语言不跟系统（R-LANG-08）：见 AppDateFormatters
 */
import { preferences } from '@kit.ArkData';
import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { resolveInitialLanguage } from './LocaleParsing';

/** AppStorage key：当前 App 语言 id */
export const STORAGE_KEY_APP_LANGUAGE = 'appLanguage';
/** AppStorage key：LanguageManager 实例（1.6 接 AppEnvironment @Provide 后移除） */
export const STORAGE_KEY_LANGUAGE_MANAGER = 'languageManager';

/** 语言选项。显示名永远用自称（英语永远显示 English），不随界面语言翻译 */
export class LanguageOption {
  readonly id: string;
  /** 自称资源（app.string.lang_name_*，手工条目，值取自 iOS LanguageManager.swift） */
  readonly nameResource: Resource;

  constructor(id: string, nameResource: Resource) {
    this.id = id;
    this.nameResource = nameResource;
  }
}

export class LanguageManager {
  static readonly PREFS_NAME = 'memoir_prefs'; // 与 ThemeManager 同一个偏好文件
  static readonly PREF_KEY = 'appLanguage';

  /** 七种语言 id，顺序固定（R-LANG-01）。纯数据，纯逻辑单测用 */
  static readonly SUPPORTED_IDS: string[] = ['zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'fr', 'es'];

  private static cachedOptions: LanguageOption[] | undefined = undefined;

  /**
   * 七种语言选项（含自称资源）。惰性构造：`$r` 只在首次调用（UI 侧）时解析，
   * 类加载不碰资源 —— local 纯逻辑单测 import 本类安全。
   */
  static supportedOptions(): LanguageOption[] {
    if (LanguageManager.cachedOptions === undefined) {
      LanguageManager.cachedOptions = [
        new LanguageOption('zh-Hans', $r('app.string.lang_name_zh_hans')),
        new LanguageOption('zh-Hant', $r('app.string.lang_name_zh_hant')),
        new LanguageOption('en', $r('app.string.lang_name_en')),
        new LanguageOption('ja', $r('app.string.lang_name_ja')),
        new LanguageOption('ko', $r('app.string.lang_name_ko')),
        new LanguageOption('fr', $r('app.string.lang_name_fr')),
        new LanguageOption('es', $r('app.string.lang_name_es'))
      ];
    }
    return LanguageManager.cachedOptions;
  }

  private readonly prefs: preferences.Preferences;

  currentLanguage: string = 'en';

  private constructor(prefs: preferences.Preferences) {
    this.prefs = prefs;
  }

  /**
   * 创建并完成初始化：读偏好 → 空则按系统语言解析（R-LANG-02）并**立刻落盘**
   * → 设 App 级首选语言 → 写 AppStorage。在 EntryAbility 里 loadContent 前 await。
   */
  static async create(appContext: Context): Promise<LanguageManager> {
    let prefs: preferences.Preferences;
    try {
      prefs = await preferences.getPreferences(appContext, LanguageManager.PREFS_NAME);
    } catch (err) {
      // 偏好打不开：抛给调用方（EntryAbility 已 catch，启动不拦，资源按系统语言回退）
      hilog.error(0x0000, 'LanguageManager', 'getPreferences failed: %{public}s', JSON.stringify(err));
      throw new Error('LanguageManager.getPreferences failed');
    }
    const mgr = new LanguageManager(prefs);
    let raw: preferences.ValueType = '';
    try {
      raw = prefs.getSync(LanguageManager.PREF_KEY, '');
    } catch (err) {
      // 读失败当没存过：走 R-LANG-02 首启解析
      hilog.error(0x0000, 'LanguageManager', 'read appLanguage failed: %{public}s', JSON.stringify(err));
    }
    const stored = typeof raw === 'string' ? raw : '';
    // 存的值必须归一后在名单里；不在（脏数据 / 未来下架的语言）当没存过重新解析
    const storedCanonical = LanguageManager.canonicalLanguageId(stored);
    const resolved = storedCanonical !== undefined
      ? storedCanonical
      : LanguageManager.resolveFromSystem();
    if (resolved !== stored) {
      try {
        prefs.putSync(LanguageManager.PREF_KEY, resolved);
        prefs.flush();
      } catch (err) {
        hilog.error(0x0000, 'LanguageManager', 'Failed to persist language: %{public}s', JSON.stringify(err));
      }
    }
    mgr.currentLanguage = resolved;
    mgr.applyPreferredLanguage(resolved);
    AppStorage.setOrCreate(STORAGE_KEY_APP_LANGUAGE, resolved);
    AppStorage.setOrCreate(STORAGE_KEY_LANGUAGE_MANAGER, mgr);
    return mgr;
  }

  /** 首启解析：系统偏好语言列表里找第一个受支持的（解析逻辑在 LocaleParsing，单测覆盖） */
  private static resolveFromSystem(): string {
    return resolveInitialLanguage(i18n.System.getPreferredLanguageList(), LanguageManager.SUPPORTED_IDS);
  }

  /** id 归一成名单里的规范写法；不在名单返回 undefined（大小写不敏感，防脏值） */
  static canonicalLanguageId(id: string): string | undefined {
    const normalized = id.toLowerCase();
    return LanguageManager.SUPPORTED_IDS.find((supported: string): boolean => supported.toLowerCase() === normalized);
  }

  /** id 是否在七种名单里 */
  static isSupported(id: string): boolean {
    return LanguageManager.canonicalLanguageId(id) !== undefined;
  }

  /** 切换语言：校验归一 → 落盘 → 设首选语言 → 替换 AppStorage（触发刷新）。当场生效（R-LANG-03） */
  setLanguage(id: string): void {
    const canonical = LanguageManager.canonicalLanguageId(id);
    if (canonical === undefined) {
      hilog.error(0x0000, 'LanguageManager', 'setLanguage ignored, unsupported id: %{public}s', id);
      return;
    }
    if (canonical === this.currentLanguage) {
      return;
    }
    this.currentLanguage = canonical;
    try {
      this.prefs.putSync(LanguageManager.PREF_KEY, canonical);
      this.prefs.flush();
    } catch (err) {
      hilog.error(0x0000, 'LanguageManager', 'Failed to persist language: %{public}s', JSON.stringify(err));
    }
    this.applyPreferredLanguage(canonical);
    AppStorage.setOrCreate(STORAGE_KEY_APP_LANGUAGE, canonical);
  }

  /** 设 App 级首选语言，`$r` 按它解析（R-LANG-08 的资源侧） */
  private applyPreferredLanguage(id: string): void {
    try {
      i18n.System.setAppPreferredLanguage(id);
    } catch (err) {
      hilog.error(0x0000, 'LanguageManager', 'setAppPreferredLanguage failed: %{public}s', JSON.stringify(err));
    }
  }
}
