/**
 * 邮筒 tab（10_BUILD_MANUAL.md 5.1 壳 + 5.2 正文）。对应 iOS
 * `Views/PostBox/PostBoxView.swift` + `Posting/PostBoxPage.swift`。
 *
 * - 整页一个邮筒（插画由主题提供），页面底色取插画**左上 1 像素**
 *   （图不带透明底，底色差一点就会看出一个框；iOS UIImage.cornerColor 同款）
 * - 下面一行状态（R-POST-06 八种情况，先命中先算）+ 一块固定高度
 *   （188vp）的地方放「这次寄出的日记」那叠纸（5.3 投信动画要从纸飞到
 *   投信口，中途邮筒不能因下面换内容变大变小）
 * - 候选口径 R-POST-02/03 在 PostBoxLogic（纯逻辑，带单测）
 * - 进页面就问 GET /me/rhythm：这周寄不了提前说明，不等点了再拒
 *   （R-POST-05；问不到当作能寄，最终由服务端拦）
 * - 点邮筒投信（5.3 落库 + 5.6 动画）：落库成功才起投信动画（displaySync
 *   逐帧推进 postingT，手感数值集中在 LetterPostingTimeline /
 *   LetterPostingFlightGeometry，单测钉死）；动画放完才申请通知授权
 *   （R-POST-09）；投信口拒收轻轻一顿（LetterPostingFeel）
 * - 「此刻」每 5 秒推进（R-BOX-02）：在路上的信到点，右上角红点自己亮
 * - 切到本 tab / 登录态变化才重查（MainTabsView onChange 写
 *   STORAGE_KEY_POSTBOX_VISIBLE_TICK 驱动；tab 内容常驻不重建）
 * - 标题栏：左上不出「邮筒」二字（用户拍板，iOS 同款无标题），
 *   右上角「信箱」入口 = 官方 Button（缩小版：高 32、图标 16、字 12），
 *   位置对齐首页页首「+」（安全区顶+28、右 20），带未读红点（红色用
 *   destructive——accent 在部分主题是墨色会看成黑点）
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { displaySync } from '@kit.ArkGraphics2D';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { STORAGE_KEY_SESSION_TICK } from '../../services/auth/UserSession';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { AppDatabase } from '../../data/Database';
import { LetterRepository } from '../../data/LetterRepository';
import { EntryRepository } from '../../data/EntryRepository';
import { LetterDelivery } from '../../models/LetterDelivery';
import { Letter, LetterStatus, LetterTriggerKind, letterStationery } from '../../models/Letter';
import { generateUuid } from '../../models/Uuid';
import { JournalEntry } from '../../models/JournalEntry';
import { RhythmResponse } from '../../models/Api';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { shortDate } from '../../services/AppDateFormatters';
import {
  PostBoxSituationKind,
  PostBoxState,
  PostBoxStateInput,
  judgePostBoxState,
  outgoingItemsOf,
  hasUnreadLetter,
  inTransitLettersOf,
  postmarkPlace,
  postmarkInkHex
} from '../../models/PostBoxLogic';
import { OutgoingItem } from '../../models/PostBoxLogic';
import { LetterPostingTimeline } from '../../models/LetterPostingTimeline';
import {
  PostingRun,
  RectF,
  fitRectInRect,
  slotRectOf,
  MAILBOX_IMAGE_ASPECT
} from '../../models/LetterPostingFlightGeometry';
import { LetterPostingFeel } from '../../services/LetterPostingFeel';
import { LetterPalette } from './LetterPalette';
import { OutgoingPile } from './OutgoingPile';
import { LetterPostingFlight } from './LetterPostingFlight';
import { Postmark } from './Postmark';
import { PostBoxMetrics } from './PostBoxMetrics';
import { STORAGE_KEY_LETTER_OUTBOX_TICK } from '../../services/LetterOutboxService';
import { STORAGE_KEY_POSTBOX_OPEN_LETTERBOX_TICK } from '../../services/LetterNotifications';
import { mailboxPageColor } from '../../services/MailboxPageColor';
import {
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_WINDOW_HEIGHT_VP
} from '../../services/ImmersiveChrome';
import { AppPrefs, PREF_KEY_PEN_PAL_NAME } from '../../services/AppPrefs';

const DOMAIN = 0x0000;
const TAG = 'PostBoxTabView';

/** AppStorage key：切到邮筒 tab 时 +1（MainTabsView onChange 写；tab 内容常驻不重建） */
export const STORAGE_KEY_POSTBOX_VISIBLE_TICK = 'postboxVisibleTick';

/** 「此刻」推进间隔（R-BOX-02），对齐 iOS 5 秒 */
const NOW_TICK_INTERVAL_MS: number = 5000;

