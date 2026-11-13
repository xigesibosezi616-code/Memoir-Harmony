/**
 * 来信详情（10_BUILD_MANUAL.md 5.1 / 5.7）。对应 iOS `Views/PostBox/LetterDetailView.swift`。
 *
 * - 世界笔友的信（`penPalId` 非空，U01 读信规则 2026-10-16）：一张两面写字的信纸 ——
 *   正面是他用母语写的原文，翻过来是译文；危险的那封**正面直接是读信人的语言**，
 *   信纸下面再附一张求助卡片（`CrisisHelpCard`）。他的母语和你的语言相同时只有一面、
 *   不翻。信纸下面一行小字写明他是虚构的 AI 笔友。不写「致 XXX」—— 信里他自己会称呼你
 * - 普通信**打开即已读**（R-BOX-04）：首次装载时 status → read 落库（只第一次有效）
 * - 火漆信（尺素会员寄出的，见 `Letter.isSealed`）：没拆过的先是一枚封着的信封，
 *   一下一下拆开（`SealedLetterOpener`），**打碎火漆那一刻才算已读**；
 *   拆过的再打开直接是信纸（专属信纸 `LetterStationery`）。
 *   只看了一眼信封就退出去，信还封着 —— 和实物一样
 * - 信头「致{昵称快照}」（R-BOX-07）：整句交给译文排（致%s，R-LANG-07）；
 *   昵称是**寄出那一刻的快照**，不实时读当前昵称——改名字不连历史信一起变
 * - 信末会员小字（R-BOX-08）：行先渲染占位；会员状态接入后只对非会员显示，
 *   点击开付费页等付费体系卡片接通
 * - 路由：邮筒 tab 内 Navigation（router_map `LetterDetail`），参数 = 信 id
 */
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { relationalStore } from '@kit.ArkData';
import { LengthMetrics, MeasureText } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import {
  STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP
} from '../../services/ImmersiveChrome';
import { AppDatabase } from '../../data/Database';
import { LetterRepository } from '../../data/LetterRepository';
import { Letter, LetterStatus } from '../../models/Letter';
import { LetterDelivery } from '../../models/LetterDelivery';
import { LetterOpeningTimeline } from '../../models/LetterOpeningTimeline';
import { PostingRun } from '../../models/LetterPostingFlightGeometry';
import { LetterLanguage } from '../../models/LetterLanguage';
import { PenPalRoster } from '../../services/PenPalRoster';
import { dayAndWeekday } from '../../services/AppDateFormatters';
import { LetterPalette } from './LetterPalette';
import { SealedLetterOpener } from './SealedLetterOpener';
import { CrisisHelpCard } from './CrisisHelpCard';
import { LetterStationery, LINE_HEIGHT_VP } from './LetterStationery';

const DOMAIN = 0x0000;
const TAG = 'LetterDetailView';

/** '#RRGGBB' + 透明度 → '#AARRGGBB'（翻面按钮描边用，LetterStationery 同款） */
function withAlpha(hex: string, alpha01: number): string {
  const a = Math.round(Math.max(0, Math.min(1, alpha01)) * 255);
  const s = a.toString(16);
  return `#${s.length < 2 ? '0' : ''}${s}${hex.substring(1)}`;
}

/** 系统路由表入口（router_map.json → name `LetterDetail`）：信箱行推入 */
@Builder
export function LetterDetailBuilder() {
  LetterDetailView()
}

