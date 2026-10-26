/**
 * 邮筒 tab 壳（10_BUILD_MANUAL.md 5.1）。对应 iOS `PostBoxView.swift` 的导航壳。
 *
 * - 本卡只落：tab 内 Navigation（信箱 / 读信挂这栈上，router_map 注册）
 *   + 右上角「信箱」入口（对齐 iOS：信箱从邮筒页右上角进，R-BOX）
 * - 占位正文居中标题「邮筒」；真邮筒页（候选日记叠 + 状态行 + 节奏，5.2）
 *   替换占位正文时**保留 Navigation 与信箱入口**
 * - 邮筒插画底色 / 状态行等都是 5.2+ 的卡，这里不预建
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP } from '../../services/ImmersiveChrome';

@Component
export struct PostBoxTabView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  private navPathStack: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.navPathStack) {
      Stack() {
        // 占位正文：居中标题（5.2 换真邮筒页）
        Column() {
          Text($r('app.string.s_11ab7804df'))
            .fontSize(this.theme.headingFont.size)
            .fontWeight(this.theme.headingFont.weight)
            .fontFamily(this.theme.headingFont.family)
            .fontColor(this.theme.textSecondary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None)

        // 右上角「信箱」入口（iOS 邮筒页右上角同位；5.2 保位）
        Row() {
          Blank()
          Text($r('app.string.s_44fd049d7d'))
            .fontSize(this.theme.bodyFont.size)
            .fontWeight(this.theme.bodyFont.weight)
            .fontFamily(this.theme.bodyFont.family)
            .fontColor(this.theme.accent)
            .padding({ left: 12, right: 16, top: 8, bottom: 8 })
            .onClick((): void => {
              this.navPathStack.pushPathByName('Letterbox', '');
            })
        }
        .width('100%')
        .padding({ top: this.safeAreaTopVp + 8, left: 16, right: 0 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor(this.theme.background)
  }
}
