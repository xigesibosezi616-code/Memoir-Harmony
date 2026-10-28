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
  /** 退回信里关联的日记 id（调用方查 letter_entry 关联表，只算本机负责的退回信） */
  readonly heldEntryIds: Set<string>;
  /** 本机寄信队列负责的信 id（5.3；另一台设备投的信不归本机管，不进 Returned/JustPosted） */
  readonly ownedLetterIds: Set<string>;
  /** GET /me/rhythm 的结果；问不到（未登录、断网）传 undefined，当作能寄（R-POST-05） */
  readonly rhythm: RhythmResponse | undefined;
  readonly isLoggedIn: boolean;
  readonly nowMs: number;

  constructor(letters: Letter[], entries: JournalEntry[], heldEntryIds: Set<string>,
    ownedLetterIds: Set<string>, rhythm: RhythmResponse | undefined,
    isLoggedIn: boolean, nowMs: number) {
    this.letters = letters;
    this.entries = entries;
    this.heldEntryIds = heldEntryIds;
    this.ownedLetterIds = ownedLetterIds;
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
  /** Returned 时那封退回的信（最近投的；视图拿它渲染退回卡片） */
  readonly returnedLetter?: Letter;

  constructor(kind: PostBoxSituationKind, candidates: JournalEntry[],
    returnedLetter?: Letter) {
    this.kind = kind;
    this.candidates = candidates;
    this.returnedLetter = returnedLetter;
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
 * 「本机负责」看 ownedLetterIds（寄信队列的本机负责表）：另一台设备投的信
 * （写信中 / 退回）不劫持本机的邮筒页（iOS isQueued && owns / isReturned 同款）。
 */
export function judgePostBoxState(input: PostBoxStateInput): PostBoxState {
  // 1. 有一封退回来了，等用户决定（最优先——哪怕没登录，退回的信也该让用户看见）。
  //    letters 由调用方按 generated_at 倒序备好，第一个命中的就是最近投的
  const returned = input.letters.find((letter: Letter): boolean =>
    LetterDelivery.isBounced(letter) && input.ownedLetterIds.has(letter.id));
  if (returned !== undefined) {
    return new PostBoxState(PostBoxSituationKind.Returned, [], returned);
  }
  // 2. 未登录
  if (!input.isLoggedIn) {
    return new PostBoxState(PostBoxSituationKind.NotLoggedIn, []);
  }
  // 3. 刚投了一封、还在写（本机负责的）。候选照算：状态行要区分
  //    「信已经投进邮筒了」和「上一封信刚寄出，过一会儿再寄下一封」
  if (input.letters.some((letter: Letter): boolean =>
    LetterDelivery.isWriting(letter) && input.ownedLetterIds.has(letter.id))) {
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

/**
 * 在路上的信（iOS PostBoxView.inTransitLetters 同款）：本机投了还在写的
 * + 写好了还没到的，按寄出时刻从新到旧。底部「邮戳 + 在路上」拿最新那封渲染。
 */
export function inTransitLettersOf(letters: Letter[], ownedLetterIds: Set<string>,
  nowMs: number): Letter[] {
  const transit: Letter[] = letters.filter((letter: Letter): boolean =>
    (LetterDelivery.isWriting(letter) && ownedLetterIds.has(letter.id)) ||
    LetterDelivery.isInTransit(letter, nowMs));
  transit.sort((a: Letter, b: Letter): number => b.generatedAt - a.generatedAt);
  return transit;
}

/** 邮戳上的日期：各国写法差不多，统一「2026.10.11」（iOS Postmark.dateText 同款） */
export function postmarkDateText(dateMs: number): string {
  const d = new Date(dateMs);
  const year = d.getFullYear();
  const month = d.getMonth() + 1;
  const day = d.getDate();
  const pad = (n: number): string => (n < 10 ? '0' + n : '' + n);
  return `${year}.${pad(month)}.${pad(day)}`;
}

/**
 * 邮戳上写哪个地方（iOS Postmark.place(from:) 同款）：这封信里最近一篇记了地点的
 * 日记的地名，只写第一段（城市或地标），太长截短——中日韩方块字 8 个、拉丁 16 个。
 */
export function postmarkPlace(locations: Array<string | undefined>): string {
  let raw: string | undefined = undefined;
  for (const location of locations) {
    if (location !== undefined) {
      const trimmed = location.trim();
      if (trimmed.length > 0) {
        raw = trimmed;
        break;
      }
    }
  }
  if (raw === undefined) {
    return '';
  }
  const segments = raw.split(' ');
  const first = segments.length > 0 ? segments[0] : raw;
  const isWide = Array.from(first).some((ch: string): boolean => ch.charCodeAt(0) >= 0x2E80);
  const limit = isWide ? 8 : 16;
  return first.length > limit ? first.substring(0, limit) : first;
}

/** 邮戳的油墨色（iOS Postmark.ink 同款）：素笺朱红、肯特灰蓝、皮革浅棕 */
export function postmarkInkHex(themeId: string): string {
  switch (themeId) {
    case 'leather':
      return '#C8A87C';
    case 'kent':
      return '#5F7896';
    default:
      return '#B5473A';
  }
}