@Component
export struct PostBoxTabView {
  @StorageProp(STORAGE_KEY_THEME) @Watch('onThemeChanged') theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  /** 底部避让：悬浮胶囊 Tab 栏离底安全距离（HomeView 同款约定） */
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  /** 顶部避让（沉浸式下内容要从状态栏下开始；顶距按它标定，跨机型不漂） */
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  /** 窗口高（ImmersiveChrome 折叠/旋转/改窗时发布；版式度量按它分档） */
  @StorageProp(STORAGE_KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 0;
  /** 登录 / 登出 / 注销后重查（登录状态影响节奏问询和状态行） */
  @StorageProp(STORAGE_KEY_SESSION_TICK) @Watch('reload') sessionTick: number = 0;
  /** 切到本 tab 时重查（别的 tab 里写了日记、寄了信，回来都要是最新的） */
  @StorageProp(STORAGE_KEY_POSTBOX_VISIBLE_TICK) @Watch('reload') visibleTick: number = 0;
  /** 寄信队列改了库里的信（寄出 / 退回 / 补领）时重查——人坐在本页也要是最新的 */
  @StorageProp(STORAGE_KEY_LETTER_OUTBOX_TICK) @Watch('reload') outboxTick: number = 0;
  /** 5.4 点到达通知（R-NOTIFY-05）：主框架切到邮筒 tab 后 +1，本页 push 信箱。
   *  冷启动主框架先切 tab 再挂本页，@Watch 首值不触发 → aboutToAppear 手动消费 */
  @StorageProp(STORAGE_KEY_POSTBOX_OPEN_LETTERBOX_TICK)
  @Watch('onOpenLetterboxRequested') openLetterboxTick: number = 0;
  @State private letters: Letter[] = [];
  @State private entries: JournalEntry[] = [];
  /** 退回信里关联的日记 id（不出现在候选里，R-POST-03） */
  @State private heldEntryIds: Set<string> = new Set<string>();
  /** 这一叠里取消勾选的（勾选状态本地持有，投信那一刻才算数） */
  @State private excluded: Set<string> = new Set<string>();
  /** 服务端说现在能不能寄；问不到（未登录、断网）undefined，当作能寄（R-POST-05） */
  @State private rhythm: RhythmResponse | undefined = undefined;
  /** 「此刻」（毫秒），定时推进——路上的信到点，红点自己亮（R-BOX-02） */
  @State private nowMs: number = Date.now();
  /** 邮筒插画左上 1 像素的颜色，当整页底色；取不到退回主题背景 */
  @State private pageColor: string | undefined = undefined;
  @State private penPalName: string = '青鸟';
  /** 「邮戳 + 在路上」快照（reload 时备好；Postmark 地点要查关联日记，渲染时不能异步） */
  @State private transitPlace: string = '';
  @State private transitHasOthers: boolean = false;
  /** 最新一封在途信快照（reload 时与上面几个一起备好）。
   *  排雷（实机实证）：@Builder 按值传参（表达式实参）不随状态刷新——
   *  首渲染 letters 未加载时以 undefined 落地，reload 后即使 if 分支
   *  不切换也不会重刷，下半区就一直空着。快照进 @State、builder 无参读它 */
  @State private transitLetter: Letter | undefined = undefined;
  private navPathStack: NavPathStack = new NavPathStack();
  private store: relationalStore.RdbStore | undefined = undefined;
  private nowTimerId: number = -1;

  // ---- 5.6 投信动画（displaySync 逐帧推进 postingT；手感集中在几何层单测） ----
  /** 正在投的那一封（undefined = 没在投信）。投进去就算寄出：落库成功才起动画 */
  @State private posting: PostingRun | undefined = undefined;
  /** 动画推进到的时刻（秒，0 ~ TOTAL），displaySync 每帧推一下 */
  @State private postingT: number = 0;
  /** 投信的手感：跟动画节点的小震动 + 封口声（预载失败只是没声没震，静默） */
  private postingFeel: LetterPostingFeel = new LetterPostingFeel();
  /** 逐帧驱动（动画起了才 start，放完 / 离开页面 stop） */
  private postingSync: displaySync.DisplaySync | undefined = undefined;
  private postingFrameCallback: ((info: displaySync.IntervalInfo) => void) | undefined = undefined;
  /** 动画起点（displaySync 回调的 ns 时间戳；首帧定下） */
  private postingStartNs: number = -1;
  /** 起飞那一刻量好的几何（动画期间版式恒定，量一次用到底） */
  private postingSlotRect: RectF = { x: 0, y: 0, width: 0, height: 0 };
  private postingPileRect: RectF = { x: 0, y: 0, width: 0, height: 0 };
  /** 落库进行中（防连点双寄：posting 要落库成功才立起来，这中间也得拦） */
  private postingUnderway: boolean = false;

  aboutToAppear(): void {
    this.penPalName = AppPrefs.getString(PREF_KEY_PEN_PAL_NAME, '青鸟');
    this.nowTimerId = setInterval((): void => {
      this.nowMs = Date.now();
    }, NOW_TICK_INTERVAL_MS);
    this.loadPageColor();
    this.reload();
    // 5.4 点通知冷启动路由（R-NOTIFY-05）：主框架已先 bump（EntryAbility →
    // MainTabsView 切 tab）→ 本页首次挂载时读残留信号手动消费一次
    if (this.openLetterboxTick > 0) {
      this.onOpenLetterboxRequested();
    }
    // 5.6 投信手感预载：声音两条 wav 走 rawfile（生成脚本和 iOS 共用），
    // 页面一出现就备好，点邮筒那一刻不用等
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.postingFeel.prepare(context.resourceManager);
    }
  }

  aboutToDisappear(): void {
    if (this.nowTimerId >= 0) {
      clearInterval(this.nowTimerId);
      this.nowTimerId = -1;
    }
    // 5.6：动画没放完就离开页面——停驱动、停震、放掉解码器
    this.stopPostingSync();
    this.postingFeel.cancel();
    this.postingFeel.release();
  }

  /** 5.4 点到达通知路由（R-NOTIFY-05）：进本页即推信箱；消费即清零防重复触发。
   *  返回时的重查不靠 onPop（侧滑返回不触发），靠信箱页 onDisappear bump
   *  STORAGE_KEY_POSTBOX_VISIBLE_TICK（见 LetterboxView） */
  private onOpenLetterboxRequested(): void {
    AppStorage.setOrCreate(STORAGE_KEY_POSTBOX_OPEN_LETTERBOX_TICK, 0);
    this.navPathStack.pushPathByName('Letterbox', '');
  }

