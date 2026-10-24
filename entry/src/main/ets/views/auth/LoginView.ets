/**
 * 手机号登录页（10_BUILD_MANUAL.md 4.2/4.3；AUTH_DESIGN.md §6 两步流）。
 * 对应 iOS `LoginView.swift`（login / bindPhone 双模式）。
 *
 * 两步流：手机号 → 验证码；6 位自动提交；重发倒计时由后端 retryAfter 驱动；
 * 命中频控（429）按顶层 retryAfter 恢复倒计时（杀 App 重进立刻点重发的场景）。
 * 登录不强制：写日记永远不需要登录，这里只服务 AI 信件等云端能力。
 *
 * 模式（路由参数，pushPathByName('Login', param)）：
 * - ''（登录）：验证码 → POST /auth/verify-code → establish
 * - 'bindPhone'（补绑手机号，需已登录）：验证码 → POST /me/bindings/phone；
 *   switchedAccount == true 时服务端已把绑定转移到老账号并删掉空壳——
 *   本地 token 指向的身份不存在了，必须用返回 token+user 覆盖（establish），
 *   并提示「已找回你的账号」（R-ACCOUNT-04）；否则只刷快照（updateUser）。
 *
 * 华为账号登录（U02 R-ACCOUNT-09）：官方 LoginWithHuaweiIDButton（loginType: ID）
 * 放手机号登录下面（仅登录模式），拿凭据 idToken 交 POST /auth/huawei——
 * unionID / openID 不上送（服务端只认验过签的 idToken）。
 * 三分支：503 huawei_disabled → 「华为账号登录暂未开放，请先用手机号登录」；
 * 用户取消 / 未登录华为账号 → 静默；其他失败 → 「华为账号授权失败」+ 完整日志。
 *
 * 路由：系统路由表（router_map.json → name `Login`），设置页推入；
 * 悬浮 Tab 栏在页面上期间隐藏（STORAGE_KEY_HIDE_TAB_BAR，接近日志 sheet 盖全屏的语义）。
 */
import { LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { STORAGE_KEY_HIDE_TAB_BAR, STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AuthLogic } from '../../services/auth/AuthLogic';
import { HuaweiIdProof, HuaweiAuthLogic } from '../../services/auth/HuaweiAuthLogic';
import { HttpError } from '../../services/http/HttpError';
import { STORAGE_KEY_SESSION_TICK } from '../../services/auth/UserSession';
import { SendCodeResponse, AuthResponse, BindPhoneResponse } from '../../models/Api';

const DOMAIN = 0x0000;
const TAG = 'LoginView';

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

  /** 模式：0 = 登录，1 = 补绑手机号（bindPhone；路由参数 'bindPhone'） */
  @State private mode: number = 0;
  /** 两步流：0 = 手机号步，1 = 验证码步（iOS Step.phone / .code） */
  @State private step: number = 0;
  @State private phone: string = '';
  @State private code: string = '';
  @State private busy: boolean = false;
  /** 重发倒计时剩余秒数（后端 retryAfter 驱动） */
  @State private countdown: number = 0;
  private countdownTimerId: number = -1;
  private navPathStack: NavPathStack = new NavPathStack();
  /** 华为账号登录按钮控制器（官方组件；回调在 aboutToAppear 注册） */
  private huaweiButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController();

  aboutToAppear(): void {
    this.huaweiButtonController.onClickLoginWithHuaweiIDButton(
      (error: BusinessError, credential: loginComponentManager.HuaweiIDCredential): void => {
        this.onHuaweiCredential(error, credential);
      });
  }

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
            Text(this.titleText())
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

          // 华为账号登录（U02 R-ACCOUNT-01/09）：官方按钮组件按华为按钮规范放手机号登录
          // 下面；仅登录模式（bindPhone 模式不加），手机号步才出现（进了验证码步已选定短信）
          if (this.mode === 0 && this.step === 0) {
            LoginWithHuaweiIDButton({
              params: {
                style: loginComponentManager.Style.BUTTON_RED,
                borderRadius: 24,
                loginType: loginComponentManager.LoginType.ID,
                supportDarkMode: true
              },
              controller: this.huaweiButtonController
            })
            .height(48)
            .width('100%')
          }

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
      // 模式由路由参数带进来（设置页账户卡 ''；账户页补绑 'bindPhone'）
      if (ctx.pathInfo.param === 'bindPhone') {
        this.mode = 1;
      }
    })
    .onShown((): void => {
      AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, true);
    })
    .onHidden((): void => {
      AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, false);
    })
  }

  /** 页面标题：登录模式 = 手机号登录；补绑模式 = 绑定手机号；验证码步两模式同文案 */
  private titleText(): Resource {
    if (this.step === 1) {
      return $r('app.string.s_5c3e9b7a12');
    }
    if (this.mode === 1) {
      return $r('app.string.s_7fbe49401c');
    }
    return $r('app.string.s_f2d81a9c46');
  }

  /** 副标题：手机号步 = 模式说明；验证码步 = 已发送至掩码手机号 */
  private subtitleText(): Resource {
    if (this.step === 0 && this.mode === 1) {
      return $r('app.string.s_06f6dfc980');
    }
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
          this.submitCode();
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
        Text(this.primaryButtonText())
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
        this.submitCode();
      }
    })
  }

  /** 主按钮文案：手机号步 = 获取验证码；验证码步按模式 = 登录 / 绑定 */
  private primaryButtonText(): Resource {
    if (this.step === 0) {
      return $r('app.string.s_084f68942b');
    }
    if (this.mode === 1) {
      return $r('app.string.s_6aed7c48be');
    }
    return $r('app.string.s_21f1e88275');
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

  /** 验证码步提交入口：按模式分发（登录 / 补绑手机号） */
  private submitCode(): void {
    if (this.mode === 1) {
      this.bindPhone();
    } else {
      this.login();
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
        this.bumpSessionTick();
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

  /** 补绑手机号（R-ACCOUNT-04）：switchedAccount 时服务端已把绑定转移到老账号并删空壳，
   * 本地 token 指向的身份不存在——必须用返回 token+user 覆盖（establish）并提示「已找回你的账号」；
   * 正常绑定只刷快照（updateUser）。409 冲突（号已属于别人）由 envelope.message 透传。 */
  private async bindPhone(): Promise<void> {
    if (this.busy || this.code.length !== 6) {
      return;
    }
    const session = this.env.session;
    const token: string | null = session === undefined ? null : session.token;
    if (token === null) {
      this.presentResourceToast($r('app.string.s_0e37efff8d'), ErrorToastKind.Error);
      this.navPathStack.pop();
      return;
    }
    this.busy = true;
    try {
      const auth = this.env.auth;
      if (auth === undefined) {
        return;
      }
      const resp: BindPhoneResponse = await auth.bindPhone(this.phone, this.code, token);
      if (resp.switchedAccount && resp.token.length > 0 && session !== undefined) {
        session.establish(resp.token, resp.user);
        this.presentResourceToast($r('app.string.s_221b549139'), ErrorToastKind.Success);
      } else {
        if (session !== undefined) {
          session.updateUser(resp.user);
        }
        this.presentResourceToast($r('app.string.s_cecceb5a0a'), ErrorToastKind.Success);
      }
      this.bumpSessionTick();
      this.stopCountdown();
      this.navPathStack.pop();
    } catch (e) {
      // 线上 /me/bindings/phone 疑似 500（2026-10-25 实测，消费码后绑定步崩溃）：
      // 打 kind/status/body 供后端定位，待服务端修复后可移除。
      if (e instanceof HttpError && e.statusCode >= 500) {
        hilog.error(DOMAIN, TAG,
          'bind phone failed: kind=%{public}s status=%{public}d body=%{public}s',
          e.kind, e.statusCode, e.body);
      }
      this.presentAuthError(e, $r('app.string.s_b94e9a68cd'));
      this.code = '';
    } finally {
      this.busy = false;
    }
  }

  /** 登录态变化信号：设置页（4.3 账户卡）@Watch 刷新用（RDB 无观察机制同款补法） */
  private bumpSessionTick(): void {
    AppStorage.setOrCreate(STORAGE_KEY_SESSION_TICK,
      (AppStorage.get<number>(STORAGE_KEY_SESSION_TICK) ?? 0) + 1);
  }

  // ---- 华为账号登录（U02-1）----

  /** 官方按钮回调分流：取消/未登录静默；无凭证单独提示；拿到 idToken 走 /auth/huawei */
  private onHuaweiCredential(error: BusinessError,
    credential: loginComponentManager.HuaweiIDCredential): void {
    if (error) {
      // 用户取消 / 未登录华为账号：静默回登录页，不弹错（U02 R-ACCOUNT-09）
      if (HuaweiAuthLogic.isSilentKitError(error.code)) {
        return;
      }
      hilog.error(DOMAIN, TAG, 'huawei login failed: %{public}d %{public}s',
        error.code, error.message);
      this.presentResourceToast($r('app.string.s_a23663f119'), ErrorToastKind.Error);
      return;
    }
    const proof: HuaweiIdProof | null = HuaweiAuthLogic.proofFor(
      credential.idToken, credential.authorizationCode);
    if (proof === null) {
      hilog.error(DOMAIN, TAG, 'huawei login no idToken in credential');
      this.presentResourceToast($r('app.string.s_2b42a64cab'), ErrorToastKind.Error);
      return;
    }
    this.loginWithHuawei(proof.idToken);
  }

  /** 华为账号登录：POST /auth/huawei → establish（同验码登录）；503 huawei_disabled
   *  提示「暂未开放，请先用手机号登录」，其余服务端文案透传 / fallback 授权失败 */
  private async loginWithHuawei(idToken: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const auth = this.env.auth;
      if (auth === undefined) {
        return;
      }
      const resp: AuthResponse = await auth.loginWithHuawei(idToken);
      const session = this.env.session;
      if (session !== undefined) {
        session.establish(resp.token, resp.user);
        this.bumpSessionTick();
      }
      this.presentResourceToast($r('app.string.s_8d4a2f6e90'), ErrorToastKind.Success);
      this.navPathStack.pop();
    } catch (e) {
      if (e instanceof HttpError && e.envelope !== null && e.envelope.code === 'huawei_disabled') {
        // 后端还没配华为（AGC 密钥未配齐）：提示后手机号登录照常不受影响
        this.presentResourceToast($r('app.string.s_c3758b0795'), ErrorToastKind.Error);
        return;
      }
      this.presentAuthError(e, $r('app.string.s_a23663f119'));
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
