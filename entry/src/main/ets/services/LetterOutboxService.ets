/**
 * 寄信队列（10_BUILD_MANUAL.md 5.3；R-OUTBOX-01~11）。
 * 对应 iOS `Services/LetterOutbox.swift` 的编排壳。
 *
 * - 「哪些信归本机寄」记在**本机偏好**（AppPrefs `letterOutbox.v1` JSON，
 *   纯逻辑层 LetterOutboxLogic 编解码），🔴 不进库、不进同步（R-OUTBOX-01）
 * - process：把本机负责、到了该试时候的信一封封寄出去，随便叫不会重复寄
 *   （isProcessing 单飞，R-OUTBOX-02）；发过请求的（attempts>0）重发前先补领（R-OUTBOX-07）
 * - 429 先补领一次，领不到才退回并说明原因（R-OUTBOX-08）；429 的 reason 在
 *   顶层、message 只有中文，按 reason 本地渲染（02_BACKEND_API「POST /letter」）
 * - 退回原因在退回那一刻渲染成本地语言快照存 errorMessage（iOS 存
 *   error.localizedDescription 同款；之后换语言这张卡不跟着换）
 * - 寄信请求包短时后台任务（R-OUTBOX-02「投完信马上切走也要尽量寄完」；
 *   iOS beginBackgroundTask 对应 backgroundTaskManager.requestSuspendDelay）
 * - 成功后的**到达通知预约是 5.4**：notifyArrival 位点已留，本卡不实现
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDatabase } from '../data/Database';
import { LetterRepository } from '../data/LetterRepository';
import { EntryRepository } from '../data/EntryRepository';
import { Letter, LetterStatus, LetterTriggerKind, letterStationery } from '../models/Letter';
import { LetterDelivery } from '../models/LetterDelivery';
import { JournalEntry } from '../models/JournalEntry';
import { generateUuid } from '../models/Uuid';
import {
  LetterRequest,
  LetterRequestEntry,
  LetterSummaryDTO
} from '../models/Api';
import {
  OutboxItem,
  RemoteLetter,
  WaitingLetter,
  ReconcileActionKind,
  decodeOutboxState,
  encodeOutboxState,
  isOutboxDue,
  itemAfterNetworkError,
  itemAfterServerFailure,
  itemForResend,
  shouldGiveBack,
  dominantMoodOf,
  reconcilePlan
} from '../models/LetterOutboxLogic';
import { AppPrefs } from './AppPrefs';
import { UserSession } from './auth/UserSession';
import { AuthService } from './auth/AuthService';
import { HttpError } from './http/HttpError';

const DOMAIN = 0x0000;
const TAG = 'LetterOutboxService';

/** 本机负责表的偏好键（iOS UserDefaults stateKey 同名，R-OUTBOX-01） */
export const PREF_KEY_LETTER_OUTBOX = 'letterOutbox.v1';

/** AppStorage key：队列改了库里的信（寄出 / 退回 / 补领）时 +1——
 *  邮筒页 @Watch 重查（SwiftData @Query 自动刷新的等价物） */
export const STORAGE_KEY_LETTER_OUTBOX_TICK = 'letterOutboxTick';

export class LetterOutboxService {
  private readonly context: common.Context;
  private readonly session: UserSession;
  private readonly auth: AuthService;

  /** 内存里的一份负责表；null = 还没从偏好读过（构造时偏好可能未 load） */
  private state: Map<string, OutboxItem> | null = null;
  /** 正在跑一轮（同一时间只跑一轮，免得同一封信被发两次；R-OUTBOX-02） */
  private isProcessing: boolean = false;

  constructor(context: common.Context, session: UserSession, auth: AuthService) {
    this.context = context;
    this.session = session;
    this.auth = auth;
  }

  /** 队列改了信 → 通知开着邮筒页的界面重查 */
  private bumpTick(): void {
    AppStorage.setOrCreate(STORAGE_KEY_LETTER_OUTBOX_TICK,
      (AppStorage.get<number>(STORAGE_KEY_LETTER_OUTBOX_TICK) ?? 0) + 1);
  }

  // ---- 本机负责表 ----

  /** 惰性读偏好 → 内存缓存；所有写都经 saveState，进程内始终一致 */
  private ensureState(): Map<string, OutboxItem> {
    if (this.state === null) {
      this.state = decodeOutboxState(AppPrefs.getString(PREF_KEY_LETTER_OUTBOX, ''));
    }
    return this.state;
  }