  /** 换主题 = 换邮筒插画 = 底色重取；笔友名也顺手刷新（设置页改完回来生效） */
  private onThemeChanged(): void {
    this.penPalName = AppPrefs.getString(PREF_KEY_PEN_PAL_NAME, '青鸟');
    this.loadPageColor();
  }

  private palette(): LetterPalette {
    return LetterPalette.of(this.theme.id);
  }

  /** 本机型/形态的版式度量（纯计算，单测覆盖；窗口高未发布时按主流直板兜底） */
  private metrics(): PostBoxMetrics {
    const windowHeight = this.windowHeightVp > 0 ? this.windowHeightVp : 782.65;
    return PostBoxMetrics.compute(windowHeight, this.safeAreaTopVp, this.safeAreaBottomVp);
  }

  /** 本机寄信队列负责的信 id（Returned/JustPosted 的口径；队列没装配时空集） */
  private ownedLetterIds(): Set<string> {
    return this.env.outbox !== undefined ? this.env.outbox.ownedLetterIds() : new Set<string>();
  }

  private isLoggedIn(): boolean {
    return this.env.session !== undefined && this.env.session.isLoggedIn();
  }

  /** 邮筒插画左上 1 像素 → 整页底色（结果按主题 id 缓存） */
  private loadPageColor(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    mailboxPageColor(context, this.theme.id, this.theme.mailboxImage)
      .then((hex: string | undefined): void => {
        this.pageColor = hex;
      });
  }

