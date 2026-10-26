/**
 * 邮筒 tab 壳（10_BUILD_MANUAL.md 5.1）。对应 iOS `PostBoxView.swift` 的导航壳。
 *
 * - 本卡只落：tab 内 Navigation（信箱 / 读信挂这栈上，router_map 注册）
 *   + 官方标题栏右上角「信箱」入口。
 *   入口实现 = 自定义 title 的**内联 this 引用**（`.title(this.titleBar)`，
 *   ComposeView:435 / EditEntryView:337 同款、真机已验证可渲染）：
 *   builder 一旦被箭头闭包 / 字段捕获就丢掉 @Builder 作用域装置，静默不渲染
 *   或崩溃（EntryDetailView:443 注释、faqs-arkui-906 同因）；
 *   menus 的 CustomBuilder 形态同样不渲染（真机实证箭头式/调用式均无节点），
 *   数组形态能渲染但 API 10 起不显示菜单文本 —— 都不可用。
 *   自定义 title 内容横排 Blank+信箱，信箱落到标题栏右端，
 *   等价 iOS toolbar 的 ToolbarItem(.topBarTrailing)（PostBoxView.swift L81-84）。
 *   - 标题栏不显示标题（用户拍板：左上角不出「邮筒」二字，只留右上角入口；
 *     iOS 该页同样无标题文字）
 * - 5.2 替换正文时**保留 Navigation、标题栏与信箱入口**
 * - 邮筒插画底色 / 状态行等都是 5.2+ 的卡，这里不预建
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

@Component
export struct PostBoxTabView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  private navPathStack: NavPathStack = new NavPathStack();

  /** 标题栏：左端留空，右端「信箱」入口（iOS letterboxButton 同款：captionFont + textPrimary） */
  @Builder
  titleBar() {
    Row() {
      Blank()
      Text($r('app.string.s_44fd049d7d'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textPrimary)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick((): void => {
          this.navPathStack.pushPathByName('Letterbox', '');
        })
    }
    .width('100%')
  }

  build() {
    Navigation(this.navPathStack) {
      // 占位正文（5.2 换真邮筒页：候选日记叠 + 状态行 + 节奏）
      Column()
        .width('100%')
        .layoutWeight(1)
    }
    .title(this.titleBar)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .backgroundColor(this.theme.background)
  }
}
