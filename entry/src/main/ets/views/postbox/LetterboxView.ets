/**
 * 信箱（10_BUILD_MANUAL.md 5.1）。对应 iOS `Views/PostBox/LetterboxView.swift`。
 *
 * - 只显示**已到达**的信（R-BOX-01）：LetterDelivery.hasArrived 过滤、按到达时刻倒序；
 *   在路上的看不见，只要有一封在走就在卡片下补一行「有回信正在路上」
 * - 「此刻」每 5 秒推进一次（R-BOX-02）：页面开着时到点的信自己冒出来、红点自己亮
 * - 行 =「来自{笔友}」+ 到达日子 + 预览（R-BOX-03：火漆信没拆不露预览）+ 未读红点；
 *   信箱里显示的是**收到的日子**（到达时刻），不是寄出日子（iOS 同款）
 * - 空态「信箱还是空的」；到点的信由 onShown 全量重查 + nowMs 推进双驱动
 * - 路由：邮筒 tab 内 Navigation（router_map `Letterbox`），邮筒页右上角推入
 * - 火漆信行首暂用首字圆徽占位（SealedEnvelope 小信封是 5.7 火漆卡）
 */
import { relationalStore } from '@kit.ArkData';
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
import { LetterDelivery } from '../../models/LetterDelivery';
import { Letter } from '../../models/Letter';
import { shortDate } from '../../services/AppDateFormatters';

const DOMAIN = 0x0000;
const TAG = 'LetterboxView';

/** 顶栏一行的高（返回圆钮 + 居中标题） */
const TOP_BAR_ROW_HEIGHT_VP: number = 44;
/** 「此刻」推进间隔（R-BOX-02），对齐 iOS Task.sleep 5 秒 */
const NOW_TICK_INTERVAL_MS: number = 5000;
/** 预览截取长度（iOS body.prefix(60) 同款） */
const PREVIEW_MAX_LENGTH: number = 60;

/** 系统路由表入口（router_map.json → name `Letterbox`）：邮筒 tab 内推入 */
@Builder
export function LetterboxBuilder() {
  LetterboxView()
}