  private saveState(state: Map<string, OutboxItem>): void {
    this.state = state;
    AppPrefs.putString(PREF_KEY_LETTER_OUTBOX, encodeOutboxState(state));
  }

  private mutateItem(letterId: string,
    change: (item: OutboxItem) => OutboxItem): void {
    const state = this.ensureState();
    const current = state.get(letterId) ?? new OutboxItem(0, 0, undefined);
    state.set(letterId, change(current));
    this.saveState(state);
  }

  private forget(letterId: string): void {
    const state = this.ensureState();
    state.delete(letterId);
    this.saveState(state);
  }

  /** 这封信归不归本机寄（写信中、退回来的都算；R-OUTBOX-01） */
  owns(letterId: string): boolean {
    return this.ensureState().has(letterId);
  }

  /** 本机负责表的全部信 id（PostBoxLogic 的 Returned/JustPosted 口径用） */
  ownedLetterIds(): Set<string> {
    const ids = new Set<string>();
    this.ensureState().forEach((item: OutboxItem, id: string): void => {
      ids.add(id);
    });
    return ids;
  }

  /** 刚投进邮筒的一封，交给本机寄 */
  enqueue(letterId: string): void {
    this.mutateItem(letterId, (): OutboxItem => new OutboxItem(0, 0, undefined));
  }

  // ---- 退回之后（R-POST-11）----

  /**
   * 重新寄出：回到写信中，失败计数清零（attempts 记着，先补领再重发），
   * 寄信立刻接着跑。信找不到（手删库）只清负责表。
   */
  async resend(letterId: string): Promise<void> {
    const store = await AppDatabase.open(this.context);
    const letter = await LetterRepository.findLetter(store, letterId);
    if (letter !== null) {
      letter.status = LetterStatus.Generating;
      letter.errorMessage = undefined;
      letter.updatedAt = Date.now();
      await LetterRepository.saveLetter(store, letter);
      this.bumpTick();
    }
    this.mutateItem(letterId, (item: OutboxItem): OutboxItem => itemForResend(item));
    await this.process();
  }

  /**
   * 不寄了：本机不再管它，带着的日记放回「要寄的日记」里。这条记录本身留着
   * （正文空、状态失败，哪儿都不显示），不删库里的东西。
   */
  async discard(letterId: string): Promise<void> {
    const store = await AppDatabase.open(this.context);
    const letter = await LetterRepository.findLetter(store, letterId);
    if (letter !== null) {
      await LetterRepository.clearLetterEntries(store, letterId);
      letter.updatedAt = Date.now();
      await LetterRepository.saveLetter(store, letter);
    }
    this.forget(letterId);
    this.bumpTick();
  }

  // ---- 寄 ----

