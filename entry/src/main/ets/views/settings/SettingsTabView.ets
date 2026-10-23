/**
 * 设置 tab（10_BUILD_MANUAL.md 4.2 起步；4.3 账户卡）。
 * 对应 iOS SettingsView 的账户卡段：账户卡不收进二级页，
 * 🔴 未绑手机号的红色警告也留在一级页卡上（R-ACCOUNT-03，2026-08-12 账号分裂事故
 * 的直接对策——收进二级页等于取消警告）。
 *
 * 登录态刷新：UserSession 无观察机制，用 STORAGE_KEY_SESSION_TICK
 * （登录 / 绑定 / 401 清理时 +1）驱动重读。
 *
 * 顶部定格居中小标题「设置」：内容 Scroll 上滑从标题底下穿过（官方组件化改造）。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { STORAGE_KEY_SESSION_TICK } from '../../services/auth/UserSession';
import { AuthLogic } from '../../services/auth/AuthLogic';

/** 定格标题行的高（居中小标题「设置」悬浮在顶部） */
const TOP_BAR_ROW_HEIGHT_VP: number = 44;

@Component
export struct SettingsTabView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @StorageProp(STORAGE_KEY_SESSION_TICK) @Watch('onSessionTick') sessionTick: number = 0;

  @State private loggedIn: boolean = false;
  /** 账户卡主标题：昵称优先，其次脱敏手机号，再兜底「已登录」 */
  @State private accountTitle: string = '';
  /** 账户卡副标题：有昵称时的脱敏手机号（'' = 不显示） */
  @State private accountSubtitle: string = '';
  /** 🔴 未绑手机号 → 一级页卡上红色警告（R-ACCOUNT-03） */
  @State private phoneMissing: boolean = false;
  private navPathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.refreshSessionState();
  }

  /** 登录 / 绑定 / 401 清理信号 → 重读会话（UserSession 无观察机制，tick 补） */
  onSessionTick(): void {
    this.refreshSessionState();
  }

  build() {
    Navigation(this.navPathStack) {
      Column() {
        // 定格居中小标题「设置」（不随内容滚动；账户卡就在它下面、贴顶原位）
        Row() {
          Text($r('app.string.s_7debf9cb03'))
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

        // 内容：占满标题以下，上滑时在标题底边处隐去
        Scroll() {
          Column() {
            if (this.loggedIn) {
              this.loggedInAccountCard()
            } else {
              this.loginEntryCard()
            }
            // 底部：悬浮 Tab 栏 + 手势条让位
            Column().width('100%').height(this.safeAreaBottomVp + 88)
          }
          .padding({ left: 24, right: 24 })
          .constraintSize({ maxWidth: 840 })
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        // 🔴 Scroll 设高度限制后内容小于视口默认居中（官方 FAQ faqs-arkui-725，
        // 2026-10-24 真机「账户卡在屏幕中间」三轮排查后定位）——必须显式顶对齐
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.safeAreaTopVp })
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }

  /** 已登录账户卡：头像 + 昵称/手机号 + chevron，点进账户二级页；
   *  🔴 未绑手机号红色警告留在这张卡上，不收二级页（R-ACCOUNT-03） */
  @Builder
  private loggedInAccountCard() {
    Column() {
      Row({ space: 14 }) {
        SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
          .fontSize(34)
          .fontColor([this.theme.textSecondary])
        Column({ space: 3 }) {
          // 有昵称就以昵称为准——一串脱敏手机号当账号名，用户看不出「这是我」（iOS 同款）
          Text(this.accountTitle)
            .fontSize(this.theme.bodyFont.size)
            .fontWeight(this.theme.bodyFont.weight)
            .fontFamily(this.theme.bodyFont.family)
            .fontColor(this.theme.textPrimary)
          if (this.accountSubtitle.length > 0) {
            Text(this.accountSubtitle)
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.textTertiary)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.textTertiary])
      }
      .width('100%')
      .padding({ top: 14, bottom: this.phoneMissing ? 0 : 14, left: 20, right: 20 })
      .onClick((): void => {
        this.navPathStack.pushPathByName('Account', '');
      })

      // 🔴 未绑手机号警告必须留在一级页卡上（R-ACCOUNT-03；U02 华为版文案）
      if (this.phoneMissing) {
        Divider()
          .color(this.theme.border)
          .strokeWidth(0.5)
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
            .fontSize(14)
            .fontColor([this.theme.destructive])
          Text($r('app.string.s_ab8da9843c'))
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.destructive)
            .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Top)
        .width('100%')
        .padding({ top: 10, bottom: 14, left: 20, right: 20 })
      }
    }
    .borderRadius(16)
    .backgroundColor(this.theme.cardBackground)
    .width('100%')
    .margin({ top: 20 })
  }

  /** 未登录：登录 / 注册入口卡 */
  @Builder
  private loginEntryCard() {
    Row({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
        .fontSize(34)
        .fontColor([this.theme.textSecondary])
      Text($r('app.string.s_5d2df2c92d'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textTertiary])
    }
    .width('100%')
    .padding(20)
    .borderRadius(16)
    .backgroundColor(this.theme.cardBackground)
    .width('100%')
    .margin({ top: 20 })
    .onClick((): void => {
      this.navPathStack.pushPathByName('Login', '');
    })
  }

  /** 从会话容器重读登录态：主标题昵称优先，副标题有昵称时的脱敏手机号 */
  private refreshSessionState(): void {
    const session = this.env.session;
    if (session === undefined || !session.isLoggedIn()) {
      this.loggedIn = false;
      this.accountTitle = '';
      this.accountSubtitle = '';
      this.phoneMissing = false;
      return;
    }
    this.loggedIn = true;
    const user = session.user;
    if (user === null) {
      // 有 token 无快照（快照损坏 / 401 前一瞬）：也算已登录，兜底展示
      this.accountTitle = '';
      this.accountSubtitle = '';
      this.phoneMissing = false;
      return;
    }
    this.phoneMissing = user.phone.length === 0;
    const masked: string = AuthLogic.maskedPhone(user.phone);
    if (user.displayName.length > 0) {
      this.accountTitle = user.displayName;
      this.accountSubtitle = user.phone.length > 0 ? masked : '';
    } else {
      this.accountTitle = user.phone.length > 0 ? masked : '';
      this.accountSubtitle = '';
    }
  }
}
