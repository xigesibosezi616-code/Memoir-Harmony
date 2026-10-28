/**
 * 寄信队列的纯逻辑（10_BUILD_MANUAL.md 5.3；R-OUTBOX-01~11、R-POST-11）。
 * 对应 iOS `Services/LetterOutbox.swift` 的状态机部分（Item / 重试计时 / 补领匹配）。
 *
 * - 「哪些信归本机寄」记在本机偏好（letterOutbox.v1，JSON），**不进库、不进同步**
 *   （R-OUTBOX-01）；这里的 encode/decode 只管这层 JSON，偏好读写在 LetterOutboxService
 * - 重试计时（R-OUTBOX-04/05）：断网 / 超时 / 取消 / 传输故障**不算失败**，30 秒后再试；
 *   服务端出错 1 分钟、5 分钟后重试，连续 3 次退回
 * - 补领匹配（R-OUTBOX-07/09）：按正文去重，写信时刻 ≥ 本封寄出时刻 − 5 分钟的
 *   服务端信算它的回信；对不上的新落一封（到达时刻由调用方按服务端时间重算）
 * - 全部纯函数，毫秒与「此刻」由调用方注入，单测跑穿各种时间线
 */
import { Letter } from './Letter';
import { LetterDelivery } from './LetterDelivery';

/** 本机负责表里一封信的重试情况（iOS LetterOutbox.Item 同构） */
export class OutboxItem {
  /** 发出去过几次请求。>0 = 服务端可能已经写好，重发前先补领 */
  attempts: number;
  /** 服务端连续出错几次（断网 / 超时不算） */
  failures: number;
  /** 下次最早什么时候再试（毫秒）；undefined = 随时 */
  nextAttemptAt?: number;

  constructor(attempts: number, failures: number, nextAttemptAt?: number) {
    this.attempts = attempts;
    this.failures = failures;
    this.nextAttemptAt = nextAttemptAt;
  }
}

/** 本机负责表偏好的 JSON 原样形状（字段全可缺，逐字段 typeof 校验） */
interface OutboxItemRaw {
  attempts?: number;
  failures?: number;
  nextAttemptAt?: number;
}

/** 服务端连续出错几次就退回（R-OUTBOX-05「连续 3 次」） */
export const OUTBOX_MAX_FAILURES: number = 3;
/** 补领认「是这封的回信」容许的时钟误差（R-OUTBOX-07「− 5 分钟」；手机和服务器的钟不一定对得上） */
export const OUTBOX_CLOCK_SKEW_MS: number = 5 * 60 * 1000;
/** 断网 / 超时 / 取消 / 传输故障后再试间隔（R-OUTBOX-04「30 秒后再试」） */
export const OUTBOX_NETWORK_RETRY_MS: number = 30 * 1000;
/** 服务端出错第 1 次后的重试间隔（R-OUTBOX-05「1 分钟」） */
export const OUTBOX_FIRST_FAILURE_RETRY_MS: number = 60 * 1000;
/** 服务端出错第 2 次起的重试间隔（R-OUTBOX-05「5 分钟」） */
export const OUTBOX_LATER_FAILURE_RETRY_MS: number = 5 * 60 * 1000;

/** 本机负责表 → JSON（Preferences 只存字符串）。nextAttemptAt 缺省不发 */
export function encodeOutboxState(state: Map<string, OutboxItem>): string {
  const raw: Record<string, Object> = {};
  state.forEach((item: OutboxItem, id: string): void => {
    const o: Record<string, Object> = {
      'attempts': item.attempts,
      'failures': item.failures
    };
    if (item.nextAttemptAt !== undefined) {
      o['nextAttemptAt'] = item.nextAttemptAt;
    }
    raw[id] = o;
  });
  return JSON.stringify(raw);
}

/** JSON → 本机负责表。坏 JSON / 坏形状按空表处理（信还在库里，最多多试一次寄信） */
export function decodeOutboxState(raw: string): Map<string, OutboxItem> {
  const state = new Map<string, OutboxItem>();
  if (raw.length === 0) {
    return state;
  }
  try {
    const parsed = JSON.parse(raw) as Record<string, OutboxItemRaw>;
    if (parsed === null || typeof parsed !== 'object') {
      return state;
    }
    const keys = Object.keys(parsed);
    for (const id of keys) {
      const item = parsed[id];
      if (item === null || typeof item !== 'object') {
        continue;
      }
      const attempts = typeof item.attempts === 'number' ? item.attempts : 0;
      const failures = typeof item.failures === 'number' ? item.failures : 0;
      const next = typeof item.nextAttemptAt === 'number' ? item.nextAttemptAt : undefined;
      state.set(id, new OutboxItem(attempts, failures, next));
    }
  } catch (err) {
    // 坏 JSON 当空表：退信多弹一张卡也比把队列整个弄丢好
  }
  return state;
}

/** 这封到了该试的时候没有（nextAttemptAt 缺省 = 随时） */
export function isOutboxDue(item: OutboxItem, nowMs: number): boolean {
  return item.nextAttemptAt === undefined || item.nextAttemptAt <= nowMs;
}

/** 服务端出错第 failures 次后的重试间隔（R-OUTBOX-05：第 1 次 1 分钟，之后 5 分钟） */
export function failureRetryDelayMs(failures: number): number {
  return failures <= 1 ? OUTBOX_FIRST_FAILURE_RETRY_MS : OUTBOX_LATER_FAILURE_RETRY_MS;
}

/** 断网 / 超时 / 取消 / 传输故障（R-OUTBOX-04）：不算失败，30 秒后再试 */
export function itemAfterNetworkError(item: OutboxItem, nowMs: number): OutboxItem {
  return new OutboxItem(item.attempts, item.failures, nowMs + OUTBOX_NETWORK_RETRY_MS);
}

