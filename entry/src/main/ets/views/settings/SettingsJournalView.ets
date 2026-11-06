/**
 * 设置 →「日记」二级页（10_BUILD_MANUAL.md 6.1）。对应 iOS `SettingsJournalView.swift`。
 *
 * - 照片相纸样式：推「默认相纸样式」选择页（DefaultPaperStylePickerView），
 *   行值显示当前默认相纸（插照片时预选的那个；05 §3.5）
 * - 日记印章 / 封条提醒天数不做（Q10：印章待产品决定、封条提醒死设置）
 * - 「写作统计」不在这页——它是内容页，一级页单列一行（R-SETTINGS-02）
 *
 * 路由：系统路由表（router_map.json → name `JournalSettings`）。
 */
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AppPrefs, PREF_KEY_DEFAULT_PAPER_STYLE } from '../../services/AppPrefs';
import { PaperStyle, paperStyleFromRaw } from '../../models/ContentBlock';

@Builder
export function SettingsJournalBuilder() {
  SettingsJournalView()
}

@Component
export struct SettingsJournalView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 当前默认相纸（行值；进页读偏好，默认宝丽来，05 §3.5） */
  @State private paperStyle: PaperStyle = PaperStyle.Polaroid;

  private navPathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 20 }) {
            Column() {
              this.paperStyleRow()
            }
            .borderRadius(16)
            .backgroundColor(this.theme.settingsCardBackground)
            .width('100%')

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
    })
    // 从相纸选择页返回时本页未销毁——onShown 每次露出都重读偏好，行值不滞留旧值
    .onShown((): void => {
      const stored = paperStyleFromRaw(
        AppPrefs.getString(PREF_KEY_DEFAULT_PAPER_STYLE, PaperStyle.Polaroid));
      // 非法值按宝丽来兜底（旧数据 / 手改坏了不崩；05 §3.5）
      this.paperStyle = stored === undefined ? PaperStyle.Polaroid : stored;
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
        Text($r('app.string.s_bf50d67138'))
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
    .margin({ bottom: TOP_BAR_CONTENT_GAP_VP })
  }

  // ---- 照片相纸样式（插照片预选；推选择页） ----

  @Builder
  private paperStyleRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.picture'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_775660537d'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      Text(this.paperStyleName())
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textTertiary])
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.navPathStack.pushPathByName('DefaultPaperStyle', '');
    })
  }

  /** 相纸显示名（PaperStylePickerSheet 同一张映射表） */
  private paperStyleName(): Resource {
    switch (this.paperStyle) {
      case PaperStyle.Original:
        return $r('app.string.s_cd0f3ad8dd');
      case PaperStyle.WashiSticker:
        return $r('app.string.s_105137838b');
      case PaperStyle.MinimalCard:
        return $r('app.string.s_234289679b');
      case PaperStyle.FilmFrame:
        return $r('app.string.s_c3915c323e');
      case PaperStyle.LetterAttached:
        return $r('app.string.s_975ac3e011');
      case PaperStyle.Polaroid:
      default:
        return $r('app.string.s_f4ae8c66ad');
    }
  }
}
