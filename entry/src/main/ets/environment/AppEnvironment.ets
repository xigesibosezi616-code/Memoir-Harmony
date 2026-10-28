/**
 * 应用级依赖容器（10_BUILD_MANUAL.md 1.6）。对应 iOS `Environment/AppEnvironment.swift`。
 *
 * 注入方式：EntryAbility 同步创建（冷启动时 `onForeground` 在 `onWindowStageCreate`
 * 之后才触发，先建好才不丢回前台事件）→ 存 AppStorage → Index 读出后 `@Provide`
 * 下发，View 端 `@Consume` 读取（CLAUDE.md：依赖容器只此一个，不另立全局单例）。
 *
 * 本卡（1.6）只落 `errors`、`chrome` 与回前台钩子注册表；`http` / `session` / `ai`
 * 等服务到位后在各自卡片（4.1/4.2/5.x）加字段，不预建空槽。
 */
import { ErrorPresenter } from './ErrorPresenter';
import { ImmersiveChrome } from '../services/ImmersiveChrome';
import { UserSession } from '../services/auth/UserSession';
import { AuthService } from '../services/auth/AuthService';
import { LetterOutboxService } from '../services/LetterOutboxService';
import { LetterNotifications } from '../services/LetterNotifications';

/** AppStorage key：AppEnvironment 实例（EntryAbility 创建，Index 取出 @Provide） */
export const STORAGE_KEY_APP_ENVIRONMENT = 'appEnvironment';

export class AppEnvironment {
  readonly errors: ErrorPresenter;

  /** 沉浸式全屏控制器（Index 观察主题变化时驱动系统栏配色；拿不到主窗口时缺省） */
  readonly chrome?: ImmersiveChrome;

  /** 登录会话（token + 用户快照；4.2 手机号登录） */
  readonly session?: UserSession;

  /** 认证接口客户端（发码 / 验码 / /me；4.2） */
  readonly auth?: AuthService;

  /** 寄信队列（5.3：投信 / 重试 / 补领 / 退回） */
  readonly outbox?: LetterOutboxService;

  /** 到达通知（5.4：定时提醒预约 / 授权申请 / 点通知路由信号） */
  readonly notifications?: LetterNotifications;

  private readonly foregroundHooks: Array<() => void> = [];

  constructor(errors: ErrorPresenter, chrome?: ImmersiveChrome,
    session?: UserSession, auth?: AuthService, outbox?: LetterOutboxService,
    notifications?: LetterNotifications) {
    this.errors = errors;
    this.chrome = chrome;
    this.session = session;
    this.auth = auth;
    this.outbox = outbox;
    this.notifications = notifications;
  }

  /** 注册回到前台钩子（后续挂通知重排、寄信队列、同名合并等） */
  registerForegroundHook(hook: () => void): void {
    this.foregroundHooks.push(hook);
  }

  /** 依次执行已注册的前台钩子（EntryAbility.onForeground 调） */
  onAppForeground(): void {
    for (const hook of this.foregroundHooks) {
      hook();
    }
  }
}
