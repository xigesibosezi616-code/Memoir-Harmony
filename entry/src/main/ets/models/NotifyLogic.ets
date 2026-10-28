/**
 * 到达通知纯逻辑（10_BUILD_MANUAL.md 5.4；R-NOTIFY-01~05）。
 * 对应 iOS `Services/LetterNotifications.swift` 的计划部分。
 *
 * - 只挑「在路上」的信（isInTransit，写信中的还没回信不排）；
 *   提醒是值快照（iOS LetterNotifications.InTransit 同款：letterId /
 *   到达时刻 / 笔友名，模型不跨并发边界）
 * - 本机注册表 letterId → notificationId 存 AppPrefs（`letterArrivalNotifyRegistry.v1`）：
 *   同一封信复用同一 notificationId，代理提醒按 id **覆盖**不重复（R-NOTIFY-04）
 * - 全量重排计划：每封在途信一次发布，触发秒数 max(1, ceil(距离到达的毫秒 / 1000))
 *   ——已过到达时刻的也排（1 秒内弹），对应寄成功/补领时 onlyIfAhead=false 语义；
 *   只加不减（iOS rescheduleInTransit 同款）：不在途的信不处理，一次性提醒自然过期
 */
import { Letter } from './Letter';
import { LetterDelivery } from './LetterDelivery';

/** 一封在途信的提醒快照（值对象） */
export class ArrivalReminder {
  readonly letterId: string;
  /** 到达时刻（毫秒） */
  readonly triggerAtMs: number;
  /** 笔友名快照（通知文案用，预约那一刻的取值） */
  readonly penPalName: string;

  constructor(letterId: string, triggerAtMs: number, penPalName: string) {
    this.letterId = letterId;
    this.triggerAtMs = triggerAtMs;
    this.penPalName = penPalName;
  }
}

/** 在途信 → 提醒快照数组（iOS rescheduleInTransit 的 InTransit 口径：只 isInTransit） */
export function arrivalRemindersOf(letters: Letter[], nowMs: number): ArrivalReminder[] {
  const reminders: ArrivalReminder[] = [];
  for (const letter of letters) {
    if (LetterDelivery.isInTransit(letter, nowMs)) {
      reminders.push(new ArrivalReminder(letter.id,
        LetterDelivery.arrivalOf(letter), letter.fromCharacter));
    }
  }
  return reminders;
}

/**
 * 本机通知注册表：letterId → notificationId + 下一号计数器。
 * 坏输入（空串 / 坏 JSON / 结构不符）一律回空表，不让通知拖垮信流。
 */
export class ArrivalNotifyRegistry {
  /** 下一个可分配的 notificationId（从 1 起，0 保留给系统） */
  nextNotifyId: number;
  readonly notifyIds: Map<string, number>;

  constructor(nextNotifyId: number, notifyIds: Map<string, number>) {
    this.nextNotifyId = nextNotifyId;
    this.notifyIds = notifyIds;
  }

  static empty(): ArrivalNotifyRegistry {
    return new ArrivalNotifyRegistry(1, new Map<string, number>());
  }
}

/** 注册表偏好 JSON 的原始形状（只做一次性转换，字段不认识的忽略） */
interface RegistryRaw {
  v?: number;
  next?: number;
  ids?: Record<string, number>;
}

export function decodeArrivalNotifyRegistry(raw: string): ArrivalNotifyRegistry {
  if (raw.length === 0) {
    return ArrivalNotifyRegistry.empty();
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (err) {
    return ArrivalNotifyRegistry.empty();
  }
  const rawRegistry = parsed as RegistryRaw;
  if (typeof rawRegistry.next !== 'number' || rawRegistry.next < 1) {
    return ArrivalNotifyRegistry.empty();
  }
  const ids = new Map<string, number>();
  const rawIds = rawRegistry.ids;
  if (rawIds !== undefined && rawIds !== null) {
    const keys = Object.keys(rawIds);
    for (const key of keys) {
      const value = rawIds[key];
      if (typeof value === 'number' && Number.isFinite(value) && value >= 0) {
        ids.set(key, value);
      }
    }
  }
  return new ArrivalNotifyRegistry(Math.floor(rawRegistry.next), ids);
}

export function encodeArrivalNotifyRegistry(registry: ArrivalNotifyRegistry): string {
  const ids: Record<string, number> = {};
  registry.notifyIds.forEach((notifyId: number, letterId: string): void => {
    ids[letterId] = notifyId;
  });
  return JSON.stringify({
    v: 1,
    next: registry.nextNotifyId,
    ids: ids
  } as RegistryRaw);
}

/** 单封到达提醒的发布计划 */
export class ArrivalPublish {
  readonly letterId: string;
  /** 代理提醒 notificationId（同信复用同 id = 覆盖，R-NOTIFY-04） */
  readonly notifyId: number;
  /** 距触发还有多少秒（至少 1） */
  readonly triggerInSeconds: number;
  readonly penPalName: string;

  constructor(letterId: string, notifyId: number, triggerInSeconds: number, penPalName: string) {
    this.letterId = letterId;
    this.notifyId = notifyId;
    this.triggerInSeconds = triggerInSeconds;
    this.penPalName = penPalName;
  }
}

/** 全量重排计划（R-NOTIFY-04：回前台 / 收信变化后整体覆盖一遍） */
export class ArrivalReschedulePlan {
  readonly toPublish: ArrivalPublish[];
  /** 重排后的注册表（调用方发布后持久化） */
  readonly nextRegistry: ArrivalNotifyRegistry;

  constructor(toPublish: ArrivalPublish[], nextRegistry: ArrivalNotifyRegistry) {
    this.toPublish = toPublish;
    this.nextRegistry = nextRegistry;
  }
}

/**
 * 全量重排计划：每封在途信一次代理提醒发布。
 * - 已在注册表的信复用原 notificationId（覆盖语义）；新信从计数器取号
 * - 触发秒数 max(1, ceil((triggerAtMs - nowMs) / 1000))：已过到达时刻 → 1 秒内弹
 * - 注册表只加不减：不在途的信留着旧号（避免号复用串台），过期提醒系统自然清
 */
export function planArrivalReschedule(registry: ArrivalNotifyRegistry,
  reminders: ArrivalReminder[], nowMs: number): ArrivalReschedulePlan {
  const notifyIds = new Map<string, number>();
  for (const entry of registry.notifyIds) {
    notifyIds.set(entry[0], entry[1]);
  }
  let nextNotifyId = Math.max(registry.nextNotifyId, 1);
  const toPublish: ArrivalPublish[] = [];
  for (const reminder of reminders) {
    let notifyId = notifyIds.get(reminder.letterId);
    if (notifyId === undefined) {
      notifyId = nextNotifyId;
      nextNotifyId += 1;
    }
    notifyIds.set(reminder.letterId, notifyId);
    const deltaMs = reminder.triggerAtMs - nowMs;
    const seconds = Math.max(1, Math.ceil(deltaMs / 1000));
    toPublish.push(new ArrivalPublish(reminder.letterId, notifyId, seconds, reminder.penPalName));
  }
  return new ArrivalReschedulePlan(toPublish,
    new ArrivalNotifyRegistry(nextNotifyId, notifyIds));
}