@Component
export struct LetterDetailView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  /** 路由参数：信 id（onReady 从 NavDestinationContext.pathInfo 取） */
  private letterId: string = '';
  @State private letter: Letter | undefined = undefined;
  /** 火漆信这次进来时还封着、还没拆完。进来那一刻定下，拆完变 false（iOS sealed） */
  @State private sealed: boolean = false;
  /** 世界笔友的信：现在看的是不是背面 */
  @State private showsBack: boolean = false;
  /** 翻面动画角度：前半程 0→90 收拢、90° 那一刻换面、后半程 90→0 展开（U01：0.6 秒不回弹） */
  @State private flipAngle: number = 0;
  /** 翻面动画进行中（连点不理，防打断换面时机） */
  private flipping: boolean = false;
  /** 两面同纸的信纸实测宽度（vp）：换纸宽（旋转屏 / 分屏）时重算补齐行数 */
  @State private paperWidthVp: number = 0;
  /** 两面各自的补齐空行数（字少的那面多画几格空行，两面一样大，U01 读信规则 3） */
  @State private frontBlankLines: number = 2;
  @State private backBlankLines: number = 2;
  /** 信头的地名（名册里这位的 place，按 App 语言取；名册里没有 = ''，只写信上的署名） */
  @State private senderPlace: string = '';
  private navPathStack: NavPathStack = new NavPathStack();
  private store: relationalStore.RdbStore | undefined = undefined;

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        if (this.letter !== undefined) {
          if (this.letter.isSealed && this.sealed) {
            this.sealedEnvelopeView(this.letter)
          } else if (this.isWorldLetter(this.letter)) {
            this.worldLetterView(this.letter)
          } else if (this.letter.isSealed) {
            this.stationeryView(this.letter)
          } else {
            this.plainLetterView(this.letter)
          }
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.safeAreaTopVp })
      .backgroundColor(this.theme.background)
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.background)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      // 信箱行 pushPathByName 传的是 string id；Record 分支兼容历史路由参数形态
      const raw = ctx.pathInfo.param as Record<string, Object> | string | undefined;
      if (typeof raw === 'string') {
        this.letterId = raw;
      } else if (raw !== undefined) {
        const id = raw['id'];
        if (typeof id === 'string') {
          this.letterId = id;
        }
      }
      this.loadLetter();
    })
  }

  // ---- 普通信（打开即已读，R-BOX-04） ----

  @Builder
  private plainLetterView(letter: Letter) {
    Scroll() {
      Column({ space: 24 }) {
        // 信头：寄出日子 + 抬头「致{昵称快照}」
        Column({ space: 6 }) {
          Text(dayAndWeekday(new Date(letter.generatedAt), this.appLanguage))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textTertiary)
            .letterSpacing(this.theme.letterSpacingWide)
          Text(this.salutation())
            .fontSize(this.theme.headingFont.size)
            .fontWeight(this.theme.headingFont.weight)
            .fontFamily(this.theme.headingFont.family)
            .fontColor(this.theme.textPrimary)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 8 })

        Divider()
          .strokeWidth(0.5)
          .color(this.theme.borderAccent)
          .width('100%')

        // 正文（已含开头 + 中段 + 结尾 + 签名——服务端写好）
        Text(letter.body)
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .lineSpacing(LengthMetrics.vp(10))
          .width('100%')

        this.memberHint()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: 28,
        right: 28,
        bottom: this.safeAreaBottomVp + 60
      })
    }
    // Scroll 高度受限后内容小于视口默认居中（官方 FAQ faqs-arkui-725）——显式顶对齐
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .layoutWeight(1)
  }

  // ---- 世界笔友的信（U01 读信规则，2026-10-16） ----

  /** 世界笔友写来的：penPalId 非空。自己起名的那位 penPalId 为空，照 v1 读信页不变 */
  private isWorldLetter(letter: Letter): boolean {
    return letter.penPalId !== undefined && letter.penPalId.length > 0;
  }

  /** 有没有译文。他的母语和你的语言相同（如西安的吴写给写中文的你）就只有原文一面 */
  private hasTranslation(letter: Letter): boolean {
    return letter.translatedBody !== undefined && letter.translatedBody.length > 0;
  }

  /** 危险的那封正面是译文（读信人的语言），平常正面是原文 */
  private frontIsTranslation(letter: Letter): boolean {
    return this.hasTranslation(letter) && letter.danger === true;
  }

  private frontText(letter: Letter): string {
    if (this.frontIsTranslation(letter)) {
      return letter.translatedBody ?? '';
    }
    return letter.body;
  }

  private backText(letter: Letter): string {
    if (this.frontIsTranslation(letter)) {
      return letter.body;
    }
    return letter.translatedBody ?? '';
  }

  /** 这封信是用哪种语言写给你的：有译文看译文，没有就看原文（和你的语言相同）。
   *  求助卡片按它选热线 —— 和服务端写进信里的那条一致 */
  private readerLanguage(letter: Letter): string {
    const text = this.hasTranslation(letter) ? (letter.translatedBody ?? '') : letter.body;
    return LetterLanguage.forLetter([text], this.appLanguage);
  }

  /** 信头「斯图尔特岛 · McRae」。名册里找不到这位（比如老版本没有的笔友）就只写信上的署名 */
  private worldSender(letter: Letter): string {
    if (this.senderPlace.length > 0) {
      return `${this.senderPlace} · ${letter.fromCharacter}`;
    }
    return letter.fromCharacter;
  }

  @Builder
  private worldLetterView(letter: Letter) {
    Scroll() {
      Column({ space: 18 }) {
        if (this.hasTranslation(letter)) {
          this.twoSidedSheet(letter)
        } else {
          // 他的母语和你的语言相同：只有一面，没有翻面按钮
          this.worldSide(letter, letter.body, 2)
        }
        if (letter.danger === true) {
          // 危险的那封：信纸下面固定附一张求助卡片（热线和信里写的一致）
          CrisisHelpCard({
            language: this.readerLanguage(letter),
            palette: LetterPalette.of(this.theme.id)
          })
            .margin({ top: 6 })
        }
        // 信末写明：他是虚构的 AI 笔友（产品定：名册、信末、隐私协议都写清）
        Text($r('app.string.s_13d655e2da', letter.fromCharacter))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textTertiary)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: this.safeAreaBottomVp + 60
      })
    }
    // Scroll 高度受限后内容小于视口默认居中（官方 FAQ faqs-arkui-725）——显式顶对齐
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .layoutWeight(1)
  }

  /** 两面写字的那张纸，下面是翻面的按钮（U01 读信规则 3） */
  @Builder
  private twoSidedSheet(letter: Letter) {
    Column() {
      if (!this.showsBack) {
        this.worldSide(letter, this.frontText(letter), this.frontBlankLines)
      } else {
        this.worldSide(letter, this.backText(letter), this.backBlankLines)
      }
    }
    .width('100%')
    // 绕竖轴翻面（iOS rotation3DEffect perspective 0.3 同款）
    .rotate({ y: 1, angle: this.flipAngle, perspective: 0.3 })
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const w = Math.round(Number(newArea.width) * 10) / 10;
      if (w !== this.paperWidthVp) {
        this.paperWidthVp = w;
        this.recomputeBlankLines();
      }
    })

    // 翻面：说清楚背面是什么（原文 / 译文），而不是一个光秃秃的「翻转」
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.textPrimary])
        Text(this.flipButtonTitle(letter))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.textPrimary)
      }
    }
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(Color.Transparent)
    .border({ width: 0.8, color: withAlpha(this.textPrimaryHex(), 0.4) })
    .onClick((): void => {
      this.flip();
    })
  }

  /** 信纸的一面。信头是寄信人（地名 · 姓）—— 世界笔友的信里自己会称呼你，不再写「致 XXX」 */
  @Builder
  private worldSide(letter: Letter, content: string, blankLines: number) {
    LetterStationery({
      palette: LetterPalette.of(this.theme.id),
      date: dayAndWeekday(new Date(letter.generatedAt), this.appLanguage),
      salutation: this.worldSender(letter),
      content: content,
      blankLines: blankLines
    })
  }

  /** 现在看的这面是原文 → 按钮写「看译文」；是译文 → 「看原文」 */
  private flipButtonTitle(letter: Letter): ResourceStr {
    if (this.showsBack === this.frontIsTranslation(letter)) {
      return $r('app.string.s_4494ba640a'); // 看译文
    }
    return $r('app.string.s_18cb8ddf9d'); // 看原文
  }

  /** theme.textPrimary（各主题实际是 0xAARRGGBB 数字色）→ '#RRGGBB'；不是数字退墨黑 */
  private textPrimaryHex(): string {
    const color = this.theme.textPrimary;
    if (typeof color === 'number') {
      return `#${(color & 0xFFFFFF).toString(16).padStart(6, '0')}`;
    }
    return '#000000';
  }

  /**
   * 把信纸翻过去：像拿起一张纸翻面 —— 平滑、不回弹（U01：0.6 秒缓入缓出，
   * 转到 90° 那一刻换面）。前半程收拢到 90°（EaseIn），换面，后半程展开（EaseOut）。
   * iOS 在系统「减弱动态效果」打开时直接换面；鸿蒙没有对应的公开系统设置，恒走动画
   */
  private flip(): void {
    if (this.flipping) {
      return;
    }
    this.flipping = true;
    this.getUIContext().keyframeAnimateTo({
      onFinish: (): void => {
        this.flipping = false;
      }
    }, [
      { duration: 300, curve: Curve.EaseIn, event: (): void => {
        this.flipAngle = 90;
      } },
      { duration: 300, curve: Curve.EaseOut, event: (): void => {
        // 90° 侧棱那一刻换面（之前看不见背面，之后看不见正面）；角度归零展开新面
        this.showsBack = !this.showsBack;
        this.flipAngle = 0;
      } }
    ]);
  }

  /**
   * 同一张纸两面一样大：字少的那一面多画几格空行（U01 读信规则 3）。
   * 两面的文字高度用 measure 离线量（和 LetterStationery 正文同参：serif / 15 / 行高 30），
   * 不依赖布局结果，不会和纸高互相反馈
   */
  private recomputeBlankLines(): void {
    const letter = this.letter;
    if (letter === undefined || !this.hasTranslation(letter) || this.paperWidthVp <= 0) {
      return;
    }
    // 正文区左右各留 28（LetterStationery 纸内边距），与量字宽一致
    const textWidth = this.paperWidthVp - 56;
    if (textWidth <= 0) {
      return;
    }
    const frontHeight = this.textHeightVp(this.frontText(letter), textWidth);
    const backHeight = this.textHeightVp(this.backText(letter), textWidth);
    const maxHeight = Math.max(frontHeight, backHeight);
    this.frontBlankLines = 2 + Math.max(0, Math.ceil((maxHeight - frontHeight) / LINE_HEIGHT_VP));
    this.backBlankLines = 2 + Math.max(0, Math.ceil((maxHeight - backHeight) / LINE_HEIGHT_VP));
  }

  /** 量这段字在 widthVp 宽里占多高（与 LetterStationery 正文渲染参数一致） */
  private textHeightVp(text: string, widthVp: number): number {
    const size: SizeOptions = MeasureText.measureTextSize({
      textContent: text,
      fontSize: 15,
      lineHeight: LINE_HEIGHT_VP,
      fontFamily: 'serif',
      constraintWidth: widthVp
    });
    return Number(size.height);
  }

  /** 名册里这位的地名（信头「地名 · 姓」用；取不到 / 名册里没有就只写信上的署名） */
  private async loadSenderPlace(letter: Letter): Promise<void> {
    const context = this.getUIContext().getHostContext();
    const id = letter.penPalId ?? '';
    if (context === undefined || id.length === 0) {
      return;
    }
    try {
      const penPal = await PenPalRoster.penPal(id, context);
      this.senderPlace = penPal !== null ? penPal.place.resolved(this.appLanguage) : '';
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'load penpal place failed id=%{public}s: %{public}s',
        id, JSON.stringify(err));
      this.senderPlace = '';
    }
  }

  // ---- 火漆信：封着的信封，一下一下拆开（R-BOX-05，5.7） ----

  @Builder
  private sealedEnvelopeView(letter: Letter) {
    SealedLetterOpener({
      palette: LetterPalette.of(this.theme.id),
      mark: PostingRun.sealMarkOf(letter.fromCharacter),
      sender: $r('app.string.s_d190c58094', letter.fromCharacter),
      onBroken: (): void => {
        // 第一下打碎火漆那一刻才算已读（R-BOX-04）
        this.markLetterRead();
      },
      onFinished: (): void => {
        // 信纸抽出来了，摊开成信纸（iOS unfold：easeInOut 0.55s）
        this.getUIContext().animateTo({
          duration: Math.round(LetterOpeningTimeline.UNFOLD_DURATION * 1000),
          curve: Curve.EaseInOut
        }, (): void => {
          this.sealed = false;
        });
      }
    })
    .width('100%')
    .layoutWeight(1)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 30 })))
  }

  // ---- 火漆信：摊开的专属信纸（字一行一格落在格线上，5.7） ----

  @Builder
  private stationeryView(letter: Letter) {
    Scroll() {
      Column() {
        LetterStationery({
          palette: LetterPalette.of(this.theme.id),
          date: dayAndWeekday(new Date(letter.generatedAt), this.appLanguage),
          salutation: this.salutation(),
          content: letter.body
        })
        // 会员小字居中一行（iOS stationery 的 VStack 默认居中；
        // 20 是 memberHint 自带的顶距，8 补齐 iOS 的 28）
        Row() {
          this.memberHint()
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 8 })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: this.safeAreaBottomVp + 60
      })
    }
    // Scroll 高度受限后内容小于视口默认居中（官方 FAQ faqs-arkui-725）——显式顶对齐
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .layoutWeight(1)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 16 })))
  }

  /** 抬头：有昵称快照「致%s」整句交给译文，没有退回光秃秃的「致」（R-BOX-07） */
  private salutation(): ResourceStr {
    const letter = this.letter;
    if (letter !== undefined && letter.toName !== undefined && letter.toName.length > 0) {
      return $r('app.string.s_71cfa4ee81', letter.toName);
    }
    return $r('app.string.s_b4a7bb16c0');
  }

  /**
   * 装载 + 标已读。
   * 普通信打开即已读（R-BOX-04）；火漆信要打碎火漆那一刻才算（onBroken 里调
   * `markLetterRead`），这里只定「这次进来还封不封着」。
   * 已读只记本地（R-BOX-10），不调服务端。
   */
  private async loadLetter(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined || this.letterId.length === 0) {
      return;
    }
    try {
      if (this.store === undefined) {
        this.store = await AppDatabase.open(context);
      }
      const letter = await LetterRepository.findLetter(this.store, this.letterId);
      if (letter === null) {
        // 查不到（理论不发生——从信箱行进）：留在空态，不出错提示
        return;
      }
      const now = Date.now();
      if (letter.isSealed) {
        // 拆过的再打开直接是信纸（R-BOX-04）；只看信封退出的仍封着
        this.sealed = LetterDelivery.isUnread(letter, now);
      } else if (LetterDelivery.isUnread(letter, now)) {
        this.markLetterRead(letter, now);
      }
      this.letter = letter;
      if (this.isWorldLetter(letter)) {
        // 信头「地名 · 姓」：名册里查这位的地名（查不到就只写署名）
        await this.loadSenderPlace(letter);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'load letter failed id=%{public}s: %{public}s',
        this.letterId, JSON.stringify(err));
    }
  }

  /** 标记已读（只第一次有效；写库失败不阻断阅读，下次进来再标） */
  private async markLetterRead(letter?: Letter, now?: number): Promise<void> {
    const target = letter !== undefined ? letter : this.letter;
    if (target === undefined) {
      return;
    }
    const at = now !== undefined ? now : Date.now();
    if (!LetterDelivery.isUnread(target, at)) {
      return;
    }
    target.status = LetterStatus.Read;
    target.readAt = at;
    target.updatedAt = at;
    if (this.store !== undefined) {
      try {
        await LetterRepository.saveLetter(this.store, target);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'mark letter read failed id=%{public}s: %{public}s',
          target.id, JSON.stringify(err));
      }
    }
  }

  // ---- 顶栏：返回圆钮 + 居中标题「来信」 ----

  @Builder
  private topBar() {
    Stack() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textPrimary])
        }
        .width(34)
        .height(34)
        .padding(0)
        .backgroundColor(this.theme.glassBackground)
        .border({ width: 0.5, color: this.theme.glassBorder })
        .onClick((): void => {
          this.navPathStack.pop();
        })
        Blank()
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text($r('app.string.s_0f47f66752'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textSecondary)
          .letterSpacing(this.theme.letterSpacingWide)
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      // 纯展示层全宽盖在按钮行上，触摸穿透给下面的返回钮
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(TOP_BAR_ROW_HEIGHT_VP)
    .margin({ bottom: TOP_BAR_CONTENT_GAP_VP })
  }

  // ---- 信末会员小字（R-BOX-08，入口先留） ----

  @Builder
  private memberHint() {
    // 刚被回应过是最心动的时刻——只一行小字，不弹窗、不打断读信（iOS 同款）。
    // 会员体系未接（后续卡）：先渲染行占位，会员状态接入后只对非会员显示；
    // 点击开付费页也等付费体系卡接通。
    Row({ space: 8 }) {
      Text($r('app.string.s_3bba23dbc1'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
      Text($r('app.string.s_cf9d76b498'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.accent)
    }
    .padding({ top: 20 })
  }
}
