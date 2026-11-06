/**
 * 来信详情（10_BUILD_MANUAL.md 5.1 / 5.7）。对应 iOS `Views/PostBox/LetterDetailView.swift`。
 *
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
import { LengthMetrics } from '@kit.ArkUI';
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
import { dayAndWeekday } from '../../services/AppDateFormatters';
import { LetterPalette } from './LetterPalette';
import { SealedLetterOpener } from './SealedLetterOpener';
import { LetterStationery } from './LetterStationery';

const DOMAIN = 0x0000;
const TAG = 'LetterDetailView';

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
  private navPathStack: NavPathStack = new NavPathStack();
  private store: relationalStore.RdbStore | undefined = undefined;

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        if (this.letter !== undefined) {
          if (this.letter.isSealed) {
            // 火漆信：没拆过的是一枚封着的信封；拆完（或上次已拆过）摊开成信纸
            if (this.sealed) {
              this.sealedEnvelopeView(this.letter)
            } else {
              this.stationeryView(this.letter)
            }
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
