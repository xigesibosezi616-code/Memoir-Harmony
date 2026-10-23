import { AbilityConstant, UIAbility, Want, wantConstant } from '@kit.AbilityKit';
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
import { AppEnvironment, STORAGE_KEY_APP_ENVIRONMENT } from '../environment/AppEnvironment';
import { createDefaultErrorPresenter } from '../environment/ErrorPresenter';
import { ImmersiveChrome } from '../services/ImmersiveChrome';
import { DraftRepository } from '../data/DraftRepository';
import { AppDatabase } from '../data/Database';
import {
  WANT_PARAM_DRAFT,
  STORAGE_KEY_LIVE_DRAFT_JSON,
  STORAGE_KEY_CONTINUED_DRAFT_JSON,
  STORAGE_KEY_CONTINUE_TO_COMPOSE_TICK,
  continuationPayloadFits,
  encodeDraftForContinuation
} from '../services/AppContinuation';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  /** 应用级依赖容器（onWindowStageCreate 创建；onForeground 回前台时取用） */
  private environment: AppEnvironment | null = null;
  /** 内容加载防重入：Create / Restore 互斥触发，标志兜底防重复 loadContent 重置页面栈 */
  private contentLoaded: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    this.stashContinuedDraftIfAny(want, launchParam);
  }

  /**
   * 应用接续（源端）：系统把应用拖到另一台设备时回调。优先取 ComposeView
   * 防抖发布的实时快照（编辑器里还没落库的字也在），没有再退回库里的草稿；
   * 都没有就带空包 AGREE（对端打开首页，与 iOS 无此能力相比已是增量）。
   * 负载超官方 100KB 约束 REJECT——不静默截断，用户会误以为接续成功。
   */
  async onContinue(wantParam: Record<string, Object>): Promise<AbilityConstant.OnContinueResult> {
    try {
      // 不迁移系统 router 页面栈：接续恢复走 HomeView 消费链（stash → 落库 →
      // push Compose），系统栈直落 Compose 会读到还没落库的旧本地草稿；且文档
      // 明说自动栈恢复仅支持 router、不支持我们用的 Navigation（bpta-continue-cast）
      wantParam[wantConstant.Params.SUPPORT_CONTINUE_PAGE_STACK_KEY] = false;
      let payload: string = AppStorage.get<string>(STORAGE_KEY_LIVE_DRAFT_JSON) ?? '';
      if (payload.length === 0) {
        const store = await AppDatabase.open(this.context);
        const draft = await DraftRepository.loadCurrentDraft(store);
        if (draft !== null) {
          payload = encodeDraftForContinuation(draft);
        }
      }
      if (payload.length > 0) {
        if (!continuationPayloadFits(payload)) {
          hilog.warn(DOMAIN, TAG, 'continue payload over 100KB limit, rejected');
          return AbilityConstant.OnContinueResult.REJECT;
        }
        wantParam[WANT_PARAM_DRAFT] = payload;
      }
      return AbilityConstant.OnContinueResult.AGREE;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'onContinue failed: %{public}s', JSON.stringify(err));
      return AbilityConstant.OnContinueResult.REJECT;
    }
  }

  /**
   * 应用接续（对端）：LaunchReason.CONTINUATION 时把接续草稿 JSON 暂存进
   * AppStorage 并 +1 信号。**不在这里写库**：冷启动时合规层（同意页 /
   * 引导）还没走完，库写入和路由都等首页就绪后由 HomeView 消费
   * （restoreContinuedDraftIfNeeded）。
   */
  private stashContinuedDraftIfAny(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) {
      return;
    }
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return;
    }
    const payload: Object | undefined = params[WANT_PARAM_DRAFT];
    if (typeof payload !== 'string' || payload.length === 0) {
      return;
    }
    AppStorage.setOrCreate(STORAGE_KEY_CONTINUED_DRAFT_JSON, payload);
    AppStorage.setOrCreate(STORAGE_KEY_CONTINUE_TO_COMPOSE_TICK,
      (AppStorage.get<number>(STORAGE_KEY_CONTINUE_TO_COMPOSE_TICK) ?? 0) + 1);
    hilog.info(DOMAIN, TAG, 'continued draft stashed, waiting for home to restore');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onNewWant');
    this.stashContinuedDraftIfAny(want, launchParam);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    this.setupEnvironment(windowStage);
    this.initThenLoad(windowStage);
  }

  /**
   * 应用接续（对端）窗口还原：官方文档实锤——迁移启动（无论冷/热）只回调
   * onWindowStageRestore，**不回调 onWindowStageCreate**（bpta-continue-cast
   * 「对端恢复数据」；2026-10-23 80 Pro Max 白屏实测：onCreate → onWindowStageRestore
   * → onForeground，缺此实现 loadContent 永不执行 = 白屏）。必须把 Create 里
   * 做过的启动初始化在这里原样做一遍。contentLoaded 防重入：同一 UIAbility
   * 存续期内若两回调都被触发，只 loadContent 一次，避免重置页面栈。
   */
  onWindowStageRestore(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageRestore');
    if (this.contentLoaded) {
      hilog.warn(DOMAIN, TAG, 'content already loaded, skip re-load in restore');
      return;
    }
    this.setupEnvironment(windowStage);
    this.initThenLoad(windowStage);
  }

  /**
   * 应用级依赖容器装配（10_BUILD_MANUAL.md 1.6），**必须同步**完成再 loadContent：
   * - 沉浸式全屏：拿主窗口（getMainWindowSync 可抛，失败降级为非沉浸）包
   *   ImmersiveChrome。**setup 延后到 loadContent 之后**（见 initThenLoad）：
   *   loadContent 前调 setWindowLayoutFullScreen(true) 不生效，窗口保持
   *   裁剪态（页面从状态栏下 y122 起、getWindowAvoidArea 返回 0、
   *   NavDestination 标题栏按窗口顶布局被裁剩 53px——2026-10-16 真机定位）
   * - AppEnvironment：ErrorPresenter + chrome 同步创建存进 AppStorage，
   *   Index 取出 @Provide 下发——冷启动 onForeground 在 onWindowStageCreate 之后
   *   触发，先建好才不丢回前台事件
   */
  private setupEnvironment(windowStage: window.WindowStage): void {
    let chrome: ImmersiveChrome | undefined = undefined;
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      chrome = new ImmersiveChrome(mainWindow);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'getMainWindowSync failed, immersive degraded: %{public}s', JSON.stringify(err));
    }
    const env = new AppEnvironment(createDefaultErrorPresenter(), chrome);
    this.environment = env;
    AppStorage.setOrCreate(STORAGE_KEY_APP_ENVIRONMENT, env);
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
    if (this.contentLoaded) {
      return;
    }
    this.contentLoaded = true;
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
      // 沉浸式全屏必须在 loadContent 之后设置：提前设置不生效（窗口裁剪、
      // 避让区全 0），页面所有 safeAreaTopVp/BottomVp 让位全部失真
      const env = this.environment;
      if (env !== null && env.chrome !== undefined) {
        env.chrome.setup().catch((err: Object): void => {
          hilog.error(DOMAIN, TAG, 'chrome setup failed: %{public}s', JSON.stringify(err));
        });
      }
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
    // 回前台钩子（10_BUILD_MANUAL.md 1.6）：后续挂通知重排 / 寄信队列等
    const env = this.environment;
    if (env !== null) {
      env.onAppForeground();
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
