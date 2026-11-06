/**
 * 设置 → 外观 →「应用图标」选择页（10_BUILD_MANUAL.md 6.2）。对应 iOS `Views/Settings/AppIconPickerView.swift`。
 *
 * 默认**跟随主题** —— 换主题时图标自动跟着换（这是本来就有的行为）。
 * 用户一旦手动选了某个图标，就固定下来，之后换主题不再覆盖他的选择（R-THEME-06）。
 *
 * - 「跟随主题」行：paintbrush 图标 + 说明；四主题图标行：预览图 + 主题名（图标名跟主题名
 *   保持一致 —— 图标是跟着主题走的，两处叫法不一样会让用户以为是两个东西）
 * - 选中态看的是「用户选的是不是这一个」，不是「当前生效的是不是这一个」——
 *   跟随主题时当前生效的也是某个图标，但那时候勾应该打在「跟随主题」上
 * - 切换走 AGC 图标管理服务；开发期未上架服务不可用，失败提示「图标切换失败，请稍后再试」
 *
 * 路由：系统路由表（router_map.json → name `AppIconPicker`）。
 */
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME, STORAGE_KEY_THEME_MANAGER, ThemeManager } from '../../theme/ThemeManager';
import { ThemePaper } from '../../theme/ThemePaper';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';

@Builder
export function AppIconPickerBuilder() {
  AppIconPickerView()
}

@Component
export struct AppIconPickerView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 用户选的图标 id；'' = 跟随主题（进页读真实状态，选择后立即刷新） */
  @State private selection: string = '';

  private navPathStack: NavPathStack = new NavPathStack();
  private manager: ThemeManager | undefined = undefined;

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 16 }) {
            this.followThemeRow()

            Divider()
              .color(this.theme.textTertiary)
              .opacity(0.25)
              .margin({ top: 4, bottom: 4 })

            ForEach(ThemePaper.all, (paper: ThemePaper) => {
              this.iconRow(paper)
            })

            Text($r('app.string.s_6e5c04b091'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.textTertiary)
              .textAlign(TextAlign.Center)
              .margin({ top: 20, left: 12, right: 12 })

            // 底部：手势条让位
            Column().width('100%').height(this.safeAreaBottomVp + 32)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 20, right: 20, top: 16 })
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
      this.manager = AppStorage.get<ThemeManager>(STORAGE_KEY_THEME_MANAGER);
      if (this.manager !== undefined) {
        this.selection = this.manager.appIconSelection;
      }
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题（ThemePickerView 同款） ----

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
        Text($r('app.string.s_f93d423da3'))
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

  // ---- 「跟随主题」行 ----

  @Builder
  private followThemeRow() {
    Row({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.paintbrush'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(56)
        .height(56)
        .backgroundColor(this.theme.accentBackground)
        .borderRadius(13)

      Column({ space: 2 }) {
        Text($r('app.string.s_cb7f4c5817'))
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
        Text($r('app.string.s_1ce1054c48'))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.selection === '') {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.accent])
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor(this.theme.settingsCardBackground)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.select('');
    })
  }

  // ---- 单个图标行 ----

  @Builder
  private iconRow(paper: ThemePaper) {
    Row({ space: 14 }) {
      Image(paper.iconPreviewRes)
        .width(56)
        .height(56)
        .borderRadius(13)
        .border({ width: 0.5, color: this.theme.border })
        .objectFit(ImageFit.Cover)

      Text(paper.nameRes)
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)

      if (this.selection !== '' && this.selection === paper.id) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.accent])
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor(this.theme.settingsCardBackground)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.select(paper.id);
    })
  }

  /** 选择（'' = 回跟随主题）。用户手动点的，失败必须让他看见 —— 否则就是「点了没反应」 */
  private select(id: string): void {
    this.selection = id;
    if (this.manager === undefined) {
      return;
    }
    this.manager.selectAppIcon(id, (error: BusinessError): void => {
      hilog.error(0x0000, 'AppIconPicker', 'icon switch failed, code: %{public}d', error.code);
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.s_1d83c41037')
      });
    });
  }
}