@Component
export struct LetterboxView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  /** 信箱数据：onShown 全量重查（读信返回、调试插信后回来都刷新） */
  @State private letters: Letter[] = [];
  /** 「此刻」（毫秒）。定时推进，让到点的信自己冒出来（R-BOX-02） */
  @State private nowMs: number = Date.now();
  private navPathStack: NavPathStack = new NavPathStack();
  private store: relationalStore.RdbStore | undefined = undefined;
  private nowTimerId: number = -1;

  aboutToAppear(): void {
    this.nowTimerId = setInterval((): void => {
      this.nowMs = Date.now();
    }, NOW_TICK_INTERVAL_MS);
  }

  aboutToDisappear(): void {
    if (this.nowTimerId >= 0) {
      clearInterval(this.nowTimerId);
      this.nowTimerId = -1;
    }
  }

  /** 已到达的信，按到达时刻倒序（R-BOX-01） */
  private arrivedLetters(): Letter[] {
    const arrived = this.letters.filter((letter: Letter): boolean =>
      LetterDelivery.hasArrived(letter, this.nowMs));
    arrived.sort((a: Letter, b: Letter): number =>
      LetterDelivery.arrivalOf(b) - LetterDelivery.arrivalOf(a));
    return arrived;
  }

  /** 有信在路上（含写信中——对用户都算「在路上」，R-BOX-01） */
  private hasLettersInTransit(): boolean {
    return this.letters.some((letter: Letter): boolean =>
      LetterDelivery.isInTransit(letter, this.nowMs) || LetterDelivery.isWriting(letter));
  }

  private async reloadLetters(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      if (this.store === undefined) {
        this.store = await AppDatabase.open(context);
      }
      this.letters = await LetterRepository.listLetters(this.store);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'reload letters failed: %{public}s', JSON.stringify(err));
    }
  }

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column() {
            // 信件卡片（iOS：圆角 16 卡底 + 1px 描边）
            Column() {
              if (this.arrivedLetters().length === 0) {
                this.emptyState()
              } else {
                ForEach(this.arrivedLetters(), (letter: Letter, index: number) => {
                  if (index > 0) {
                    Divider()
                      .strokeWidth(0.5)
                      .color(this.theme.border)
                      .margin({ left: 68 })
                  }
                  this.letterRow(letter)
                }, (letter: Letter): string => `${letter.id}:${letter.status}`)
              }
            }
            .width('100%')
            .backgroundColor(this.theme.cardBackground)
            .borderRadius(16)
            .border({ width: 1, color: this.theme.border })

            // 卡片下面的一行轻提示：有信还在路上（空态时提示已在卡片里）
            if (this.arrivedLetters().length > 0 && this.hasLettersInTransit()) {
              Text($r('app.string.s_48f55a18f1'))
                .fontSize(this.theme.captionFont.size)
                .fontWeight(this.theme.captionFont.weight)
                .fontFamily(this.theme.captionFont.family)
                .fontColor(this.theme.textTertiary)
                .margin({ top: 16 })
            }

            Column()
              .width('100%')
              .height(this.safeAreaBottomVp + 32)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 12 })
        }
        // Scroll 高度受限后内容小于视口默认居中（官方 FAQ faqs-arkui-725）——显式顶对齐
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .layoutWeight(1)
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
    })
    .onShown((): void => {
      this.reloadLetters();
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题「信箱」 ----

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
        Text($r('app.string.s_44fd049d7d'))
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

  // ---- 空态：信箱还是空的（有信在路上时补一句） ----

  @Builder
  private emptyState() {
    Column({ space: 8 }) {
      Text($r('app.string.s_73f8dc416c'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
      if (this.hasLettersInTransit()) {
        Text($r('app.string.s_48f55a18f1'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
      }
    }
    .width('100%')
    .padding({ top: 40, bottom: 40 })
    .alignItems(HorizontalAlign.Center)
  }

  // ---- 一行信 ----

  @Builder
  private letterRow(letter: Letter) {
    Row({ space: 12 }) {
      // 行首：笔友首字圆徽（火漆信 5.7 换 SealedEnvelope 小信封，先占位）
      Stack() {
        Circle()
          .fill(this.theme.accentBackground)
        Text(letter.fromCharacter.length > 0 ? letter.fromCharacter.charAt(0) : '青')
          .fontSize(16)
          .fontColor(this.theme.accent)
      }
      .width(40)
      .height(40)

      Column({ space: 4 }) {
        Row() {
          Text($r('app.string.s_d190c58094', letter.fromCharacter))
            .fontSize(this.theme.bodyFont.size)
            .fontWeight(this.theme.bodyFont.weight)
            .fontFamily(this.theme.bodyFont.family)
            .fontColor(this.theme.textPrimary)
            .maxLines(1)
            .layoutWeight(1)
          // 收到的日子（到达时刻），不是寄出日子（iOS 同款）
          Text(shortDate(new Date(LetterDelivery.arrivalOf(letter)), this.appLanguage))
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.textTertiary)
        }
        .width('100%')

        // 火漆信没拆之前看不到里面写了什么（R-BOX-03）——和实物一样，拆开才算读到
        Text(letter.isSealed && LetterDelivery.isUnread(letter, this.nowMs)
          ? $r('app.string.s_0f534330b9')
          : letter.body.substring(0, PREVIEW_MAX_LENGTH))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textSecondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 未读红点：保持占位、不跳动（iOS opacity 同款）
      Circle()
        .fill(this.theme.accent)
        .width(8)
        .height(8)
        .margin({ top: 6 })
        .opacity(LetterDelivery.isUnread(letter, this.nowMs) ? 1 : 0)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick((): void => {
      this.navPathStack.pushPathByName('LetterDetail', letter.id);
    })
  }
}
