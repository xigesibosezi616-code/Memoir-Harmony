/**
 * 来信详情（普通信，10_BUILD_MANUAL.md 5.1）。对应 iOS `LetterDetailView.swift`。
 *
 * - 普通信**打开即已读**（R-BOX-04）：首次装载时 status → read 落库（只第一次有效）
 * - 信头「致{昵称快照}」（R-BOX-07）：整句交给译文排（致%s，R-LANG-07）；
 *   昵称是**寄出那一刻的快照**，不实时读当前昵称——改名字不连历史信一起变
 * - 正文一整段（开头、中段、结尾、签名都由服务端写好）
 * - 信末会员小字（R-BOX-08）：行先渲染占位；会员状态接入后只对非会员显示，
 *   点击开付费页等付费体系卡片接通
 * - 火漆信（5.7 拆信流程）：本卡先按普通信展示正文，但**不标已读**——
 *   拆信要打碎火漆那一刻才算（R-BOX-04），只看一眼就退出信还封着
 * - 路由：邮筒 tab 内 Navigation（router_map `LetterDetail`），参数 = 信 id
 */
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
import { dayAndWeekday } from '../../services/AppDateFormatters';

const DOMAIN = 0x0000;
const TAG = 'LetterDetailView';

/** 顶栏一行的高（返回圆钮 + 居中标题） */
const TOP_BAR_ROW_HEIGHT_VP: number = 44;

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
  private navPathStack: NavPathStack = new NavPathStack();
  private store: relationalStore.RdbStore | undefined = undefined;

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        if (this.letter !== undefined) {
          Scroll() {
            Column({ space: 24 }) {
              // 信头：寄出日子 + 抬头「致{昵称快照}」
              Column({ space: 6 }) {
                Text(dayAndWeekday(new Date(this.letter.generatedAt), this.appLanguage))
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
              Text(this.letter.body)
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
   * 普通信打开即已读（R-BOX-04）；火漆信要打碎火漆那一刻才算（5.7 接），这里不标。
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
      if (!letter.isSealed && LetterDelivery.isUnread(letter, now)) {
        letter.status = LetterStatus.Read;
        letter.readAt = now;
        letter.updatedAt = now;
        await LetterRepository.saveLetter(this.store, letter);
      }
      this.letter = letter;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'load letter failed id=%{public}s: %{public}s',
        this.letterId, JSON.stringify(err));
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
    .width('100%')
    .padding({ top: 20 })
  }
}
