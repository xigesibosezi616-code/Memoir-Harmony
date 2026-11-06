/**
 * 设置 →「日记」→「照片相纸样式」选择页（10_BUILD_MANUAL.md 6.1）。
 * 对应 iOS `DefaultPaperStylePickerView.swift`。
 *
 * - 六种相纸单选（`defaultPaperStyle`，插照片时预选；05 §3.5）
 * - 行值按实际存的偏好打勾；选完落偏好即生效（下次插照片预选）
 * - 会员锁（四种会员款）阶段 7 再上：本阶段全放开（2.6 起判定恒放开）
 *
 * 路由：系统路由表（router_map.json → name `DefaultPaperStyle`），
 * 由 SettingsJournalView 推入。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AppPrefs, PREF_KEY_DEFAULT_PAPER_STYLE } from '../../services/AppPrefs';
import { PaperStyle, paperStyleFromRaw } from '../../models/ContentBlock';

/** 顶栏一行的高（返回圆钮 + 居中标题） */
const TOP_BAR_ROW_HEIGHT_VP: number = 44;

/** 一个相纸选项（值 + 显示名词条） */
class PaperOption {
  readonly style: PaperStyle;
  readonly nameRes: Resource;

  constructor(style: PaperStyle, nameRes: Resource) {
    this.style = style;
    this.nameRes = nameRes;
  }
}

@Builder
export function DefaultPaperStylePickerBuilder() {
  DefaultPaperStylePickerView()
}

@Component
export struct DefaultPaperStylePickerView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 当前选中的默认相纸（打勾；非法值按宝丽来兜底） */
  @State private selected: PaperStyle = PaperStyle.Polaroid;

  private navPathStack: NavPathStack = new NavPathStack();

  /** 六种相纸固定顺序（PaperStyle 枚举序：原图 → 宝丽来 → 和风贴纸 → 极简卡片 → 胶片帧 → 信纸附照） */
  private readonly options: PaperOption[] = [
    new PaperOption(PaperStyle.Original, $r('app.string.s_cd0f3ad8dd')),
    new PaperOption(PaperStyle.Polaroid, $r('app.string.s_f4ae8c66ad')),
    new PaperOption(PaperStyle.WashiSticker, $r('app.string.s_105137838b')),
    new PaperOption(PaperStyle.MinimalCard, $r('app.string.s_234289679b')),
    new PaperOption(PaperStyle.FilmFrame, $r('app.string.s_c3915c323e')),
    new PaperOption(PaperStyle.LetterAttached, $r('app.string.s_975ac3e011'))
  ];

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 20 }) {
            // 组头
            Text($r('app.string.s_8d1a970c8d'))
              .fontSize(this.theme.labelFont.size)
              .fontWeight(this.theme.labelFont.weight)
              .fontFamily(this.theme.labelFont.family)
              .fontColor(this.theme.textTertiary)
              .letterSpacing(this.theme.letterSpacingWide)
              .padding({ left: 8 })

            // 六种相纸单选（当前默认打勾）
            Column() {
              ForEach(this.options, (option: PaperOption, index: number) => {
                if (index > 0) {
                  Divider()
                    .color(this.theme.border)
                    .strokeWidth(0.5)
                    .margin({ left: 20 })
                }
                this.optionRow(option)
              })
            }
            .borderRadius(16)
            .backgroundColor(this.theme.settingsCardBackground)
            .width('100%')

            // footer：预选说明（iOS 同款）
            Text($r('app.string.s_8c2d497713'))
              .fontSize(this.theme.labelFont.size)
              .fontWeight(this.theme.labelFont.weight)
              .fontFamily(this.theme.labelFont.family)
              .fontColor(this.theme.textTertiary)
              .padding({ left: 8, right: 8 })

            // 底部：手势条让位
            Column().width('100%').height(this.safeAreaBottomVp + 32)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 24, right: 24 })
        }
        .width('100%')
        .layoutWeight(1)
        // 🔴 Scroll 设高度限制后内容小于视口默认居中（官方 FAQ faqs-arkui-725）——必须显式顶对齐
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.safeAreaTopVp })
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.settingsPageBackground)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      const stored = paperStyleFromRaw(
        AppPrefs.getString(PREF_KEY_DEFAULT_PAPER_STYLE, PaperStyle.Polaroid));
      this.selected = stored === undefined ? PaperStyle.Polaroid : stored;
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题（SettingsAccountView 同款） ----

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
        Text($r('app.string.s_775660537d'))
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
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(TOP_BAR_ROW_HEIGHT_VP)
  }

  // ---- 单个相纸行（选中打勾） ----

  @Builder
  private optionRow(option: PaperOption) {
    Row({ space: 10 }) {
      Text(option.nameRes)
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      if (this.selected === option.style) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.accent])
      }
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      if (this.selected !== option.style) {
        this.selected = option.style;
        AppPrefs.putString(PREF_KEY_DEFAULT_PAPER_STYLE, option.style);
      }
    })
  }
}