  /** 全量重查：信、日记、退回信关联的日记、节奏（进 tab / 登录态变都走这） */
  private reload(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const load = async (): Promise<void> => {
      try {
        if (this.store === undefined) {
          this.store = await AppDatabase.open(context);
        }
        const store = this.store;
        this.letters = await LetterRepository.listLetters(store);
        this.entries = await EntryRepository.fetchAllEntries(store);
        // 本机负责的退回信里关联的日记不重新出现在候选里（R-POST-03；
        // 另一台设备退回的不算——它的日记不该被这台机器扣住）
        const owned = this.ownedLetterIds();
        const bouncedIds: string[] = [];
        for (const letter of this.letters) {
          if (LetterDelivery.isBounced(letter) && owned.has(letter.id)) {
            bouncedIds.push(letter.id);
          }
        }
        this.heldEntryIds = await LetterRepository.entryIdsForLetters(store, bouncedIds);
        // 「邮戳 + 在路上」的快照（iOS PostBoxView.latestInTransit + Postmark.place）：
        // 最新那封在途信的寄出地点取它关联日记记下的地方，是否还有别的信也在路上
        const transit = inTransitLettersOf(this.letters, owned, this.nowMs);
        const latestTransit = transit.length > 0 ? transit[0] : undefined;
        if (latestTransit !== undefined) {
          const linkedIds = await LetterRepository.entryIdsForLetters(store, [latestTransit.id]);
          const locations: Array<string | undefined> = [];
          for (const entry of this.entries) {
            if (linkedIds.has(entry.id)) {
              locations.push(entry.locationInfo);
            }
          }
          this.transitLetter = latestTransit;
          this.transitPlace = postmarkPlace(locations);
          this.transitHasOthers = transit.length > 1;
        } else {
          this.transitLetter = undefined;
          this.transitPlace = '';
          this.transitHasOthers = false;
        }
        // 新一轮候选出来，旧的勾选清掉（默认全勾；R-POST-04）
        this.excluded = new Set<string>();
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'reload postbox failed: %{public}s', JSON.stringify(err));
      }
    };
    load();
    this.refreshRhythm();
  }

  /** 能不能寄，问服务端（R-POST-05/12：判定权只在服务端，这里只提前说明） */
  private refreshRhythm(): void {
    const session = this.env.session;
    const auth = this.env.auth;
    const token = session !== undefined ? session.token : null;
    if (!this.isLoggedIn() || auth === undefined || token === null) {
      this.rhythm = undefined;
      return;
    }
    auth.fetchRhythm(token)
      .then((rhythm: RhythmResponse): void => {
        this.rhythm = rhythm;
      })
      .catch((err: BusinessError): void => {
        // 问不到当作能寄，最终由服务端拦（R-POST-05）
        hilog.warn(DOMAIN, TAG, 'fetch rhythm failed: %{public}s', JSON.stringify(err));
        this.rhythm = undefined;
      });
  }

  /** 此刻的状况（R-POST-06 判定顺序，纯逻辑在 PostBoxLogic） */
  private state(): PostBoxState {
    return judgePostBoxState(new PostBoxStateInput(this.letters, this.entries,
      this.heldEntryIds, this.ownedLetterIds(), this.rhythm, this.isLoggedIn(), this.nowMs));
  }

  /** 有信在路上（本机投的写信中 + 写好了还没到的；服务端拦着时下面半透明摆纸用） */
  private hasLettersInTransit(): boolean {
    const owned = this.ownedLetterIds();
    return this.letters.some((letter: Letter): boolean =>
      LetterDelivery.isInTransit(letter, this.nowMs) ||
      (LetterDelivery.isWriting(letter) && owned.has(letter.id)));
  }

  /** 最新一封在路上的信（iOS latestInTransit）：见 this.transitLetter
   *  （reload 时备好的快照，「邮戳 + 在路上」拿它渲染） */

  /** 勾上的那几篇（状态行「一篇都没勾」要区分） */
  private checkedCount(candidates: JournalEntry[]): number {
    let n = 0;
    for (const entry of candidates) {
      if (!this.excluded.has(entry.id)) {
        n++;
      }
    }
    return n;
  }

  /** 状态行文案（R-POST-06 八种情况；带笔友名的走资源参数 %s） */
  private statusLabel(): ResourceStr {
    // 5.6 投信动画中钉住「点邮筒…」：信还没进邮筒不说「在路上」，版式不跳
    if (this.posting !== undefined) {
      return $r('app.string.s_ae7b18f8be', this.penPalName);
    }
    const state = this.state();
    switch (state.kind) {
      case PostBoxSituationKind.Returned:
        return $r('app.string.s_3b849347c8');
      case PostBoxSituationKind.NotLoggedIn:
        return $r('app.string.s_6b3f21b5dd', this.penPalName);
      case PostBoxSituationKind.JustPosted:
        return state.candidates.length === 0
          ? $r('app.string.s_b2e8e82a2a')
          : $r('app.string.s_e2322d97a3');
      case PostBoxSituationKind.Blocked:
        return this.rhythmLabel();
      case PostBoxSituationKind.Ready:
        return this.checkedCount(state.candidates) === 0
          ? $r('app.string.s_7d8e819a4b')
          : $r('app.string.s_ae7b18f8be', this.penPalName);
      case PostBoxSituationKind.InTransit:
        return $r('app.string.s_ce8689ed1e');
      case PostBoxSituationKind.NothingNew:
        return $r('app.string.s_8b365db6c9');
      default:
        return $r('app.string.s_dc36d11a9a');
    }
  }

  /** 服务端拦着时提前说清楚（R-POST-12）；不用「额度 / 剩余 N 封」这类计量词（定价文档 §5.1） */
  private rhythmLabel(): ResourceStr {
    if (this.rhythm === undefined) {
      return $r('app.string.s_589be40a92', this.penPalName);
    }
    switch (this.rhythm.reason) {
      case 'daily_cap':
        return $r('app.string.s_c2b46a7849');
      case 'monthly_cap':
        return $r('app.string.s_cd2db65a0a', this.penPalName);
      case 'welcome_pending':
        return $r('app.string.s_524e22ba8d', this.penPalName);
      default:
        return $r('app.string.s_589be40a92', this.penPalName);
    }
  }

  private excludedIdsArray(): string[] {
    const ids: string[] = [];
    this.excluded.forEach((id: string): void => {
      ids.push(id);
    });
    return ids;
  }

  // ---- 投信（R-POST-07；点邮筒触发）----

  /** 点邮筒（iOS tapMailbox）：不是 Ready / 一篇都没勾就不收——状态行已写明原因 */
  private tapMailbox(): void {
    // 正在投 / 正在落库：忽略连点（投进去就算寄出，不会寄出第二封）
    if (this.posting !== undefined || this.postingUnderway) {
      return;
    }
    // 点下立刻给一记扎实的（真机反馈「点击震感弱」：投信编排要等异步落库后才起，
    // 这一下让手指马上有回音；拒收也同款，原因在状态行里写着）
    this.postingFeel.playMailboxTap();
    const state = this.state();
    if (state.kind !== PostBoxSituationKind.Ready) {
      return;
    }
    const checked: JournalEntry[] = [];
    for (const entry of state.candidates) {
      if (!this.excluded.has(entry.id)) {
        checked.push(entry);
      }
    }
    if (checked.length === 0) {
      return;
    }
    this.post(checked, outgoingItemsOf(state.candidates), this.excludedIdsArray());
  }

  /**
   * 投信：先落一封「写信中」的信（R-POST-07 字段口径），交给寄信队列后台寄；
   * 落库成功才起 5.6 投信动画（约 3 秒，那叠日记飞进投信口）。落库失败弹提示，
   * 别的不动。通知授权挪到动画放完（R-POST-09：弹窗不压在动画上）。
   */
  private post(checked: JournalEntry[], items: OutgoingItem[], excludedIds: string[]): void {
    const store = this.store;
    const outbox = this.env.outbox;
    if (store === undefined || outbox === undefined) {
      return;
    }
    this.postingUnderway = true;
    // 点下邮筒的这一刻 = 寄出时刻，到达时刻从这里起算
    const sentAt = Date.now();
    const letter = new Letter(generateUuid(), sentAt, Date.now());
    letter.status = LetterStatus.Generating;
    letter.body = '';
    letter.fromCharacter = this.penPalName;
    // 写信当刻的昵称快照；没登录 / 没设昵称时缺省，抬头退回只写「致」
    const session = this.env.session;
    if (session !== undefined) {
      const user = session.user;
      if (user !== null && user.displayName.length > 0) {
        letter.toName = user.displayName;
      }
    }
    letter.triggerKind = LetterTriggerKind.Weekly;
    // 信纸在寄出这一刻定下（会员火漆信 6.x 接上即生效；当前恒普通信）
    letter.stationery = letterStationery(false);
    letter.deliveredAt = LetterDelivery.arrivalDate(sentAt, LetterDelivery.debugTimeScale(), Math.random);
    const entryIds: string[] = [];
    for (const entry of checked) {
      entryIds.push(entry.id);
    }
    const save = async (): Promise<void> => {
      try {
        await LetterRepository.saveLetter(store, letter);
        await LetterRepository.linkLetterEntries(store, letter.id, entryIds);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'post letter failed: %{public}s', JSON.stringify(err));
        this.postingUnderway = false;
        this.presentErrorText($r('app.string.s_7744960f42'));
        return;
      }
      // 投进去就算寄出：交给本机队列，清掉勾选，立刻试寄一轮
      outbox.enqueue(letter.id);
      this.excluded = new Set<string>();
      this.reload();
      // 5.6 投信动画（items/excludedIds 是点邮筒那一刻的快照，动画里要画）。
      // 几何量不出来（初次布局未完成等）信照寄，动画跳过直接收尾
      this.beginPosting(items, excludedIds);
      outbox.process().catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'process outbox failed: %{public}s', JSON.stringify(err));
      });
    };
    save();
  }

  /**
   * 5.6 投信动画起飞：量邮筒 / 叠纸的几何 → 快照进 PostingRun →
   * 起逐帧驱动（iOS beginPostingFlight；页面坐标 = 窗口坐标，沉浸满窗）。
   */
  private beginPosting(items: OutgoingItem[], excludedIds: string[]): void {
    const ui = this.getUIContext();
    const mailboxRect = ui.getComponentUtils().getRectangleById('postboxMailboxImage');
    const pileRectInfo = ui.getComponentUtils().getRectangleById('postboxPile');
    if (mailboxRect.size.width <= 0 || mailboxRect.size.height <= 0 ||
      pileRectInfo.size.width <= 0 || pileRectInfo.size.height <= 0) {
      // 邮筒 / 叠纸还没量出来（初次布局未完成等）：信照寄，动画跳过直接收尾
      hilog.warn(DOMAIN, TAG,
        'posting geometry missing, skip animation: mailbox=%{public}f pile=%{public}f',
        mailboxRect.size.width, pileRectInfo.size.width);
      this.finishPosting();
      return;
    }
    // 排雷（官方 API 参考实证）：getRectangleById 的 size / windowOffset 单位是 px，
    // 飞行层的 position/width/height 全按 vp 算——不转的话整个动画画到 3 倍屏外，
    // 真机表现是「displaySync 在跑、画面纹丝不动」。在这里一次转清，纯逻辑层照旧全 vp。
    const mailboxDrawn = fitRectInRect({
      x: ui.px2vp(mailboxRect.windowOffset.x),
      y: ui.px2vp(mailboxRect.windowOffset.y),
      width: ui.px2vp(mailboxRect.size.width),
      height: ui.px2vp(mailboxRect.size.height)
    }, MAILBOX_IMAGE_ASPECT);
    this.postingSlotRect = slotRectOf(mailboxDrawn);
    this.postingPileRect = {
      x: ui.px2vp(pileRectInfo.windowOffset.x),
      y: ui.px2vp(pileRectInfo.windowOffset.y),
      width: ui.px2vp(pileRectInfo.size.width),
      height: ui.px2vp(pileRectInfo.size.height)
    };
    // 真机排障：float 参数会被 hilog 隐私打码（}f），先拼进字符串再打
    const slot = this.postingSlotRect;
    const pile = this.postingPileRect;
    hilog.info(DOMAIN, TAG,
      'posting flight begin, slot=(%{public}s,%{public}s,%{public}s,%{public}s) pile=(%{public}s,%{public}s,%{public}s,%{public}s)',
      slot.x.toFixed(1), slot.y.toFixed(1), slot.width.toFixed(1), slot.height.toFixed(1),
      pile.x.toFixed(1), pile.y.toFixed(1), pile.width.toFixed(1), pile.height.toFixed(1));
    const session = this.env.session;
    const displayName = session !== undefined && session.user !== null
      ? session.user.displayName : undefined;
    // 会员火漆信是 6.x，现在投的都是普通封口；火漆管道先铺好
    const hasSeal = false;
    this.posting = new PostingRun(items, excludedIds, hasSeal, PostingRun.sealMarkOf(displayName));
    this.postingT = 0;
    this.postingStartNs = -1;
    this.postingFeel.play(hasSeal);
    // 排雷（displaySync 文档实证）：start 在异步回调里调用会拿错 UI 上下文，
    // 回调一帧都不来（真机「点了没动画」的根因）——必须 runScopedTask
    // 把 start 绑回当前 UI 上下文
    ui.runScopedTask((): void => {
      const sync = displaySync.create();
      const callback = (info: displaySync.IntervalInfo): void => {
        this.advancePosting(info.timestamp);
      };
      sync.on('frame', callback);
      sync.start();
      this.postingSync = sync;
      this.postingFrameCallback = callback;
    });
  }

  /** 逐帧推进（displaySync 回调，UI 主线程；timestamp 是开机起单调 ns） */
  private advancePosting(timestampNs: number): void {
    if (this.posting === undefined) {
      return;
    }
    if (this.postingStartNs < 0) {
      this.postingStartNs = timestampNs;
    }
    const t = (timestampNs - this.postingStartNs) / 1000000000;
    if (t >= LetterPostingTimeline.TOTAL) {
      this.postingT = LetterPostingTimeline.TOTAL;
      this.finishPosting();
      return;
    }
    this.postingT = t;
  }

  /** 动画放完（或跳过）：停驱动、清状态、这时候才申请通知授权（R-POST-09） */
  private finishPosting(): void {
    this.stopPostingSync();
    // 正常放完（翻板已落）：2.91s 起的「余震」让它自己响完再自然停（iOS 也
    // 从不中途 stop 编排）；只有提前跳过（几何量不到）才把震动掐掉
    if (this.postingT < LetterPostingTimeline.FLAP_FALL_END) {
      this.postingFeel.cancel();
    }
    hilog.info(DOMAIN, TAG, 'posting flight finished, t=%{public}f', this.postingT);
    this.posting = undefined;
    this.postingT = 0;
    this.postingUnderway = false;
    // 5.4（R-NOTIFY-02）：第一次投信动画放完才申请——回信到了才通知得到；
    // 已授权直接过，拒过不反复弹，失败不拦投信
    const notifications = this.env.notifications;
    if (notifications !== undefined) {
      notifications.requestAuthorizationIfNeeded().catch((): void => {
        // 申请失败（未登录弹窗异常等）：下次投信再试，不打扰用户
      });
    }
  }

  private stopPostingSync(): void {
    const sync = this.postingSync;
    if (sync !== undefined) {
      sync.stop();
      if (this.postingFrameCallback !== undefined) {
        sync.off('frame', this.postingFrameCallback);
      }
    }
    this.postingSync = undefined;
    this.postingFrameCallback = undefined;
    this.postingStartNs = -1;
  }

  /** 邮戳「在路上」的淡出进度：信进了邮筒（翻板落回）才亮（和几何层 revealOpacity 同一条曲线） */
  private postingReveal(): number {
    return LetterPostingTimeline.smooth(this.postingT,
      LetterPostingTimeline.FLAP_FALL_START, LetterPostingTimeline.TOTAL);
  }

  /** 略大一点落定（和几何层 revealScale 同一条曲线） */
  private postingRevealScale(): number {
    return 1 + 0.05 * (1 - this.postingReveal());
  }

  /** 重新寄出（R-POST-11）：失败计数清零，队列立刻接着跑 */
  private resendReturned(letter: Letter): void {
    const outbox = this.env.outbox;
    if (outbox === undefined) {
      return;
    }
    outbox.resend(letter.id)
      .then((): void => {
        this.reload();
      })
      .catch((err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'resend letter failed: %{public}s', JSON.stringify(err));
        this.presentErrorText($r('app.string.s_7744960f42'));
      });
  }

  /** 不寄了（R-POST-11）：带着的日记放回「要寄的日记」，记录留着不删 */
  private discardReturned(letter: Letter): void {
    const outbox = this.env.outbox;
    if (outbox === undefined) {
      return;
    }
    outbox.discard(letter.id)
      .then((): void => {
        this.reload();
      })
      .catch((err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'discard letter failed: %{public}s', JSON.stringify(err));
        this.presentErrorText($r('app.string.s_b6c0279a8a'));
      });
  }

  /** Resource → string（resourceManager 同步取），Toast 用 */
  private presentErrorText(res: Resource): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.env.errors.present(context.resourceManager.getStringSync(res.id), ErrorToastKind.Error);
  }

  build() {
    Navigation(this.navPathStack) {
      Stack() {
      // 版式对齐 iOS PostBoxPage：VStack(spacing 14)，上邮筒插画、中状态行、
      // 下固定高叠纸。所有尺寸走 PostBoxMetrics（跨机型/形态，单测覆盖）：
      // 叠纸≈窗高 22%（iOS 188/852）、邮筒墨迹宽≈屏宽 37.9%（iOS 同比）、
      // 顶距 = 安全区顶 + 70（dome 下移到信箱入口行之下，iOS 导航区观感）、
      // 状态行 caption 字号 + 矮行高。真机实证（PROGRESS 5.2 排雷）：
      // 关键几何只走容器 padding / 固定高 / layoutWeight / constraintSize，
      // 不碰 overlay 带子闭包、width('100%') 节点的 margin、Image 的 padding
      Column({ space: 14 }) {
        // 第一节 = 页首行 + 邮筒插画（内层不再加间距，几何自管）：
        // 页首行只有右上「信箱」入口（官方 Button），位置对齐首页大屏页首的
        // 「+」——顶 = 安全区顶 + 28、右 20（HomeView showcaseHeaderRow
        // 同款几何）；入口高 32 + 底距 10 = 行高 70，插画顶 = 安全区顶
        // + 70，与原版式逐像素一致（dome 位置不动）
        Column() {
          Row() {
            this.letterboxEntry()
          }
          .justifyContent(FlexAlign.End)
          .width('100%')
          .padding({ top: 28, right: 20, bottom: 10 })

          // 邮筒插画（本身就是按钮；点邮筒投信是 5.3，本卡不挂动作）。
          // 插画已裁掉奶油边（dome ≈ 区顶）；行内 @Builder 调用渲染
          // （排雷 a：overlay 挂带子闭包的 @Builder 不渲染）。
          // 2026-11-04 用户反馈整体下移一点：offset 14vp 往下坐（不放大
          // ——图是实底，放大必裁切或盖住状态行，用户拍板不裁）；14vp
          // 恰好被插画与状态行的 space 14 吃掉，图底贴状态行框顶不遮字；
          // 投信动画量的是本 Image 的窗口矩形（getRectangleById 含
          // offset），dome 下移后投信口换算自动跟随
          Stack({ alignContent: Alignment.TopEnd }) {
            Image(this.theme.mailboxImage)
              .objectFit(ImageFit.Contain)
              .width('100%')
              .height('100%')
              .offset({ y: 14 })
              // 5.6：点邮筒那一刻量这块的窗口矩形（contain 后按 588:1410
              // 算投信口在图上的位置），量不到动画跳过
              .id('postboxMailboxImage')
              .onClick((): void => {
                this.tapMailbox();
              })
          }
          .layoutWeight(1)
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .constraintSize({ maxWidth: this.metrics().contentMaxWidthVp })

        // 中间：状态行（R-POST-06；用户定：caption 字号、矮行高，换文案不跳版）
        Text(this.statusLabel())
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textSecondary)
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .constraintSize({
            minHeight: this.metrics().statusMinHeightVp,
            maxWidth: this.metrics().contentMaxWidthVp
          })
          .margin({ left: 32, right: 32 })

        // 下面：固定高度叠纸（度量恒定，5.3 投信动画要从这叠纸飞到投信口，
        // 高度不能变）。横向 28vp 内缩（iOS 同款）走 padding（排雷 b）。
        // 内容垂直居中（iOS ZStack{Color.clear; bottom} 同款：叠纸满高无感，
        // 邮戳 / 退回卡不满高时居中不贴顶）
        Column() {
          this.bottomArea()
        }
        .height(this.metrics().pileHeightVp)
        .padding({ left: 28, right: 28 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .constraintSize({ maxWidth: this.metrics().contentMaxWidthVp })
      }
      .width('100%')
      .height('100%')
      .padding({
        // 顶 = 安全区顶（页首行从这里起排，「信箱」入口再 +28 对齐首页「+」）；
        // 底 = 安全区底 + 102（叠纸底与悬浮胶囊 Tab 栏之间留出缝隙，
        // 用户定）。真机实证（排雷 d）：这层 padding 从窗口顶 y=0 量起，
        // 度量里的值已含安全区，直接用、不再自己加
        top: this.metrics().safeTopVp,
        bottom: this.metrics().bottomOffsetVp
      })

      // 5.6 投信动画：全页覆盖层（自己不响应点击），盖在正文上。
      // 几何是窗口坐标（沉浸满窗页面坐标 = 窗口坐标），这里原样落位
      if (this.posting !== undefined) {
        LetterPostingFlight({
          t: this.postingT,
          run: this.posting,
          palette: this.palette(),
          pileRect: this.postingPileRect,
          slotRect: this.postingSlotRect,
          totalHeightVp: this.metrics().pileHeightVp,
          headerHeightVp: this.metrics().pileHeaderHeightVp,
          rowHeightVp: this.metrics().pileRowHeightVp,
          fadeHeightVp: this.metrics().pileFadeHeightVp
        })
      }
      }
    }
    .mode(NavigationMode.Stack)
    .backgroundColor(this.pageColor !== undefined ? this.pageColor : this.theme.background)
  }

  /** 右上角信箱入口：官方 Button（Capsule 胶囊，缩小版）+ inbox 图标
   *  （sys.symbol 无 tray，inbox 收件箱托盘语义一致）+ 文字 + 未读红点
   *  （destructive）。轮廓成型走主题玻璃 token（glassBackground +
   *  0.5vp glassBorder，信箱页返回圆钮同款；token 每主题单独调过「与
   *  页面背景拉开一档明度差」——2026-11-04 真机反馈透明按钮看不清轮廓
   *  后定稿）。有未读回信红点就亮（R-POST-09）。定位由外层页首行管
   *  （顶 = 安全区 + 28、右 20） */
  @Builder
  letterboxEntry() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.inbox'))
          .fontSize(16)
          .fontColor([this.theme.textPrimary])
        Text($r('app.string.s_44fd049d7d'))
          .fontSize(12)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textPrimary)
      }
      // 红点跟 iOS 同款挂法（PostBoxView letterboxButton）：overlay 在
      // 内容框（图标 + 文字的 Row）右上角，向右上探出——iOS 8pt 点 offset
      // (6, -4)，本处 6vp 点等比 (4.5, -3)。探出量吃进按钮右 padding 14 /
      // 上下留白里，点始终收在按钮框内（2026-11-04 真机反馈：收进按钮后
      // 悬在空白处「位置怪」——根因是挂在按钮外框而不是内容框上）
      .overlay(this.unreadDot(), { align: Alignment.TopEnd })
    }
    .height(32)
    .padding({ left: 12, right: 14 })
    .backgroundColor(this.theme.glassBackground)
    .border({ width: 0.5, color: this.theme.glassBorder })
    .onClick((): void => {
      // 返回后的重查不靠 onPop（侧滑返回不触发 onPop，真机复现：读完信
      // 侧滑回来红点不灭），靠信箱页 NavDestination onDisappear bump
      // STORAGE_KEY_POSTBOX_VISIBLE_TICK（见 LetterboxView）
      this.navPathStack.pushPathByName('Letterbox', '');
    })
  }

  /** 信箱入口的未读红点：有已到未读才亮（destructive——accent 在部分主题
   *  是墨色会看成黑点），6vp（2026-11-04 真机反馈缩小后定稿） */
  @Builder
  unreadDot() {
    if (hasUnreadLetter(this.letters, this.nowMs)) {
      Circle()
        .fill(this.theme.destructive)
        .width(6)
        .height(6)
        .offset({ x: 4.5, y: -3 })
    }
  }

  /** 下面那块（固定高度）：投信动画中 / 退回卡片 / 能寄出纸 / 服务端拦着半透明摆纸 */
  @Builder
  private bottomArea() {
    if (this.posting !== undefined) {
      // 5.6 投信动画中：那叠日记的活身在覆盖层里演快照，下面这块只剩
      // 邮戳「在路上」，等信进了邮筒（翻板落回）才淡出来、略大一点落定
      // （R-POST-08；reload 一落地 transitLetter 就是刚寄的这封）
      Column() {
        this.inTransitNote()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .opacity(this.postingReveal())
      .scale({ x: this.postingRevealScale(), y: this.postingRevealScale() })
    } else if (this.state().kind === PostBoxSituationKind.Returned) {
      this.returnedCard(this.state().returnedLetter)
    } else if (this.state().kind === PostBoxSituationKind.Ready) {
      OutgoingPile({
        palette: this.palette(),
        items: outgoingItemsOf(this.state().candidates),
        excludedIds: this.excludedIdsArray(),
        interactive: true,
        totalHeightVp: this.metrics().pileHeightVp,
        headerHeightVp: this.metrics().pileHeaderHeightVp,
        rowHeightVp: this.metrics().pileRowHeightVp,
        fadeHeightVp: this.metrics().pileFadeHeightVp,
        onToggle: (id: string): void => {
          const next = new Set<string>(this.excluded);
          if (next.has(id)) {
            next.delete(id);
          } else {
            next.add(id);
          }
          this.excluded = next;
        }
      })
      .width('100%')
      // 5.6：投信动画起飞那一刻量这叠纸的窗口矩形（动画里画它的快照）
      .id('postboxPile')
    } else if (this.state().kind === PostBoxSituationKind.Blocked &&
      !this.hasLettersInTransit() && this.state().candidates.length > 0) {
      // 这周寄不了，新写的先摆着，下次一起寄（只是画，不能勾）
      OutgoingPile({
        palette: this.palette(),
        items: outgoingItemsOf(this.state().candidates),
        excludedIds: this.excludedIdsArray(),
        interactive: false,
        totalHeightVp: this.metrics().pileHeightVp,
        headerHeightVp: this.metrics().pileHeaderHeightVp,
        rowHeightVp: this.metrics().pileRowHeightVp,
        fadeHeightVp: this.metrics().pileFadeHeightVp
      })
      .width('100%')
      .opacity(0.5)
    } else {
      // 其余状况：最新一封在路上的信盖一枚邮戳 +「在路上」（iOS default 分支同款）；
      // 没有在途信（没新日记 / 一篇都没有 / 没登录）下面就是空的
      this.inTransitNote()
    }
  }

  /**
   * 邮戳 + 在路上（R-POST-07 寄出后的下半区；iOS PostBoxNotes.InTransitNote 权威）：
   * 一枚日戳（寄出日期 + 地点弧排）+「X 寄出」+「在路上」胶囊 +
   * 「回信会在三天内寄到你的信箱」。投信动画（那叠日记飞进投信口）是 5.6，
   * 这里先静态摆上，别让下半区空着一块。
   * 无参、只读 @State（transitLetter 一族 reload 时备好）：@Builder 表达式
   * 传参不随状态刷新（见字段注释），按值传 letter 会永远停在首渲染的 undefined。
   */
  @Builder
  private inTransitNote() {
    if (this.transitLetter !== undefined) {
      Row({ space: 20 }) {
        Postmark({
          dateMs: this.transitLetter.generatedAt,
          place: this.transitPlace,
          ink: postmarkInkHex(this.theme.id),
          stampSizeVp: 86
        })
        Column({ space: 8 }) {
          Text($r('app.string.s_87363c0bec',
            shortDate(new Date(this.transitLetter.generatedAt), this.appLanguage)))
            .fontSize(this.theme.bodyFont.size)
            .fontWeight(this.theme.bodyFont.weight)
            .fontFamily(this.theme.bodyFont.family)
            .fontColor(this.theme.textPrimary)
            .maxLines(1)
          Row({ space: 6 }) {
            Text($r('app.string.s_ff0e280d48'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(postmarkInkHex(this.theme.id))
              .padding({ left: 7, right: 7, top: 2.5, bottom: 2.5 })
              .borderRadius(12)
              .border({
                width: 0.8,
                color: postmarkInkHex(this.theme.id)
              })
            if (this.transitHasOthers) {
              Text($r('app.string.s_a2917545f5'))
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textTertiary)
                .maxLines(1)
            }
          }
          Text($r('app.string.s_54e712fa52'))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textSecondary)
            .maxLines(2)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
    }
  }

  /**
   * 退回卡片（R-POST-11；iOS PostBoxNotes.ReturnedLetterCard 权威）：
   * 「退回」长方戳盖歪一点 + 标题（寄出日期）+ 原因（退回那一刻的语言快照）
   * + 重新寄出 / 不寄了。信纸底色按主题信纸（palette.paper）。
   */
  @Builder
  private returnedCard(letter: Letter | undefined) {
    if (letter !== undefined) {
      Row({ space: 16 }) {
      // 「退回」戳：盖歪 −8°（iOS rotationEffect 同款）
      Text($r('app.string.s_607cd976d2'))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .letterSpacing(2)
        .fontColor(this.palette().ink)
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .borderRadius(3)
        .border({
          width: 1.6,
          color: this.palette().ink
        })
        .rotate({ angle: -8 })
        .opacity(0.85)
        .margin({ top: 2 })
      Column({ space: 6 }) {
        Text($r('app.string.s_1c89ce16cb',
          shortDate(new Date(letter.generatedAt), this.appLanguage)))
          .fontSize(15)
          .fontColor(this.palette().ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (letter.errorMessage !== undefined && letter.errorMessage.length > 0) {
          Text(letter.errorMessage)
            .fontSize(12)
            .fontColor(this.palette().ink)
            .opacity(0.6)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Row({ space: 22 }) {
          Text($r('app.string.s_6ec8fe27cd'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().liner)
            .onClick((): void => {
              this.resendReturned(letter);
            })
          Text($r('app.string.s_89345cda95'))
            .fontSize(14)
            .fontColor(this.palette().ink)
            .opacity(0.5)
            .onClick((): void => {
              this.discardReturned(letter);
            })
        }
        .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')
      .padding(18)
      .backgroundColor(this.palette().paper)
      .shadow({ radius: 2, color: 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 1 })
    }
  }
}
