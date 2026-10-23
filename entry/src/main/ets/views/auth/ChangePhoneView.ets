/**
 * 换绑手机号（10_BUILD_MANUAL.md 4.3）。对应 iOS `ChangePhoneView.swift`。
 *
 * ## 为什么要验两次（R-ACCOUNT-05 三件套）
 * **旧号证明「是本人」，新号证明「这号是你的」，缺一不可。**
 * 只验新号：捡到一台已解锁手机的人就能把账号改绑到自己名下；
 * 只验旧号：用户可能把账号绑到一个打错的号上，从此再也登不回来。
 *
 * 两步流：旧号验证码（本地暂存，不提前消费——服务端要求两码一起校验，
 * 提前单独验掉的话第二步失败就得重发旧码，白白多一次短信）→
 * 新号 + 新码 → POST /me/bindings/phone/change 一次换绑。
 * 两个验证码都走 POST /auth/send-code（与登录同一套防刷）。
 *
 * 成功：updateUser 刷快照 + 「手机号已换绑」+ 退回；失败 toast（服务端文案优先）。
 * 路由：系统路由表（router_map.json → name `ChangePhone`），账户页手机号行推入。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AuthLogic } from '../../services/auth/AuthLogic';
import { HttpError } from '../../services/http/HttpError';
import { STORAGE_KEY_SESSION_TICK } from '../../services/auth/UserSession';
import { SendCodeResponse } from '../../models/Api';

/** 顶栏一行的高（返回圆钮 + 居中标题） */
const TOP_BAR_ROW_HEIGHT_VP: number = 44;

@Builder
export function ChangePhoneBuilder() {
  ChangePhoneView()
}

