/**
 * 邮筒页的候选日记与状况判定（10_BUILD_MANUAL.md 5.2；R-POST-02/03/04/06）。
 * 对应 iOS `PostBoxView.swift` 的 situation / entriesToSend / outgoingItems。
 *
 * 全部纯函数：信 / 日记 / 节奏 / 「此刻」由调用方注入，单测可跑穿各种时间线。
 * 判定顺序（R-POST-06）与候选口径（R-POST-02/03）是跨端行为规则，与 iOS 逐字一致：
 * - 候选按 `createdAt`（真正写下的时刻）判新，不按 `date`（用户可改的日记日期）——
 *   补记一篇上周的日记也算「新写的」
 * - 上次寄信时刻 = 真正的信 + 写信中的信里最大的 `generatedAt`；退回的不算；
 *   退回那封里的日记不出现在候选里（等用户决定，R-POST-03）
 * - 一次最多 14 篇（LetterDelivery.maximumEntriesPerLetter，保护上限）
 */
import { Letter } from './Letter';
import { LetterDelivery } from './LetterDelivery';
import { JournalEntry } from './JournalEntry';
import { RhythmResponse } from './Api';

/** 邮筒页此刻的状况（R-POST-06 判定顺序的产物；先命中先算） */
export enum PostBoxSituationKind {
  /** 有一封退回来了，等用户决定（5.3 寄信队列才有数据） */
  Returned = 'returned',
  NotLoggedIn = 'notLoggedIn',
  /** 刚投了一封、还在写（本机负责的） */
  JustPosted = 'justPosted',
  /** 服务端说这会儿不能寄（GET /me/rhythm 的 reason 驱动文案） */
  Blocked = 'blocked',
  /** 有新日记可寄 */
  Ready = 'ready',
  /** 寄过了、还在路上，也没有新日记 */
  InTransit = 'inTransit',
  /** 没有新日记（上次寄信之后没写过） */
  NothingNew = 'nothingNew',
  /** 一篇日记都没有 */
  NoEntries = 'noEntries'
}

/** judgePostBoxState 的入参（快照值，全部由调用方备好） */
export class PostBoxStateInput {
  readonly letters: Letter[];
  readonly entries: JournalEntry[];
  /** 退回信里关联的日记 id（调用方查 letter_entry 关联表；5.3 之前恒空集） */
  readonly heldEntryIds: Set<string>;
  /** GET /me/rhythm 的结果；问不到（未登录、断网）传 undefined，当作能寄（R-POST-05） */
  readonly rhythm: RhythmResponse | undefined;
  readonly isLoggedIn: boolean;
  readonly nowMs: number;

  constructor(letters: Letter[], entries: JournalEntry[], heldEntryIds: Set<string>,
    rhythm: RhythmResponse | undefined, isLoggedIn: boolean, nowMs: number) {
    this.letters = letters;
    this.entries = entries;
    this.heldEntryIds = heldEntryIds;
    this.rhythm = rhythm;
    this.isLoggedIn = isLoggedIn;
    this.nowMs = nowMs;
  }
}

/** 判定结果：状况 + 顺带算好的候选（Ready/Blocked 的下半区要用） */
export class PostBoxState {
  readonly kind: PostBoxSituationKind;
  /** 这次要寄的日记（R-POST-02/03 口径；Ready/Blocked 之外为空数组） */
  readonly candidates: JournalEntry[];

  constructor(kind: PostBoxSituationKind, candidates: JournalEntry[]) {
    this.kind = kind;
    this.candidates = candidates;
  }
}

/** 这次要寄的日记（R-POST-02/03）：上次寄信之后新写的、退回那封里的除外、最多 14 篇 */
export function candidateEntries(letters: Letter[], entries: JournalEntry[],
  heldEntryIds: Set<string>): JournalEntry[] {
  const lastMs = lastSentAtMs(letters);
  const fresh: JournalEntry[] = lastMs === undefined
    ? entries
    : entries.filter((entry: JournalEntry): boolean => entry.createdAt > lastMs);
  const ready = fresh.filter((entry: JournalEntry): boolean => !heldEntryIds.has(entry.id));
  return ready.slice(0, LetterDelivery.maximumEntriesPerLetter);
}

