/**
 * 设置 →「笔友」二级页（10_BUILD_MANUAL.md 6.1）。对应 iOS `SettingsPenPalView.swift`。
 *
 * - 笔友名：右对齐行内输入（`penPalName`；与 iOS 键同名，PostBoxTabView 等
 *   共用这个偏好——R-SETTINGS-05：改名只影响之后的新信，历史信件的署名不变）
 * - 名字只能由用户自己起，不再有默认名（2026-10-24 产品定，见 `PenPalName`）：
 *   空串 / 全空白 / 还是旧默认「青鸟」按「没改」处理，恢复原样不落盘
 *
 * 路由：系统路由表（router_map.json → name `PenPalSettings`）。
 */
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AppPrefs, PREF_KEY_PEN_PAL_NAME, STORAGE_KEY_PEN_PAL_NAME } from '../../services/AppPrefs';
import { PenPalName } from '../../models/PenPalName';

@Builder
export function SettingsPenPalBuilder() {
  SettingsPenPalView()
}

@Component
export struct SettingsPenPalView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /**
   * 正在改的名字。不直接绑存储：清空了离开页面时名字会变成空的
   * （笔友没有默认名可退）；还没起名时进来是空草稿
   */
  @State private penPalName: string = '';

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
      // 还没起名进来是空草稿；起过名带原名（iOS onAppear 同款）
      const stored = AppPrefs.getString(PREF_KEY_PEN_PAL_NAME, '');
      this.penPalName = PenPalName.needsNaming(stored) ? '' : stored;
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
    .margin({ bottom: TOP_BAR_CONTENT_GAP_VP })
  }

  // ---- 笔友名行内输入（右对齐；回车 / 失焦收尾） ----

  @Builder
  private penPalNameRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.person'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_088b3628a1'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
      TextInput({ text: this.penPalName, placeholder: $r('app.string.s_960e2f7361') })
        .fontSize(this.theme.captionFont.size)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textPrimary)
        .placeholderColor(this.theme.textTertiary)
        .textAlign(TextAlign.End)
        .backgroundColor(Color.Transparent)
        .border({ width: 0 })
        .padding({ left: 12, right: 0 })
        .height(40)
        .maxLength(PenPalName.MAX_LENGTH)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.penPalName = PenPalName.truncated(value);
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

  /** 离开页面也算收尾（iOS onDisappear(perform: commit) 同款）：没回车 / 没失焦就走的也存上 */
  aboutToDisappear(): void {
    this.commitPenPalName();
  }

  /**
   * 收尾落盘（iOS commit 同款）：有名字才存；空的 / 还是旧默认「青鸟」
   * 按没改处理——草稿恢复原样，偏好不动。存了的话连 AppStorage 镜像一起写，
   * 邮筒页状态行（@StorageProp）即时跟上
   */
  private commitPenPalName(): void {
    const stored = AppPrefs.getString(PREF_KEY_PEN_PAL_NAME, '');
    const name = PenPalName.normalized(this.penPalName);
    if (PenPalName.needsNaming(name)) {
      this.penPalName = PenPalName.needsNaming(stored) ? '' : stored;
      return;
    }
    this.penPalName = name;
    AppPrefs.putString(PREF_KEY_PEN_PAL_NAME, name);
    AppStorage.setOrCreate(STORAGE_KEY_PEN_PAL_NAME, name);
  }
}
