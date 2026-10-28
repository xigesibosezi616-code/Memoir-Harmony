/**
 * 到达通知服务（10_BUILD_MANUAL.md 5.4；R-NOTIFY-01~05）。
 * 对应 iOS `Services/LetterNotifications.swift`。
 *
 * - 定时提醒走 **后台代理提醒**（reminderAgentManager，R-NOTIFY-01）：
 *   不用服务器推送，App 被冻结 / 退出后由系统代管按时弹 ReminderRequestTimer
 * - 同一封信同一 notificationId **覆盖**不重复（R-NOTIFY-04）；
 *   号码表 letterId → notificationId 存 AppPrefs（NotifyLogic 纯逻辑编解码）
 * - 文案在预约那一刻取当前 App 语言快照进提醒（R-NOTIFY-03，
 *   iOS UNMutableNotificationContent 同款；之后换语言已排的不跟着换）
 * - 点通知回 App：wantAgent 带 openLetterbox 标记（API 12+ parameters），
 *   EntryAbility onCreate / onNewWant 读到后发 tick，主框架切邮筒 tab 进信箱
 *   （R-NOTIFY-05；iOS openLetterboxRequested 同款链路）
 * - 🔴 预约失败（无代理提醒权益 / 未开通知 / 超数量）只打日志降级，不炸信流
 */
import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Letter } from '../models/Letter';
import { LetterDelivery } from '../models/LetterDelivery';
import {
  ArrivalReminder,
  ArrivalPublish,
  decodeArrivalNotifyRegistry,
  encodeArrivalNotifyRegistry,
  planArrivalReschedule
} from '../models/NotifyLogic';
import { AppPrefs } from './AppPrefs';

const DOMAIN = 0x0000;
const TAG = 'LetterNotifications';

/** 本机通知号码表偏好键（letterId → notificationId，R-NOTIFY-04 覆盖用） */
export const PREF_KEY_ARRIVAL_NOTIFY_REGISTRY = 'letterArrivalNotifyRegistry.v1';

/** 点通知带回的 want 参数标记（wantAgent.parameters 键，API 12+） */
export const WANT_PARAM_OPEN_LETTERBOX = 'openLetterbox';

/** AppStorage key：EntryAbility 读到 openLetterbox want 后 +1，主框架切邮筒 tab */
export const STORAGE_KEY_OPEN_LETTERBOX_TICK = 'openLetterboxTick';

/** AppStorage key：主框架已切到邮筒 tab 后 +1，邮筒页 push 信箱（两级路由解耦） */
export const STORAGE_KEY_POSTBOX_OPEN_LETTERBOX_TICK = 'postboxOpenLetterboxTick';

export class LetterNotifications {
  private readonly context: common.UIAbilityContext;
  /** wantAgent 跳转目标（EntryAbility 注入，点通知回 App 用） */
  private readonly bundleName: string;
  private readonly abilityName: string;

  constructor(context: common.UIAbilityContext,
    bundleName: string, abilityName: string) {
    this.context = context;
    this.bundleName = bundleName;
    this.abilityName = abilityName;
  }