/** 服务端出错一次（R-OUTBOX-05）：failures + 1，下次 1 分钟 / 5 分钟后再试 */
export function itemAfterServerFailure(item: OutboxItem, nowMs: number): OutboxItem {
  const failures = item.failures + 1;
  return new OutboxItem(item.attempts, failures, nowMs + failureRetryDelayMs(failures));
}

/** 连续 3 次不成 → 退回（R-OUTBOX-05） */
export function shouldGiveBack(item: OutboxItem): boolean {
  return item.failures >= OUTBOX_MAX_FAILURES;
}

/** 重新寄出（R-POST-11）：失败计数清零、随时可试；attempts 记着——先补领再重发 */
export function itemForResend(item: OutboxItem): OutboxItem {
  return new OutboxItem(item.attempts, 0, undefined);
}

/** 主导心情（R-OUTBOX-10 / U03）：非空 mood 里出现最多的；并列取先出现的；都空返回 ''（不发） */
export function dominantMoodOf(moods: string[]): string {
  const counts = new Map<string, number>();
  for (const m of moods) {
    if (m.length === 0) {
      continue;
    }
    counts.set(m, (counts.get(m) ?? 0) + 1);
  }
  // 按首次出现顺序扫一遍，严格大于才换人 → 并列时先出现的赢
  let best = '';
  let bestCount = 0;
  const seen = new Set<string>();
  for (const m of moods) {
    if (m.length === 0 || seen.has(m)) {
      continue;
    }
    seen.add(m);
    const n = counts.get(m) ?? 0;
    if (n > bestCount) {
      best = m;
      bestCount = n;
    }
  }
  return best;
}

/** 补领视角的一条服务端信（GET /letters 元素，只留补领要用的三样） */
export class RemoteLetter {
  readonly body: string;
  readonly fromCharacter: string;
  readonly generatedAtMs: number;

  constructor(body: string, fromCharacter: string, generatedAtMs: number) {
    this.body = body;
    this.fromCharacter = fromCharacter;
    this.generatedAtMs = generatedAtMs;
  }
}

/** 本机一封等待中的信（写信中且本机负责）的匹配要素，按 generatedAt 升序传入 */
export class WaitingLetter {
  readonly id: string;
  readonly generatedAtMs: number;

  constructor(id: string, generatedAtMs: number) {
    this.id = id;
    this.generatedAtMs = generatedAtMs;
  }
}

/** 一条服务端信的补领归宿 */
export enum ReconcileActionKind {
  /** 填进某封本机写信中的信（回执丢了的情况，不写第二封） */
  Adopt = 'adopt',
  /** 对不上任何写信中的信 → 新落一封（R-OUTBOX-09） */
  Create = 'create',
  /** 正文本机已有（按正文去重），跳过 */
  Skip = 'skip'
}

export class ReconcileAction {
  readonly kind: ReconcileActionKind;
  /** Adopt 时的目标信 id；其余 '' */
  readonly adoptLetterId: string;
  /** 这条归宿对应的服务端信（按写信时刻升序处理；直接带引用，免下标错位） */
  readonly remote: RemoteLetter;

  constructor(kind: ReconcileActionKind, adoptLetterId: string, remote: RemoteLetter) {
    this.kind = kind;
    this.adoptLetterId = adoptLetterId;
    this.remote = remote;
  }
}

/**
 * 补领匹配（R-OUTBOX-07/09；iOS reconcile 内层逻辑逐字对齐，单测覆盖）：
 * - 服务端信按写信时刻升序逐条认领；某条能认领 waiting 里**第一封**
 *   generatedAt ≤ 这条 generatedAt + 5 分钟 的信，认领掉的信不再参与后续匹配
 * - 正文已在本机的跳过（**按正文去重**：本机没有删信入口，不会复活用户删掉的）
 * - waiting 由调用方按 generatedAt 升序、只放「写信中且本机负责」的
 */
export function reconcilePlan(remote: RemoteLetter[], waiting: WaitingLetter[],
  existingBodies: Set<string>): ReconcileAction[] {
  const ordered = remote.slice().sort((a: RemoteLetter, b: RemoteLetter): number =>
    a.generatedAtMs - b.generatedAtMs);
  const available = waiting.slice();
  const actions: ReconcileAction[] = [];
  for (const item of ordered) {
    if (existingBodies.has(item.body)) {
      actions.push(new ReconcileAction(ReconcileActionKind.Skip, '', item));
      continue;
    }
    let adoptedId = '';
    for (const w of available) {
      if (w.generatedAtMs <= item.generatedAtMs + OUTBOX_CLOCK_SKEW_MS) {
        adoptedId = w.id;
        available.splice(available.indexOf(w), 1);
        break;
      }
    }
    if (adoptedId.length > 0) {
      actions.push(new ReconcileAction(ReconcileActionKind.Adopt, adoptedId, item));
    } else {
      actions.push(new ReconcileAction(ReconcileActionKind.Create, '', item));
    }
  }
  return actions;
}

/**
 * 投下的这封信此刻归不归本机寄（judgePostBoxState 的 Returned/JustPosted
 * 口径要它；写信中 = LetterDelivery.isWriting，退回 = isBounced + 在表里）。
 */
export function isOwnedWriting(letter: Letter, ownedIds: Set<string>): boolean {
  return LetterDelivery.isWriting(letter) && ownedIds.has(letter.id);
}

/** 退回来了且归本机管（R-POST-11 的「不寄了」只对这几封出现） */
export function isOwnedBounce(letter: Letter, ownedIds: Set<string>): boolean {
  return LetterDelivery.isBounced(letter) && ownedIds.has(letter.id);
}
