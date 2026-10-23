/**
 * 手机号登录页（10_BUILD_MANUAL.md 4.2；AUTH_DESIGN.md §6 两步流）。
 * 对应 iOS `LoginView.swift`（login 模式；bindPhone 模式 4.3 绑定流再开）。
 *
 * 两步流：手机号 → 验证码；6 位自动提交；重发倒计时由后端 retryAfter 驱动；
 * 命中频控（429）按顶层 retryAfter 恢复倒计时（杀 App 重进立刻点重发的场景）。
 * 登录不强制：写日记永远不需要登录，这里只服务 AI 信件等云端能力。
 * 华为账号登录按钮（U02：放手机号登录下面）后端 /auth/huawei 未实现（09 Q1），
 * 4.4 接——本页不预留死 UI。
 *
 * 路由：系统路由表（router_map.json → name `Login`），设置页推入；
 * 悬浮 Tab 栏在页面上期间隐藏（STORAGE_KEY_HIDE_TAB_BAR，接近日志 sheet 盖全屏的语义）。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { STORAGE_KEY_HIDE_TAB_BAR, STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AuthLogic } from '../../services/auth/AuthLogic';
import { HttpError } from '../../services/http/HttpError';
import { STORAGE_KEY_SESSION_TICK } from '../../services/auth/UserSession';
import { SendCodeResponse, AuthResponse } from '../../models/Api';

/** 系统路由表入口（router_map.json → name `Login`） */
@Builder
export function LoginBuilder() {
  LoginView()
}

