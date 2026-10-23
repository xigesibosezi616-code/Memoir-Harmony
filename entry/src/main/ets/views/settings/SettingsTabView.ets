/**
 * 设置 tab（10_BUILD_MANUAL.md 4.2 起步；4.3 账户卡 / 更多设置项再扩）。
 * 对应 iOS 设置页 NavigationStack 的雏形：本卡只放「登录」入口与登录态展示，
 * 点登录推 Login 路由（router_map → name `Login`）。
 *
 * 登录态刷新：UserSession 无观察机制（4.3 账户卡接 AppStorage tick 联动），
 * 这里用 STORAGE_KEY_SESSION_TICK（登录 / 401 清理时 +1）驱动重读。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { STORAGE_KEY_SESSION_TICK } from '../../services/auth/UserSession';
import { AuthLogic } from '../../services/auth/AuthLogic';

@Component
export struct SettingsTabView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @StorageProp(STORAGE_KEY_SESSION_TICK) @Watch('onSessionTick') sessionTick: number = 0;

  @State private loggedIn: boolean = false;
  @State private accountLabel: string = '';
  private navPathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.refreshSessionState();
  }

  /** 登录 / 401 清理信号 → 重读会话（UserSession 无观察机制，tick 补） */
  onSessionTick(): void {
    this.refreshSessionState();
  }

  build() {
    Navigation(this.navPathStack) {
      Column() {
        // 页头标题「设置」（tab 内页面，顶部让开状态栏）
        Text($r('app.string.s_7debf9cb03'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)
          .width('100%')

        if (this.loggedIn) {
          this.loggedInCard()
        } else {
          this.loginEntry()
        }

        Blank()
      }
      .padding({
        left: 24,
        right: 24,
        top: this.safeAreaTopVp + 16,
        bottom: this.safeAreaBottomVp + 88
      })
      .constraintSize({ maxWidth: 840 })
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }

  /** 已登录态展示（4.3 换正式账户卡：手机号 / 昵称 / 绑定项 / 退出） */
  @Builder
  private loggedInCard() {
    Column({ space: 6 }) {
      Text(this.accountLabel)
        .fontSize(this.theme.titleFont.size)
        .fontWeight(this.theme.titleFont.weight)
        .fontFamily(this.theme.titleFont.family)
        .fontColor(this.theme.textPrimary)
      Text($r('app.string.s_0b7e2d4a9c'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .borderRadius(16)
    .backgroundColor(this.theme.cardBackground)
    .width('100%')
    .margin({ top: 20 })
  }

  /** 未登录：登录入口按钮 */
  @Builder
  private loginEntry() {
    Column() {
      Text($r('app.string.s_21f1e88275'))
        .fontSize(this.theme.titleFont.size)
        .fontWeight(this.theme.titleFont.weight)
        .fontFamily(this.theme.titleFont.family)
        .fontColor(this.theme.accent)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(20)
    .borderRadius(16)
    .backgroundColor(this.theme.cardBackground)
    .width('100%')
    .margin({ top: 20 })
    .onClick((): void => {
      this.navPathStack.pushPathByName('Login', '');
    })
  }

  /** 从会话容器重读登录态：已登录展示掩码手机号（无手机号退昵称 / 用户 ID） */
  private refreshSessionState(): void {
    const session = this.env.session;
    if (session === undefined || !session.isLoggedIn()) {
      this.loggedIn = false;
      this.accountLabel = '';
      return;
    }
    this.loggedIn = true;
    const user = session.user;
    if (user !== null && user.phone.length > 0) {
      this.accountLabel = AuthLogic.maskedPhone(user.phone);
    } else if (user !== null && user.displayName.length > 0) {
      this.accountLabel = user.displayName;
    } else if (user !== null) {
      this.accountLabel = user.id;
    } else {
      // 有 token 无快照（快照损坏 / 401 前一瞬）：也算已登录，占位展示
      this.accountLabel = '—';
    }
  }
}