  /** 通知开关已开？ */
  async isAuthorized(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'isNotificationEnabled failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * R-NOTIFY-02：申请通知授权。第一次寄信成功后调（PostBoxTabView.post），
   * 已授权直接过；没问过弹系统授权窗；用户拒过不反复骚扰（系统窗只弹一次，
   * 之后 requestEnableNotification 静默失败 → 返回 false，设置页可再开）。
   */
  async requestAuthorizationIfNeeded(): Promise<boolean> {
    try {
      if (await notificationManager.isNotificationEnabled()) {
        return true;
      }
      await notificationManager.requestEnableNotification(this.context);
      return await notificationManager.isNotificationEnabled();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'requestEnableNotification failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 预约单封到达提醒（iOS notifyArrival 同款）。
   * - onlyIfAhead：补领新建的信为 true——到达时刻已过就不排（免得一打开
   *   App 弹一堆过期通知）；寄成功 / 补领认领为 false——哪怕已过也排，
   *   1 秒内弹，用户锁屏等得到（R-NOTIFY-05 验收路径）
   * - 未授权不排（🔴 先确认已授权再预约，R-NOTIFY-02）
   */
  async notifyArrival(letter: Letter, onlyIfAhead: boolean): Promise<void> {
    const arrivesAtMs = LetterDelivery.arrivalOf(letter);
    if (onlyIfAhead && arrivesAtMs <= Date.now()) {
      hilog.info(DOMAIN, TAG, 'skip reminder (arrival passed, onlyIfAhead) id=%{public}s', letter.id);
      return;
    }
    if (!(await this.isAuthorized())) {
      hilog.info(DOMAIN, TAG, 'skip reminder (not authorized) id=%{public}s', letter.id);
      return;
    }
    await this.publish(letter.id, arrivesAtMs, letter.fromCharacter);
  }

  /**
   * R-NOTIFY-04：全量重排（回前台 / 到达时刻变化后调，iOS rescheduleInTransit
   * 同款口径）。同信复用同 notificationId 覆盖，不在途的信不处理（一次性提醒
   * 系统自然过期）。空计划（没有在途信）不碰系统。
   */
  async rescheduleInTransit(reminders: ArrivalReminder[]): Promise<void> {
    if (reminders.length === 0) {
      return;
    }
    if (!(await this.isAuthorized())) {
      hilog.info(DOMAIN, TAG, 'skip reschedule: %{public}s',
        'notifications not authorized');
      return;
    }
    const registry = decodeArrivalNotifyRegistry(
      AppPrefs.getString(PREF_KEY_ARRIVAL_NOTIFY_REGISTRY, ''));
    const plan = planArrivalReschedule(registry, reminders, Date.now());
    AppPrefs.putString(PREF_KEY_ARRIVAL_NOTIFY_REGISTRY,
      encodeArrivalNotifyRegistry(plan.nextRegistry));
    hilog.info(DOMAIN, TAG, 'rescheduling %{public}d arrival reminders', plan.toPublish.length);
    for (const item of plan.toPublish) {
      await this.publishPlan(item);
    }
  }

  // ---- 内部 ----

  /** 单封预约（notifyArrival 直排：沿用既有号，没有就取新号） */
  private async publish(letterId: string, arrivesAtMs: number, penPalName: string): Promise<void> {
    const registry = decodeArrivalNotifyRegistry(
      AppPrefs.getString(PREF_KEY_ARRIVAL_NOTIFY_REGISTRY, ''));
    const reminders = [new ArrivalReminder(letterId, arrivesAtMs, penPalName)];
    const plan = planArrivalReschedule(registry, reminders, Date.now());
    AppPrefs.putString(PREF_KEY_ARRIVAL_NOTIFY_REGISTRY,
      encodeArrivalNotifyRegistry(plan.nextRegistry));
    await this.publishPlan(plan.toPublish[0]);
  }

  /** 真正发代理提醒；失败只打日志（无权益 / 超数量 / 系统拒绝都不炸信流） */
  private async publishPlan(item: ArrivalPublish): Promise<void> {
    // 文案在预约那一刻按当前 App 语言取快照（R-NOTIFY-03；$r 须字面量）
    const title: string = this.context.resourceManager
      .getStringSync($r('app.string.s_25fbc95421').id);
    const body: string = this.context.resourceManager
      .getStringSync($r('app.string.s_b4f504af2c').id, item.penPalName);
    const wantParams: Record<string, Object> = { 'openLetterbox': true };
    const request: reminderAgentManager.ReminderRequestTimer = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
      title: title,
      content: body,
      notificationId: item.notifyId,
      triggerTimeInSeconds: item.triggerInSeconds,
      wantAgent: {
        pkgName: this.bundleName,
        abilityName: this.abilityName,
        parameters: wantParams
      },
      slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
    };
    try {
      await reminderAgentManager.publishReminder(request);
      hilog.info(DOMAIN, TAG, 'arrival reminder published letter=%{public}s notifyId=%{public}d',
        item.letterId, item.notifyId);
    } catch (err) {
      // 真机无「代理提醒」权益（AGC 申请记 12_KNOWN_ISSUES 前置项）/ 超数量限制：
      // 降级为没有通知，信流本身不受影响
      hilog.warn(DOMAIN, TAG, 'publishReminder failed letter=%{public}s: %{public}s',
        item.letterId, JSON.stringify(err));
    }
  }
}
