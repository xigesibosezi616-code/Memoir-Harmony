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
import { Letter } from '../../models/Letter';
import { JournalEntry } from '../../models/JournalEntry';
import { RhythmResponse } from '../../models/Api';
import {
  PostBoxSituationKind,
  PostBoxState,
  PostBoxStateInput,
  judgePostBoxState,
  outgoingItemsOf,
  hasUnreadLetter
} from '../../models/PostBoxLogic';
import { AppPrefs, PREF_KEY_PEN_PAL_NAME } from '../../services/AppPrefs';
import { mailboxPageColor } from '../../services/MailboxPageColor';
import { LetterPalette } from './LetterPalette';
import { OutgoingPile, OUTGOING_PILE_HEIGHT_VP } from './OutgoingPile';

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
  /** 登录 / 登出 / 注销后重查（登录状态影响节奏问询和状态行） */
  @StorageProp(STORAGE_KEY_SESSION_TICK) @Watch('reload') sessionTick: number = 0;
  /** 切到本 tab 时重查（别的 tab 里写了日记、寄了信，回来都要是最新的） */
  @StorageProp(STORAGE_KEY_POSTBOX_VISIBLE_TICK) @Watch('reload') visibleTick: number = 0;
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
        // 退回信里关联的日记不重新出现在候选里（R-POST-03）
        const bouncedIds: string[] = [];
        for (const letter of this.letters) {
          if (LetterDelivery.isBounced(letter)) {
            bouncedIds.push(letter.id);
          }
        }
        this.heldEntryIds = await LetterRepository.entryIdsForLetters(store, bouncedIds);
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
      this.heldEntryIds, this.rhythm, this.isLoggedIn(), this.nowMs));
  }

  /** 有信在路上（含写信中——对用户都算「在路上」；服务端拦着时下面半透明摆纸用） */
  private hasLettersInTransit(): boolean {
    return this.letters.some((letter: Letter): boolean =>
      LetterDelivery.isInTransit(letter, this.nowMs) || LetterDelivery.isWriting(letter));
  }

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

  build() {
    Navigation(this.navPathStack) {
      Column() {
        // 上面：邮筒插画（本身就是按钮；点邮筒投信是 5.3，本卡不挂动作）
        Column() {
          Image(this.theme.mailboxImage)
            .objectFit(ImageFit.Contain)
            .width('100%')
            .height('100%')
        }
        .layoutWeight(1)
        .padding({ left: 40, right: 40, top: 8 })

        // 中间：状态行（R-POST-06；最小高 40，换文案不跳版）
        Text(this.statusLabel())
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textSecondary)
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .constraintSize({ minHeight: 40 })
          .margin({ left: 32, right: 32, top: 14 })

        // 下面：固定高度（188vp）——5.3 投信动画要从这叠纸飞到投信口，高度不能变
        Column() {
          this.bottomArea()
        }
        .height(OUTGOING_PILE_HEIGHT_VP)
        .margin({ left: 28, right: 28, top: 14, bottom: 20 })
        .alignItems(HorizontalAlign.Center)
        .width('100%')
      }
      .width('100%')
      .height('100%')
    }
    .title(this.titleBar)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .backgroundColor(this.pageColor !== undefined ? this.pageColor : this.theme.background)
  }

  /** 标题栏：左端留空，右端「信箱」入口（带未读红点；红点用 destructive） */
  @Builder
  titleBar() {
    Row() {
      Blank()
      Stack({ alignContent: Alignment.TopEnd }) {
        Text($r('app.string.s_44fd049d7d'))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textPrimary)
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
    }
    .width('100%')
  }

  /** 下面那块（固定高度）：能寄出纸；服务端拦着且有新日记时半透明摆着（下次一起寄） */
  @Builder
  private bottomArea() {
    if (this.state().kind === PostBoxSituationKind.Ready) {
      OutgoingPile({
        palette: this.palette(),
        items: outgoingItemsOf(this.state().candidates),
        excludedIds: this.excludedIdsArray(),
        interactive: true,
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
        interactive: false
      })
      .width('100%')
      .opacity(0.5)
    }
  }
}
