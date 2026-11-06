/**
 * 设置 →「语言」选择页（10_BUILD_MANUAL.md 6.1）。对应 iOS `LanguagePickerView.swift`。
 *
 * - 七种语言（R-LANG-01 顺序固定），显示名永远用**自称**（英语永远显示 English）
 * - **没有「跟随系统」**（R-LANG-02：首启已按系统语言定过一个明确的语言）
 * - 选中打勾；点选即切（LanguageManager.setLanguage，当场生效 R-LANG-03）
 *
 * 路由：系统路由表（router_map.json → name `Language`），
 * 一级页「语言」行直通（R-SETTINGS-02 不套二级页）。
 */
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { STORAGE_KEY_APP_LANGUAGE, STORAGE_KEY_LANGUAGE_MANAGER,
  LanguageManager, LanguageOption } from '../../services/LanguageManager';

@Builder
export function LanguagePickerBuilder() {
  LanguagePickerView()
}

@Component
export struct LanguagePickerView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  /** 当前 App 语言（切换当场生效：key 一变整页重渲染，R-LANG-03） */
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'en';
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  private navPathStack: NavPathStack = new NavPathStack();
  /** LanguageManager 实例（EntryAbility 启动时建好放 AppStorage） */
  private manager: LanguageManager | undefined = undefined;

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 20 }) {
            Column() {
              ForEach(LanguageManager.supportedOptions(),
                (option: LanguageOption, index: number) => {
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
      const mgr = AppStorage.get<LanguageManager>(STORAGE_KEY_LANGUAGE_MANAGER);
      this.manager = mgr;
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题（标题「语言 / Language」多语并置，iOS 同款） ----

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
        Text($r('app.string.s_8d6bc0a28f'))
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

  // ---- 单个语言行（自称 + 当前语言打勾） ----

  @Builder
  private optionRow(option: LanguageOption) {
    Row({ space: 10 }) {
      Text(option.nameResource)
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      if (this.appLanguage === option.id) {
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
      if (this.manager !== undefined) {
        this.manager.setLanguage(option.id);
      }
    })
  }
}
