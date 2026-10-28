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
 * - 点邮筒投信是 5.3；退回卡片 / 在路上的邮戳卡是 5.6 —— 本卡不碰
 * - 「此刻」每 5 秒推进（R-BOX-02）：在路上的信到点，右上角红点自己亮
 * - 切到本 tab / 登录态变化才重查（MainTabsView onChange 写
 *   STORAGE_KEY_POSTBOX_VISIBLE_TICK 驱动；tab 内容常驻不重建）
 * - 标题栏：左上不出「邮筒」二字（用户拍板，iOS 同款无标题），
 *   右上角「信箱」入口带未读红点（红色用 destructive——accent 在部分
 *   主题是墨色会看成黑点）
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
import { AppPrefs, PREF_KEY_PEN_PAL_NAME } from '../../services/AppPrefs';
import { STORAGE_KEY_LETTER_OUTBOX_TICK } from '../../services/LetterOutboxService';
import { mailboxPageColor } from '../../services/MailboxPageColor';
import {
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_WINDOW_HEIGHT_VP
} from '../../services/ImmersiveChrome';
import { LetterPalette } from './LetterPalette';
import { OutgoingPile } from './OutgoingPile';
import { Postmark } from './Postmark';
import { PostBoxMetrics } from './PostBoxMetrics';

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

  aboutToAppear(): void {
    this.penPalName = AppPrefs.getString(PREF_KEY_PEN_PAL_NAME, '青鸟');
    this.nowTimerId = setInterval((): void => {
      this.nowMs = Date.now();
    }, NOW_TICK_INTERVAL_MS);
    this.loadPageColor();
    this.reload();
  }

  aboutToDisappear(): void {
    if (this.nowTimerId >= 0) {
      clearInterval(this.nowTimerId);
      this.nowTimerId = -1;
    }
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
    this.post(checked);
  }

  /**
   * 投信：先落一封「写信中」的信（R-POST-07 字段口径），交给寄信队列后台寄。
   * 投信动画 / 邮戳是 5.6，本卡点完即落库。落库失败弹提示，别的不动。
   */
  private post(checked: JournalEntry[]): void {
    const store = this.store;
    const outbox = this.env.outbox;
    if (store === undefined || outbox === undefined) {
      return;
    }
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
    letter.deliveredAt = LetterDelivery.arrivalDate(sentAt, 1, Math.random);
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
        this.presentErrorText($r('app.string.s_7744960f42'));
        return;
      }
      // 投进去就算寄出：交给本机队列，清掉勾选，立刻试寄一轮
      outbox.enqueue(letter.id);
      this.excluded = new Set<string>();
      this.reload();
      outbox.process().catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'process outbox failed: %{public}s', JSON.stringify(err));
      });
    };
    save();
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
      // 版式对齐 iOS PostBoxPage：VStack(spacing 14)，上邮筒插画、中状态行、
      // 下固定高叠纸。所有尺寸走 PostBoxMetrics（跨机型/形态，单测覆盖）：
      // 叠纸≈窗高 22%（iOS 188/852）、邮筒墨迹宽≈屏宽 37.9%（iOS 同比）、
      // 顶距 = 安全区顶 + 70（dome 下移到信箱入口行之下，iOS 导航区观感）、
      // 状态行 caption 字号 + 矮行高。真机实证（PROGRESS 5.2 排雷）：
      // 关键几何只走容器 padding / 固定高 / layoutWeight / constraintSize，
      // 不碰 overlay 带子闭包、width('100%') 节点的 margin、Image 的 padding
      Column({ space: 14 }) {
        // 上面：邮筒插画（本身就是按钮；点邮筒投信是 5.3，本卡不挂动作）。
        // 插画已裁掉奶油边（dome ≈ 区顶），信箱入口与插画同层 Stack、
        // 行内 @Builder 调用渲染（排雷 a：overlay 挂带子闭包的 @Builder 不渲染）
        Stack({ alignContent: Alignment.TopEnd }) {
          Image(this.theme.mailboxImage)
            .objectFit(ImageFit.Contain)
            .width('100%')
            .height('100%')
            .onClick((): void => {
              this.tapMailbox();
            })
          this.letterboxEntry()
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
        // 顶/底全走度量：顶 = 安全区顶 + 70（dome 移到信箱入口行之下），
        // 底 = 安全区底 + 102（叠纸底与悬浮胶囊 Tab 栏之间留出缝隙，
        // 用户定）。真机实证（排雷 d）：这层 padding 从窗口顶 y=0 量起，
        // 度量里的 topOffset 已含安全区顶，直接用、不再自己加
        top: this.metrics().topOffsetVp,
        bottom: this.metrics().bottomOffsetVp
      })
    }
    .mode(NavigationMode.Stack)
    .backgroundColor(this.pageColor !== undefined ? this.pageColor : this.theme.background)
  }

  /** 右上角信箱入口：官方 SymbolGlyph 图标（sys.symbol 无 tray，inbox 收件箱托盘
   *   语义一致）+ 文字 + 未读红点（destructive）。有未读回信就亮（R-POST-09）。
   *   iOS toolbar topBarTrailing 同款；wrap 节点的 margin 真机正常（右侧 16vp） */
  @Builder
  letterboxEntry() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.inbox'))
          .fontSize(this.theme.captionFont.size)
          .fontColor([this.theme.textPrimary])
        Text($r('app.string.s_44fd049d7d'))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textPrimary)
      }
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .onClick((): void => {
        this.navPathStack.pushPathByName('Letterbox', '');
      })
      if (hasUnreadLetter(this.letters, this.nowMs)) {
        Circle()
          .fill(this.theme.destructive)
          .width(8)
          .height(8)
          .offset({ x: 6, y: 8 })
      }
    }
    .margin({ top: 8, right: 16 })
  }

  /** 下面那块（固定高度）：退回卡片 / 能寄出纸 / 服务端拦着半透明摆纸 */
  @Builder
  private bottomArea() {
    if (this.state().kind === PostBoxSituationKind.Returned) {
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