/** 上次寄信时刻（R-POST-03）：真正的信 + 写信中的信里最大的 generatedAt；退回的不算 */
export function lastSentAtMs(letters: Letter[]): number | undefined {
  let max: number | undefined = undefined;
  for (const letter of letters) {
    if (LetterDelivery.isRealLetter(letter) || LetterDelivery.isWriting(letter)) {
      if (max === undefined || letter.generatedAt > max) {
        max = letter.generatedAt;
      }
    }
  }
  return max;
}

/**
 * 邮筒页此刻的状况，按 R-POST-06 的顺序判定（先命中先算）：
 * 有退回 → 未登录 → 本机有写信中的信 → 服务端拦 → 有可寄 → 在路上 → 没新日记 → 一篇都没有。
 * 「写信中」当前用 LetterDelivery.isWriting（generating 且正文空）近似 iOS 的
 * 队列成员判定（isQueued && owns）——5.3 寄信队列接上后换队列口径。
 */
export function judgePostBoxState(input: PostBoxStateInput): PostBoxState {
  // 1. 有一封退回来了，等用户决定（最优先——哪怕没登录，退回的信也该让用户看见）
  if (input.letters.some((letter: Letter): boolean => LetterDelivery.isBounced(letter))) {
    return new PostBoxState(PostBoxSituationKind.Returned, []);
  }
  // 2. 未登录
  if (!input.isLoggedIn) {
    return new PostBoxState(PostBoxSituationKind.NotLoggedIn, []);
  }
  // 3. 刚投了一封、还在写（本机负责的）。候选照算：状态行要区分
  //    「信已经投进邮筒了」和「上一封信刚寄出，过一会儿再寄下一封」
  if (input.letters.some((letter: Letter): boolean => LetterDelivery.isWriting(letter))) {
    return new PostBoxState(PostBoxSituationKind.JustPosted,
      candidateEntries(input.letters, input.entries, input.heldEntryIds));
  }
  // 4. 服务端说这会儿不能寄（问不到不算拦，最终由服务端拦）
  if (input.rhythm !== undefined && !input.rhythm.canRequestNow) {
    const candidates = candidateEntries(input.letters, input.entries, input.heldEntryIds);
    return new PostBoxState(PostBoxSituationKind.Blocked, candidates);
  }
  // 5. 有新日记可寄
  const candidates = candidateEntries(input.letters, input.entries, input.heldEntryIds);
  if (candidates.length > 0) {
    return new PostBoxState(PostBoxSituationKind.Ready, candidates);
  }
  // 6. 寄过了、还在路上，也没有新日记
  if (input.letters.some((letter: Letter): boolean =>
    LetterDelivery.isInTransit(letter, input.nowMs))) {
    return new PostBoxState(PostBoxSituationKind.InTransit, []);
  }
  // 7/8. 没新日记 / 一篇都没有
  return new PostBoxState(
    input.entries.length === 0 ? PostBoxSituationKind.NoEntries : PostBoxSituationKind.NothingNew,
    []);
}

/** 这次要寄的一篇日记（值快照，给邮筒页那叠纸用）。title 空串 = 显示「无题」 */
export class OutgoingItem {
  readonly id: string;
  /** 日记日期（毫秒），行首展示用 */
  readonly date: number;
  readonly title: string;

  constructor(id: string, date: number, title: string) {
    this.id = id;
    this.date = date;
    this.title = title;
  }
}

/**
 * 一篇日记在那叠纸上的标题（R-POST-04）：标题优先；没标题用正文第一行 ≤30 字；
 * 都没有空串（显示「无题」）。
 */
export function outgoingTitleOf(entry: JournalEntry): string {
  const title = entry.title.trim();
  if (title.length > 0) {
    return title;
  }
  const lines: string[] = entry.content.split('\n');
  const firstLine = lines.length > 0 ? lines[0].trim() : '';
  return firstLine.substring(0, 30);
}

/** 一批日记 → 那叠纸的行快照（R-POST-04；date 用日记自己的 date） */
export function outgoingItemsOf(entries: JournalEntry[]): OutgoingItem[] {
  const items: OutgoingItem[] = [];
  for (const entry of entries) {
    items.push(new OutgoingItem(entry.id, entry.date, outgoingTitleOf(entry)));
  }
  return items;
}

/** 信箱入口有没有未读（红点）：任一封已到达且未读 */
export function hasUnreadLetter(letters: Letter[], nowMs: number): boolean {
  return letters.some((letter: Letter): boolean => LetterDelivery.isUnread(letter, nowMs));
}
