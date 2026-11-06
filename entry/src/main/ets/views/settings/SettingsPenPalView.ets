/**
 * 设置 →「笔友」二级页（10_BUILD_MANUAL.md 6.1）。对应 iOS `SettingsPenPalView.swift`。
 *
 * - 笔友名：右对齐行内输入（`penPalName`，默认「青鸟」；与 iOS 键同名，
 *   PostBoxTabView 等共用这个偏好——R-SETTINGS-05：改名只影响之后的新信，
 *   历史信件的署名不变）
 * - 空串 / 全空白回车按「清空」处理时退回默认「青鸟」（iOS onSubmit 同款）
 *
 * 路由：系统路由表（router_map.json → name `PenPalSettings`）。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AppPrefs, PREF_KEY_PEN_PAL_NAME } from '../../services/AppPrefs';

/** 顶栏一行的高（返回圆钮 + 居中标题） */
const TOP_BAR_ROW_HEIGHT_VP: number = 44;

@Builder
export function SettingsPenPalBuilder() {
  SettingsPenPalView()
}

@Component
export struct SettingsPenPalView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 笔友名草稿（行内输入；失焦 / 回车落偏好） */
  @State private penPalName: string = '青鸟';

  private navPathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 20 }) {
            Column() {
              this.penPalNameRow()
            }
            .borderRadius(16)
            .backgroundColor(this.theme.settingsCardBackground)
            .width('100%')

            // footer：改名影响范围（R-SETTINGS-05；iOS 同款）
            Text($r('app.string.s_c665b719e0'))
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
      this.penPalName = AppPrefs.getString(PREF_KEY_PEN_PAL_NAME, '青鸟');
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
        Text($r('app.string.s_8dcc9a2d73'))
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

  // ---- 笔友名行内输入（右对齐；回车 / 失焦收尾） ----

  @Builder
  private penPalNameRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.person_2'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_088b3628a1'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
      TextInput({ text: this.penPalName, placeholder: '青鸟' })
        .fontSize(this.theme.captionFont.size)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textPrimary)
        .placeholderColor(this.theme.textTertiary)
        .textAlign(TextAlign.End)
        .backgroundColor(Color.Transparent)
        .border({ width: 0 })
        .padding({ left: 12, right: 0 })
        .height(40)
        .maxLength(64)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.penPalName = value;
        })
        .onSubmit((): void => {
          this.commitPenPalName();
        })
        .onBlur(() => {
          this.commitPenPalName();
        })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
  }

  /** 收尾落盘：首尾空白裁掉；空串退回默认「青鸟」（iOS onSubmit 同款） */
  private commitPenPalName(): void {
    const trimmed = this.penPalName.trim();
    if (trimmed.length === 0) {
      this.penPalName = '青鸟';
      AppPrefs.putString(PREF_KEY_PEN_PAL_NAME, '青鸟');
      return;
    }
    this.penPalName = trimmed;
    AppPrefs.putString(PREF_KEY_PEN_PAL_NAME, trimmed);
  }
}
