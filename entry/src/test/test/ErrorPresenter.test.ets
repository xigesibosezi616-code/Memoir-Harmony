/**
 * ErrorPresenter 单测（10_BUILD_MANUAL.md 1.6）。
 * 对应 iOS `ErrorPresenterTests.swift`：假调度器控制时间，验证
 * 发布序列 / 自动消失 / 重复 present 取消前一个 / presentError 语义。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  ErrorPresenter,
  ToastData,
  LocalizedError,
  ErrorToastKind
} from '../../main/ets/environment/ErrorPresenter';

/** 假调度任务 */
class ScheduledTask {
  readonly id: number;
  readonly fireAtMs: number;
  readonly action: () => void;
  cancelled: boolean = false;

  constructor(id: number, fireAtMs: number, action: () => void) {
    this.id = id;
    this.fireAtMs = fireAtMs;
    this.action = action;
  }
}

/** 假调度器：advance 推进虚拟时间，按到期顺序执行任务 */
class FakeScheduler {
  nowMs: number = 0;
  private nextId: number = 1;
  private readonly tasks: ScheduledTask[] = [];

  schedule(delayMs: number, action: () => void): number {
    const task = new ScheduledTask(this.nextId, this.nowMs + delayMs, action);
    this.nextId += 1;
    this.tasks.push(task);
    return task.id;
  }

  cancel(id: number): void {
    const task = this.findById(id);
    if (task !== undefined) {
      task.cancelled = true;
    }
  }

  advance(ms: number): void {
    const targetMs: number = this.nowMs + ms;
    for (;;) {
      let due: ScheduledTask | undefined = undefined;
      for (const task of this.tasks) {
        if (!task.cancelled && task.fireAtMs <= targetMs
          && (due === undefined || task.fireAtMs < due.fireAtMs)) {
          due = task;
        }
      }
      if (due === undefined) {
        break;
      }
      due.cancelled = true;
      this.nowMs = due.fireAtMs;
      due.action();
    }
    this.nowMs = targetMs;
  }

  pendingCount(): number {
    let count = 0;
    for (const task of this.tasks) {
      if (!task.cancelled) {
        count += 1;
      }
    }
    return count;
  }

  private findById(id: number): ScheduledTask | undefined {
    for (const task of this.tasks) {
      if (task.id === id) {
        return task;
      }
    }
    return undefined;
  }
}

function lastPublished(published: Array<ToastData | null>): ToastData | null {
  return published.length > 0 ? published[published.length - 1] : null;
}

export default function errorPresenterTest() {
  describe('ErrorPresenterTest', () => {
    it('presentPublishesToastAndAutoDismisses', 0, () => {
      const scheduler = new FakeScheduler();
      const published: Array<ToastData | null> = [];
      const presenter = new ErrorPresenter(
        (toast: ToastData | null): void => { published.push(toast); },
        (delayMs: number, action: () => void): number => scheduler.schedule(delayMs, action),
        (taskId: number): void => scheduler.cancel(taskId)
      );

      presenter.present('hello', ErrorToastKind.Info, 3000);
      expect(published.length).assertEqual(1);
      const toast = lastPublished(published);
      expect(toast !== null).assertTrue();
      if (toast !== null) {
        expect(toast.message).assertEqual('hello');
        expect(toast.kind).assertEqual(ErrorToastKind.Info);
      }
      expect(scheduler.pendingCount()).assertEqual(1);

      // 差一毫秒不消失，到点消失
      scheduler.advance(2999);
      expect(lastPublished(published) !== null).assertTrue();
      scheduler.advance(1);
      expect(lastPublished(published) === null).assertTrue();
      expect(scheduler.pendingCount()).assertEqual(0);
    })

    it('secondPresentCancelsFirstDismiss', 0, () => {
      const scheduler = new FakeScheduler();
      const published: Array<ToastData | null> = [];
      const presenter = new ErrorPresenter(
        (toast: ToastData | null): void => { published.push(toast); },
        (delayMs: number, action: () => void): number => scheduler.schedule(delayMs, action),
        (taskId: number): void => scheduler.cancel(taskId)
      );

      presenter.present('first', ErrorToastKind.Error, 3000);
      scheduler.advance(1000);
      presenter.present('second', ErrorToastKind.Error, 5000);

      // 第一条的自动消失已被取消，只挂着一个新任务
      expect(scheduler.pendingCount()).assertEqual(1);
      const second = lastPublished(published);
      expect(second !== null).assertTrue();
      if (second !== null) {
        expect(second.message).assertEqual('second');
      }

      // 虚拟时间走满 3000+5000：旧任务即便没被取消也早过期，但只有新任务会发布 null
      scheduler.advance(6000);
      expect(lastPublished(published) === null).assertTrue();
      expect(scheduler.pendingCount()).assertEqual(0);
    })

    it('dismissCancelsScheduledTask', 0, () => {
      const scheduler = new FakeScheduler();
      const published: Array<ToastData | null> = [];
      const presenter = new ErrorPresenter(
        (toast: ToastData | null): void => { published.push(toast); },
        (delayMs: number, action: () => void): number => scheduler.schedule(delayMs, action),
        (taskId: number): void => scheduler.cancel(taskId)
      );

      presenter.present('gone', ErrorToastKind.Success, 3000);
      presenter.dismiss();
      expect(lastPublished(published) === null).assertTrue();
      expect(scheduler.pendingCount()).assertEqual(0);

      // 到点后不再重复发布（任务已取消）
      scheduler.advance(3000);
      expect(lastPublished(published) === null).assertTrue();
    })

    it('presentErrorPrefersLocalizedErrorUserMessage', 0, () => {
      const scheduler = new FakeScheduler();
      const published: Array<ToastData | null> = [];
      const presenter = new ErrorPresenter(
        (toast: ToastData | null): void => { published.push(toast); },
        (delayMs: number, action: () => void): number => scheduler.schedule(delayMs, action),
        (taskId: number): void => scheduler.cancel(taskId)
      );

      presenter.presentError(new LocalizedError('已同步到本机'), '出错了，请稍后再试', 4000);
      const toast = lastPublished(published);
      expect(toast !== null).assertTrue();
      if (toast !== null) {
        expect(toast.message).assertEqual('已同步到本机');
        expect(toast.kind).assertEqual(ErrorToastKind.Error);
      }
      expect(scheduler.pendingCount()).assertEqual(1);
    })

    it('presentErrorFallsBackForPlainError', 0, () => {
      const scheduler = new FakeScheduler();
      const published: Array<ToastData | null> = [];
      const presenter = new ErrorPresenter(
        (toast: ToastData | null): void => { published.push(toast); },
        (delayMs: number, action: () => void): number => scheduler.schedule(delayMs, action),
        (taskId: number): void => scheduler.cancel(taskId)
      );

      presenter.presentError(new Error('network stack detail'), '网络异常，请稍后再试');
      const toast = lastPublished(published);
      expect(toast !== null).assertTrue();
      if (toast !== null) {
        // 底层错误信息不透给用户，只展示本地化 fallback
        expect(toast.message).assertEqual('网络异常，请稍后再试');
      }
    })

    it('toastDataIdsIncrease', 0, () => {
      const first = new ToastData('a', ErrorToastKind.Info);
      const second = new ToastData('b', ErrorToastKind.Success);
      expect(second.id - first.id).assertEqual(1);
    })
  })
}