  /** 把本机负责、到了该试的时候的信一封封寄出去（R-OUTBOX-02） */
  async process(): Promise<void> {
    if (this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    try {
      const store = await AppDatabase.open(this.context);
      const tried = new Set<string>();
      // 一封寄完再找下一封：跑的过程中刚投进来的信也能接上
      for (;;) {
        const letter = await this.nextDueLetter(store, tried);
        if (letter === null) {
          break;
        }
        tried.add(letter.id);
        await this.send(store, letter);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'process failed: %{public}s', JSON.stringify(err));
    } finally {
      this.isProcessing = false;
    }
  }

  /** 下一封该试的：写信中、归本机、到了时候、还没试过；按寄出先后（iOS nextDue 同款） */
  private async nextDueLetter(store: relationalStore.RdbStore,
    tried: Set<string>): Promise<Letter | null> {
    const state = this.ensureState();
    if (state.size === 0) {
      return null;
    }
    const letters = await LetterRepository.listLetters(store);
    const candidates: Letter[] = [];
    for (const letter of letters) {
      const item = state.get(letter.id);
      // 写信中（generating 且正文空）才归队列管；已退回的等用户决定
      if (item !== undefined && LetterDelivery.isWriting(letter) &&
        !tried.has(letter.id) && isOutboxDue(item, Date.now())) {
        candidates.push(letter);
      }
    }
    // listLetters 是 generated_at 倒序，这里要最早的先寄
    candidates.sort((a: Letter, b: Letter): number => a.generatedAt - b.generatedAt);
    return candidates.length > 0 ? candidates[0] : null;
  }

  private async send(store: relationalStore.RdbStore, letter: Letter): Promise<void> {
    const item = this.ensureState().get(letter.id) ?? new OutboxItem(0, 0, undefined);

    // 之前发过请求：服务端可能已经写好了，先补领，领到了就不再写第二封（R-OUTBOX-07）
    if (item.attempts > 0) {
      await this.reconcile();
      const fresh = await LetterRepository.findLetter(store, letter.id);
      if (fresh === null || !LetterDelivery.isWriting(fresh)) {
        return;
      }
    }

    // 没登录 → 直接退回（R-OUTBOX-06）
    if (!this.session.isLoggedIn() || this.session.token === null) {
      await this.giveBack(store, letter, this.str($r('app.string.s_2bbc8185e3')));
      return;
    }

    // 这封信勾上的日记（悬空引用滤掉——日记删了 letter_entry 会留下，R-OUTBOX-06）
    const entryIds = await LetterRepository.entryIdsForLetters(store, [letter.id]);
    const allEntries = await EntryRepository.fetchAllEntries(store);
    const entries: JournalEntry[] = [];
    for (const entry of allEntries) {
      if (entryIds.has(entry.id)) {
        entries.push(entry);
      }
    }
    if (entries.length === 0) {
      await this.giveBack(store, letter, this.str($r('app.string.s_0903a88878')));
      return;
    }
    // 日记按 date 倒序发（R-OUTBOX-10）；断网重发时 date 可能被改过，按库里现状
    entries.sort((a: JournalEntry, b: JournalEntry): number => b.date - a.date);

    const requestEntries: LetterRequestEntry[] = [];
    for (const entry of entries) {
      requestEntries.push(new LetterRequestEntry(entry.title, entry.content,
        entry.date, entry.mood));
    }
    const request = new LetterRequest(requestEntries, LetterTriggerKind.Weekly,
      dominantMoodOf(entries.map((entry: JournalEntry): string => entry.mood)),
      letter.fromCharacter, '');

    this.mutateItem(letter.id, (current: OutboxItem): OutboxItem =>
      new OutboxItem(current.attempts + 1, current.failures, current.nextAttemptAt));
    const token = this.session.token;

    // 投完信马上切走 App 也来得及：向系统多要一点后台时间把这一封寄完（R-OUTBOX-02）
    let suspendRequestId = -1;
    try {
      suspendRequestId = this.beginSuspendDelay();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'requestSuspendDelay failed: %{public}s', JSON.stringify(err));
    }
    try {
      const response = await this.auth.sendLetter(request, token);
      // 补领可能抢先一步填好了（同一封回信），就不用再填
      const fresh = await LetterRepository.findLetter(store, letter.id);
      if (fresh === null || !LetterDelivery.isWriting(fresh)) {
        return;
      }
      // 空正文按服务端异常走重试（iOS 在这里抛「来信内容为空」硬编码中文，
      // 鸿蒙不走那条路：重试满 3 次退回时用通用原因，外语用户不见中文）
      if (response.body.trim().length === 0) {
        await this.failedOnce(store, fresh, '');
        return;
      }
      fresh.body = response.body;
      fresh.fromCharacter = response.fromCharacter;
      fresh.status = LetterStatus.Pending;
      fresh.errorMessage = undefined;
      fresh.updatedAt = Date.now();
      try {
        await LetterRepository.saveLetter(store, fresh);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'save sent letter failed: %{public}s', JSON.stringify(err));
        return;
      }
      this.forget(letter.id);
      this.bumpTick();
      hilog.info(DOMAIN, TAG, 'sent letter id=%{public}s', letter.id);
      // 5.4 到达通知预约位点（R-OUTBOX-03）：notifyArrival(fresh)，本卡不实现
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'send letter failed id=%{public}s: %{public}s',
        letter.id, JSON.stringify(err));
      await this.handleError(store, letter, err);
    } finally {
      if (suspendRequestId >= 0) {
        this.cancelSuspendDelay(suspendRequestId);
      }
    }
  }

  /** 短时后台任务（R-OUTBOX-02）：寄信这一封包在里面，切后台也能尽量寄完 */
  private beginSuspendDelay(): number {
    const info = backgroundTaskManager.requestSuspendDelay('letter-send', (): void => {
      hilog.info(DOMAIN, TAG, '%{public}s', 'suspend delay expired');
    });
    return info.requestId;
  }

  private cancelSuspendDelay(requestId: number): void {
    try {
      backgroundTaskManager.cancelSuspendDelay(requestId);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'cancelSuspendDelay failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 寄信失败分类（R-OUTBOX-04/05/06/08；iOS handle 同款分支） */
  private async handleError(store: relationalStore.RdbStore, letter: Letter,
    err: Object): Promise<void> {
    if (err instanceof HttpError) {
      // 断网 / 超时 / 取消 / 传输故障：不算失败，30 秒后接着寄
      // （超时的那次服务端可能已经写好了，attempts>0 下次先补领）
      if (err.isNetworkError()) {
        this.mutateItem(letter.id, (item: OutboxItem): OutboxItem =>
          itemAfterNetworkError(item, Date.now()));
        return;
      }
      // 被节奏拦下：十有八九是这封信已经写好在服务端了——先补领一次；
      // 领到就算寄成，领不到才是真的这周寄过了，退回并说明原因（R-OUTBOX-08）
      if (err.isRateLimited()) {
        await this.reconcile();
        const fresh = await LetterRepository.findLetter(store, letter.id);
        if (fresh !== null && LetterDelivery.isWriting(fresh)) {
          await this.giveBack(store, fresh, this.rateLimitReason(err, fresh.fromCharacter));
        }
        return;
      }
      // 登录过期：401 闸门已清会话（HarmonyHttpClient），按没登录退回（R-OUTBOX-06）
      if (err.isUnauthorized()) {
        await this.giveBack(store, letter, this.str($r('app.string.s_2bbc8185e3')));
        return;
      }
      // 其余服务端错（含 502 ai_failed / empty_response 的服务端文案透传）
      await this.failedOnce(store, letter,
        err.envelope !== null ? err.envelope.message : '');
      return;
    }
    // 非 HTTP 档（解码失败等）也按服务端出错计
    await this.failedOnce(store, letter, '');
  }

  /** 服务端出错一次：没到次数就隔一阵再试，到了就退回（R-OUTBOX-05） */
  private async failedOnce(store: relationalStore.RdbStore, letter: Letter,
    serverMessage: string): Promise<void> {
    const state = this.ensureState();
    const current = state.get(letter.id) ?? new OutboxItem(0, 0, undefined);
    const next = itemAfterServerFailure(current, Date.now());
    state.set(letter.id, next);
    this.saveState(state);
    if (shouldGiveBack(next)) {
      const reason = serverMessage.length > 0
        ? this.strWith($r('app.string.s_15b21b73b7'), serverMessage)
        : this.str($r('app.string.s_5283bf449c'));
      await this.giveBack(store, letter, reason);
    }
  }

  /** 退回邮筒页：status=failed + 原因快照（R-OUTBOX-05/06；R-COPY-03 不说「生成」） */
  private async giveBack(store: relationalStore.RdbStore, letter: Letter,
    reason: string): Promise<void> {
    letter.status = LetterStatus.Failed;
    letter.errorMessage = reason;
    letter.updatedAt = Date.now();
    try {
      await LetterRepository.saveLetter(store, letter);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'give back letter failed: %{public}s', JSON.stringify(err));
      return;
    }
    this.mutateItem(letter.id, (item: OutboxItem): OutboxItem =>
      new OutboxItem(item.attempts, item.failures, undefined));
    this.bumpTick();
  }

  /**
   * 429 的退回原因（R-OUTBOX-08 + R-POST-12 语气）。**不用「额度 / 剩余 N 封」
   * 这类计量词**（定价文档 §5.1）：后端 message 只有中文，按 reason 本地渲染。
   */
  private rateLimitReason(err: HttpError, penPalName: string): string {
    const reason = err.envelope !== null && err.envelope.reason !== undefined
      ? err.envelope.reason : '';
    switch (reason) {
      case 'weekly_pending':
        return this.strWith($r('app.string.s_c0fc825651'), penPalName);
      case 'daily_cap':
        return this.str($r('app.string.s_a911a90bfb'));
      case 'monthly_cap':
        return this.strWith($r('app.string.s_c5e6652443'), penPalName);
      case 'welcome_pending':
        return this.strWith($r('app.string.s_692e58f019'), penPalName);
      default:
        if (err.envelope !== null && err.envelope.retryAfter !== undefined) {
          return this.strWith($r('app.string.s_b7c45049d1'), err.envelope.retryAfter);
        }
        return this.strWith($r('app.string.s_acc4a9dd8c'), penPalName);
    }
  }

  // ---- 补领（R-OUTBOX-07/08/09）----

  /**
   * 把服务端有、本机没有的信领回来。补领是静默的后台动作，失败下次再领。
   * 匹配 / 去重 / 新落一封的判定在纯逻辑层 reconcilePlan（单测覆盖）。
   */
  async reconcile(): Promise<void> {
    const token = this.session.token;
    if (!this.session.isLoggedIn() || token === null) {
      return;
    }
    let remote: LetterSummaryDTO[];
    try {
      remote = await this.auth.fetchLetters(20, token);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'reconcile fetch failed: %{public}s', JSON.stringify(err));
      return;
    }
    if (remote.length === 0) {
      return;
    }
    const store = await AppDatabase.open(this.context);
    const all = await LetterRepository.listLetters(store);
    const existingBodies = new Set<string>();
    const owned = this.ownedLetterIds();
    const waiting: WaitingLetter[] = [];
    for (const letter of all) {
      existingBodies.add(letter.body);
      if (LetterDelivery.isWriting(letter) && owned.has(letter.id)) {
        waiting.push(new WaitingLetter(letter.id, letter.generatedAt));
      }
    }
    // 等待的按寄出先后排（reconcilePlan 从最早的认领起）
    waiting.sort((a: WaitingLetter, b: WaitingLetter): number => a.generatedAtMs - b.generatedAtMs);
    const remoteLetters: RemoteLetter[] = [];
    for (const item of remote) {
      remoteLetters.push(new RemoteLetter(item.body, item.fromCharacter, item.generatedAtMs));
    }
    const actions = reconcilePlan(remoteLetters, waiting, existingBodies);
    let adoptedCount = 0;
    for (const action of actions) {
      const item = action.remote;
      if (action.kind === ReconcileActionKind.Adopt) {
        const letter = await LetterRepository.findLetter(store, action.adoptLetterId);
        if (letter === null || !LetterDelivery.isWriting(letter)) {
          continue;
        }
        letter.body = item.body;
        letter.fromCharacter = item.fromCharacter;
        letter.status = LetterStatus.Pending;
        letter.errorMessage = undefined;
        letter.updatedAt = Date.now();
        await LetterRepository.saveLetter(store, letter);
        this.forget(letter.id);
        adoptedCount++;
        // 5.4 通知位点：notifyArrival(letter, onlyIfAhead = false)，本卡不实现
      } else if (action.kind === ReconcileActionKind.Create) {
        // 对不上任何写信中的信 → 新落一封（R-OUTBOX-09）：
        // 到达时刻按服务端的写信时刻重算（早过了三天的即刻到达），
        // stationery 按补领时会员身份（当前无会员体系，恒普通信）
        const letter = new Letter(generateUuid(), item.generatedAtMs, Date.now());
        letter.status = LetterStatus.Pending;
        letter.body = item.body;
        letter.fromCharacter = item.fromCharacter;
        const user = this.session.user;
        if (user !== null && user.displayName.length > 0) {
          letter.toName = user.displayName;
        }
        letter.triggerKind = LetterTriggerKind.Weekly;
        letter.stationery = letterStationery(false);
        letter.deliveredAt = LetterDelivery.arrivalDate(item.generatedAtMs, 1, Math.random);
        await LetterRepository.saveLetter(store, letter);
        adoptedCount++;
        // 5.4 通知位点：notifyArrival(letter, onlyIfAhead = true)，本卡不实现
      }
      // Skip：正文本机已有（按正文去重），不动
    }
    if (adoptedCount > 0) {
      this.bumpTick();
      hilog.info(DOMAIN, TAG, 'reconciled %{public}d letters', adoptedCount);
    }
  }

  // ---- 本地化（退回原因快照；resourceManager 同步取，$r 须字面量）----

  private str(res: Resource): string {
    return this.context.resourceManager.getStringSync(res.id);
  }

  private strWith(res: Resource, arg: string | number): string {
    return this.context.resourceManager.getStringSync(res.id, arg);
  }
}