@Component
export struct LoginView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 两步流：0 = 手机号步，1 = 验证码步（iOS Step.phone / .code） */
  @State private step: number = 0;
  @State private phone: string = '';
  @State private code: string = '';
  @State private busy: boolean = false;
  /** 重发倒计时剩余秒数（后端 retryAfter 驱动） */
  @State private countdown: number = 0;
  private countdownTimerId: number = -1;
  private navPathStack: NavPathStack = new NavPathStack();

  aboutToDisappear(): void {
    this.stopCountdown();
    AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, false);
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏：取消（官方 Button 胶囊组件；底色走各主题玻璃 token——明度差
        // 已按主题单独调过（素笺米灰绿/皮革金/肯特灰），深浅底上都成型）
        Row() {
          Button($r('app.string.s_4d0b4688c7'), { type: ButtonType.Capsule, stateEffect: true })
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textPrimary)
            .backgroundColor(this.theme.glassBackground)
            .border({ width: 0.5, color: this.theme.glassBorder })
            .height(32)
            .padding({ left: 16, right: 16 })
            .onClick((): void => {
              this.navPathStack.pop();
            })
          Blank()
        }
        // 取消栏更贴左缘（12vp），与内容块 28vp 宽边距分离（真机反馈「取消键靠左一点」）
        .padding({ left: 12, right: 28 })
        .width('100%')

        // 内容块：iOS VStack(spacing:28) 同款节拍；整块水平居中（iOS VStack 默认 .center）
        Column({ space: 28 }) {
          Column({ space: 8 }) {
            Text(this.step === 0 ? $r('app.string.s_f2d81a9c46') : $r('app.string.s_5c3e9b7a12'))
              .fontSize(this.theme.titleFont.size)
              .fontWeight(this.theme.titleFont.weight)
              .fontFamily(this.theme.titleFont.family)
              .fontColor(this.theme.textPrimary)
            Text(this.subtitleText())
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.textTertiary)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 12 })

          if (this.step === 0) {
            this.phoneField()
          } else {
            this.codeField()
          }

          this.primaryButton()

          if (this.step === 1) {
            Text(this.countdown > 0
              ? $r('app.string.s_132f0d719a', this.countdown)
              : $r('app.string.s_a4e6f10bf1'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.countdown > 0 ? this.theme.textTertiary : this.theme.accent)
              .onClick((): void => {
                if (this.countdown <= 0 && !this.busy) {
                  this.sendCode();
                }
              })
          }

          Blank()
        }
        .padding({ left: 28, right: 28 })
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      }
      .padding({
        // 状态栏避让 + 16vp 呼吸位（沉浸式全屏下 NavDestination 内容从窗口顶起排；
        // 实测调参：0 顶状态栏、12 偏挤、20 偏塌，16 收口）
        top: this.safeAreaTopVp + 16,
        bottom: this.safeAreaBottomVp
      })
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.background)
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
    })
    .onShown((): void => {
      AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, true);
    })
    .onHidden((): void => {
      AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, false);
    })
  }

  /** 副标题：手机号步 = 未注册说明；验证码步 = 已发送至掩码手机号 */
  private subtitleText(): Resource {
    if (this.step === 0) {
      return $r('app.string.s_e9989b9fd6');
    }
    return $r('app.string.s_ee8a3ce436', AuthLogic.maskedPhone(this.phone));
  }

  /** 主按钮可点：不忙 &&（手机号步 11 位合法 / 验证码步 6 位） */
  private primaryEnabled(): boolean {
    if (this.busy) {
      return false;
    }
    if (this.step === 0) {
      return AuthLogic.isValidMainlandPhone(this.phone);
    }
    return this.code.length === 6;
  }

  @Builder
  private phoneField() {
    TextInput({ text: this.phone, placeholder: $r('app.string.s_0d4dd89acf') })
      .type(InputType.Number)
      .maxLength(11)
      .textAlign(TextAlign.Center)
      .fontSize(this.theme.titleFont.size)
      .fontWeight(this.theme.titleFont.weight)
      .fontFamily(this.theme.titleFont.family)
      .fontColor(this.theme.textPrimary)
      .placeholderColor(this.theme.textSecondary)
      .backgroundColor(this.theme.cardBackground)
      .borderRadius(12)
      .height(52)
      .defaultFocus(true)
      .onChange((value: string) => {
        this.phone = AuthLogic.digitsOnly(value, 11);
      })
  }

  @Builder
  private codeField() {
    TextInput({ text: this.code, placeholder: $r('app.string.s_83a302c43c') })
      .type(InputType.Number)
      .maxLength(6)
      .textAlign(TextAlign.Center)
      .fontSize(this.theme.titleFont.size)
      .fontWeight(this.theme.titleFont.weight)
      .fontFamily(this.theme.titleFont.family)
      .fontColor(this.theme.textPrimary)
      .placeholderColor(this.theme.textSecondary)
      .backgroundColor(this.theme.cardBackground)
      .borderRadius(12)
      .height(52)
      .defaultFocus(true)
      .onChange((value: string) => {
        this.code = AuthLogic.digitsOnly(value, 6);
        if (this.code.length === 6 && !this.busy) {
          this.login();
        }
      })
  }

  /** 主按钮（官方胶囊 Button）：accent 底 + cardBackground 字——工程 FAB 同款
   * per-theme 配对（素笺/肯特白字、皮革深字），三主题各自可读；禁用态整体 35% 透明 */
  @Builder
  private primaryButton() {
    Button() {
      Row({ space: 8 }) {
        if (this.busy) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.theme.cardBackground)
        }
        Text(this.step === 0 ? $r('app.string.s_084f68942b') : $r('app.string.s_21f1e88275'))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.cardBackground)
      }
      .justifyContent(FlexAlign.Center)
    }
    .type(ButtonType.Capsule)
    .backgroundColor(this.theme.accent)
    .opacity(this.primaryEnabled() ? 1 : 0.35)
    .enabled(this.primaryEnabled())
    .height(48)
    .width('100%')
    .onClick((): void => {
      if (this.step === 0) {
        this.sendCode();
      } else {
        this.login();
      }
    })
  }

  /** 发验证码：成功进验证码步并起倒计时；429 按顶层 retryAfter 恢复倒计时 */
  private async sendCode(): Promise<void> {
    if (this.busy || !AuthLogic.isValidMainlandPhone(this.phone)) {
      return;
    }
    this.busy = true;
    try {
      const auth = this.env.auth;
      if (auth === undefined) {
        return;
      }
      const resp: SendCodeResponse = await auth.sendCode(this.phone);
      this.step = 1;
      this.code = '';
      this.startCountdown(resp.retryAfter);
    } catch (e) {
      this.presentAuthError(e, $r('app.string.s_e6f8a0b2c4'));
      // 命中频控（429）按顶层 retryAfter 恢复倒计时（如杀 App 重进后立刻点重发）
      if (e instanceof HttpError && e.isRateLimited() && e.envelope !== null &&
        typeof e.envelope.retryAfter === 'number' && e.envelope.retryAfter > 0) {
        this.step = 1;
        this.startCountdown(e.envelope.retryAfter);
      }
    } finally {
      this.busy = false;
    }
  }

  /** 验码登录：成功建立会话，提示后返回 */
  private async login(): Promise<void> {
    if (this.busy || this.code.length !== 6) {
      return;
    }
    this.busy = true;
    try {
      const auth = this.env.auth;
      if (auth === undefined) {
        return;
      }
      const resp: AuthResponse = await auth.login(this.phone, this.code);
      const session = this.env.session;
      if (session !== undefined) {
        session.establish(resp.token, resp.user);
        // 登录态变化信号：设置页（4.3 账户卡）@Watch 刷新用（RDB 无观察机制同款补法）
        AppStorage.setOrCreate(STORAGE_KEY_SESSION_TICK,
          (AppStorage.get<number>(STORAGE_KEY_SESSION_TICK) ?? 0) + 1);
      }
      this.presentResourceToast($r('app.string.s_8d4a2f6e90'), ErrorToastKind.Success);
      this.stopCountdown();
      this.navPathStack.pop();
    } catch (e) {
      this.presentAuthError(e, $r('app.string.s_a9b3c1d5e7'));
      this.code = '';
    } finally {
      this.busy = false;
    }
  }

  /** 服务端错误透传（envelope.message，本地化由后端按 Accept-Language 出），
   * 其余用 fallback 词条上 toast */
  private presentAuthError(e: Object, fallback: Resource): void {
    if (e instanceof HttpError && e.envelope !== null && e.envelope.message.length > 0) {
      this.env.errors.present(e.envelope.message, ErrorToastKind.Error, 4000);
      return;
    }
    this.presentResourceToast(fallback, ErrorToastKind.Error);
  }

  /** 按资源词条上 toast（present 收 string 不收 Resource，这里转一次） */
  private presentResourceToast(res: Resource, kind: ErrorToastKind): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const message: string = context.resourceManager.getStringSync(res.id);
    this.env.errors.present(message, kind);
  }

  private startCountdown(seconds: number): void {
    this.stopCountdown();
    this.countdown = seconds > 0 ? seconds : 0;
    if (seconds <= 0) {
      return;
    }
    this.countdownTimerId = setInterval((): void => {
      this.countdown -= 1;
      if (this.countdown <= 0) {
        this.stopCountdown();
      }
    }, 1000);
  }

  private stopCountdown(): void {
    if (this.countdownTimerId >= 0) {
      clearInterval(this.countdownTimerId);
      this.countdownTimerId = -1;
    }
    this.countdown = 0;
  }
}
