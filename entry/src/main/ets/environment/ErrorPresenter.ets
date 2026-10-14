/**
 * 用户可见错误 / 提示的统一出口（10_BUILD_MANUAL.md 1.6）。
 * 对应 iOS `Environment/ErrorPresenter.swift`。
 *
 * **用法**：通过 `AppEnvironment.errors` 取用，调用 `present(...)` 触发 toast；
 * 顶层 overlay（`MainTabsView`）观察 `STORAGE_KEY_CURRENT_TOAST` 自动展示。
 *
 * **承接对象**：
 * - AI 服务网络失败、配额不足、内容过滤等
 * - 未来渐进替换现有 `try?` 静默吞错时，错误从这里冒出
 *
 * 发布与调度全部依赖注入：单测用假调度器控制时间（`ErrorPresenter.test.ets`），
 * 真机装配见 `createDefaultErrorPresenter`。
 */

/** AppStorage key：当前 toast（ToastData 实例整体替换驱动重渲染；null = 无提示） */
export const STORAGE_KEY_CURRENT_TOAST = 'currentToast';

/**
 * toast 种类（对应 iOS `ErrorPresenter.Kind`）。
 * 文档卡片只写了两种，以 iOS 源码三种为准（09_OPEN_QUESTIONS.md Q21）。
 */
export enum ErrorToastKind {
  /** 失败 / 异常（赭红） */
  Error = 0,
  /** 中性信息（墨灰蓝） */
  Info = 1,
  /** 成功确认（橄榄绿） */
  Success = 2
}

/** 一条 toast 的不可变数据（对应 iOS `ErrorPresenter.Toast`；Identifiable → 递增 id） */
export class ToastData {
  private static nextId: number = 0;

  readonly id: number;
  readonly message: string;
  readonly kind: ErrorToastKind;

  constructor(message: string, kind: ErrorToastKind) {
    this.id = ToastData.nextId;
    ToastData.nextId += 1;
    this.message = message;
    this.kind = kind;
  }
}

/** 已本地化的用户可读错误（对应 iOS `LocalizedError.errorDescription`） */
export class LocalizedError extends Error {
  readonly userMessage: string;

  constructor(userMessage: string) {
    super(userMessage);
    this.userMessage = userMessage;
  }
}

/** 用户可见提示的呈现器。应从 UI 动作 / 主线程调用（与 iOS 同款约束） */
export class ErrorPresenter {
  private readonly publish: (toast: ToastData | null) => void;
  private readonly schedule: (delayMs: number, action: () => void) => number;
  private readonly cancelScheduled: (taskId: number) => void;
  private dismissTaskId: number = -1;

  constructor(publish: (toast: ToastData | null) => void,
    schedule: (delayMs: number, action: () => void) => number,
    cancelScheduled: (taskId: number) => void) {
    this.publish = publish;
    this.schedule = schedule;
    this.cancelScheduled = cancelScheduled;
  }

  /** 展示一条提示，durationMs 后自动消失（iOS `present(_:kind:duration:)`，默认 3 秒） */
  present(message: string, kind: ErrorToastKind, durationMs: number = 3000): void {
    this.cancelDismiss();
    this.publish(new ToastData(message, kind));
    this.dismissTaskId = this.schedule(durationMs, (): void => {
      this.dismissTaskId = -1;
      this.publish(null);
    });
  }

  /**
   * 从 Error 展示：`LocalizedError` 优先 `userMessage`，其余用 fallback
   * （iOS `present(_:fallback:duration:)`，默认 4 秒）。
   * 参数用联合类型：ArkTS 里 `Error` 是接口，子类实例直接传 `Error` 参数会触发
   * 结构化类型检查（arkts-no-structural-typing），联合类型按名义匹配放行。
   */
  presentError(error: LocalizedError | Error, fallback: string, durationMs: number = 4000): void {
    const message: string = error instanceof LocalizedError ? error.userMessage : fallback;
    this.present(message, ErrorToastKind.Error, durationMs);
  }

  /** 立即关掉当前提示（点 toast / 切页面用），并取消未到期的自动消失 */
  dismiss(): void {
    this.cancelDismiss();
    this.publish(null);
  }

  private cancelDismiss(): void {
    if (this.dismissTaskId >= 0) {
      this.cancelScheduled(this.dismissTaskId);
      this.dismissTaskId = -1;
    }
  }
}

/** 真机装配：toast 发布进 AppStorage，setTimeout 调度（EntryAbility 建 AppEnvironment 时用） */
export function createDefaultErrorPresenter(): ErrorPresenter {
  return new ErrorPresenter(
    (toast: ToastData | null): void => {
      AppStorage.setOrCreate(STORAGE_KEY_CURRENT_TOAST, toast);
    },
    (delayMs: number, action: () => void): number => {
      return setTimeout(action, delayMs);
    },
    (taskId: number): void => {
      clearTimeout(taskId);
    }
  );
}