@Component
export struct ChangePhoneView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 两步流：0 = 验证当前手机号，1 = 新手机号 + 新验证码 */
  @State private step: number = 0;
  @State private oldCode: string = '';
  @State private newPhone: string = '';
  @State private newCode: string = '';
  @State private busy: boolean = false;
  /** 重发倒计时剩余秒数（后端 retryAfter 驱动） */
  @State private countdown: number = 0;
  /** 旧号验证码是否已发出——没发过就不该让用户在那儿填 */
  @State private oldCodeSent: boolean = false;
  private countdownTimerId: number = -1;
  /** 当前绑定的手机号（onReady 从会话取；换绑成功后快照会变，进页快照留一份） */
  private currentPhone: string = '';
  private maskedCurrent: string = '';
  private navPathStack: NavPathStack = new NavPathStack();

  aboutToDisappear(): void {
    this.stopCountdown();
  }

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 22 }) {
            if (this.step === 0) {
              this.oldSection()
            } else {
              this.newSection()
            }

            this.primaryButton()

            Column()
              .width('100%')
              .height(this.safeAreaBottomVp + 32)
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
      .backgroundColor(this.theme.background)
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.background)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      const session = this.env.session;
      const user = session === undefined ? null : session.user;
      if (session === undefined || user === null || user.phone.length === 0) {
        // 入口只有账户页手机号行（已绑才显示），这里兜底：无手机号直接退回
        this.navPathStack.pop();
        return;
      }
      this.currentPhone = user.phone;
      this.maskedCurrent = AuthLogic.maskedPhone(user.phone);
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题（文档流内首行，随 Column 排、不下坠） ----

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
        Text($r('app.string.s_79b0ebdd1c'))
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
      // 纯展示层全宽盖在按钮行上，触摸穿透给下面的返回钮
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(TOP_BAR_ROW_HEIGHT_VP)
  }

  // ---- 第一步：验证当前手机号 ----

  @Builder
  private oldSection() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        Text($r('app.string.s_173e51e1e5'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)
        // 脱敏手机号是用户数据，不进本地化表
        Text(this.maskedCurrent)
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)

      Row({ space: 10 }) {
        TextInput({ text: this.oldCode, placeholder: $r('app.string.s_83a302c43c') })
          .type(InputType.Number)
          .maxLength(6)
          .fontSize(this.theme.bodyFont.size)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .placeholderColor(this.theme.textSecondary)
          .backgroundColor(this.theme.cardBackground)
          .borderRadius(12)
          .height(44)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.oldCode = AuthLogic.digitsOnly(value, 6);
          })

        Text(this.countdown > 0
          ? $r('app.string.s_132f0d719a', this.countdown)
          : $r('app.string.s_084f68942b'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.countdown > 0 ? this.theme.textTertiary : this.theme.accent)
          .onClick((): void => {
            if (this.countdown <= 0 && !this.busy) {
              this.sendCode(this.currentPhone);
            }
          })
      }
      .alignItems(VerticalAlign.Center)

      // 没发过码：提示码会发到当前绑定的手机号（iOS 同款；发过就不再占位）
      if (!this.oldCodeSent) {
        Text($r('app.string.s_b72205943e'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 第二步：新手机号 + 新验证码 ----

  @Builder
  private newSection() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        Text($r('app.string.s_50034b8b01'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)
        Text($r('app.string.s_d84664c768'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)

      TextInput({ text: this.newPhone, placeholder: $r('app.string.s_0d4dd89acf') })
        .type(InputType.Number)
        .maxLength(11)
        .fontSize(this.theme.bodyFont.size)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .placeholderColor(this.theme.textSecondary)
        .backgroundColor(this.theme.cardBackground)
        .borderRadius(12)
        .height(44)
        .onChange((value: string) => {
          this.newPhone = AuthLogic.digitsOnly(value, 11);
        })

      Row({ space: 10 }) {
        TextInput({ text: this.newCode, placeholder: $r('app.string.s_83a302c43c') })
          .type(InputType.Number)
          .maxLength(6)
          .fontSize(this.theme.bodyFont.size)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .placeholderColor(this.theme.textSecondary)
          .backgroundColor(this.theme.cardBackground)
          .borderRadius(12)
          .height(44)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.newCode = AuthLogic.digitsOnly(value, 6);
          })

        Text(this.countdown > 0
          ? $r('app.string.s_132f0d719a', this.countdown)
          : $r('app.string.s_084f68942b'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.countdown > 0 || !AuthLogic.isValidMainlandPhone(this.newPhone)
            ? this.theme.textTertiary : this.theme.accent)
          .onClick((): void => {
            if (this.countdown <= 0 && !this.busy &&
              AuthLogic.isValidMainlandPhone(this.newPhone)) {
              this.sendCode(this.newPhone);
            }
          })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 主按钮：下一步 / 确认换绑（LoginView 胶囊同款） ----

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
        Text(this.step === 0 ? $r('app.string.s_ea0ef2ae72')
          : $r('app.string.s_33a1272ec8'))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.cardBackground)
      }
      .justifyContent(FlexAlign.Center)
    }
    .type(ButtonType.Capsule)
    .backgroundColor(this.theme.accent)
    .opacity(this.canSubmit() ? 1 : 0.35)
    .enabled(this.canSubmit())
    .height(48)
    .width('100%')
    .onClick((): void => {
      this.submit();
    })
  }

  /** 主按钮可点：第一步旧码 6 位；第二步新号 11 位 + 新码 6 位 */
  private canSubmit(): boolean {
    if (this.busy) {
      return false;
    }
    if (this.step === 0) {
      return this.oldCode.length === 6;
    }
    return AuthLogic.isValidMainlandPhone(this.newPhone) && this.newCode.length === 6;
  }

  // ---- 动作 ----

  /** 发验证码（当前号 / 新号共用）：成功起倒计时；第一步标记已发 */
  private async sendCode(phone: string): Promise<void> {
    if (this.busy || !AuthLogic.isValidMainlandPhone(phone)) {
      return;
    }
    this.busy = true;
    try {
      const auth = this.env.auth;
      if (auth === undefined) {
        return;
      }
      const resp: SendCodeResponse = await auth.sendCode(phone);
      if (this.step === 0) {
        this.oldCodeSent = true;
      }
      this.startCountdown(resp.retryAfter);
      this.presentResourceToast($r('app.string.s_4e09cf222e'), ErrorToastKind.Success);
    } catch (e) {
      this.presentAuthError(e, $r('app.string.s_e6f8a0b2c4'));
    } finally {
      this.busy = false;
    }
  }

  /** 提交：第一步只本地暂存进第二步（旧码不提前消费）；第二步一次换绑 */
  private submit(): void {
    if (this.step === 0) {
      if (this.oldCode.length !== 6 || this.busy) {
        return;
      }
      this.step = 1;
      this.stopCountdown();
      return;
    }
    this.changePhone();
  }

  /** 换绑：POST /me/bindings/phone/change（两码一起校验）；成功刷快照退回 */
  private async changePhone(): Promise<void> {
    if (this.busy || !this.canSubmit()) {
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
      const resp = await auth.changePhone(this.oldCode, this.newPhone, this.newCode, token);
      if (session !== undefined) {
        session.updateUser(resp.user);
      }
      this.bumpSessionTick();
      this.presentResourceToast($r('app.string.s_e561c3d4bd'), ErrorToastKind.Success);
      this.navPathStack.pop();
    } catch (e) {
      this.presentAuthError(e, $r('app.string.s_129af6c2eb'));
      this.newCode = '';
    } finally {
      this.busy = false;
    }
  }

  /** 登录态变化信号：设置页账户卡 / 账户页 @Watch 刷新用 */
  private bumpSessionTick(): void {
    AppStorage.setOrCreate(STORAGE_KEY_SESSION_TICK,
      (AppStorage.get<number>(STORAGE_KEY_SESSION_TICK) ?? 0) + 1);
  }

  /** 服务端错误透传（envelope.message），其余用 fallback 词条上 toast */
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
