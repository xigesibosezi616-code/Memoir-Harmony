/**
 * 注销账号（10_BUILD_MANUAL.md 4.3；上架清单 A9：支持注册的 App 必须提供 App 内注销）。
 * 对应 iOS `DeleteAccountView.swift`。
 *
 * 三步：说清楚删什么、不删什么 → 证明是本人 → 最后确认一次（官方 AlertDialog，
 * 按钮纯官方默认样式随明暗自适应；R-ACCOUNT-07，U02 取代版）。
 *
 * ## 为什么要再验一次身份
 * 登录态只说明「这台手机登录着」，不说明「操作的是本人」。捡到一台解锁手机的人，
 * 不该能一键删掉别人的账号和全部来信——和换绑手机号同一个道理（ChangePhoneView）。
 * 验证码发给账号绑定的手机号（POST /auth/send-code 同一套防刷）。
 * 绑了华为账号的另外能用华为账号验证（U02 Q17 解法）：官方 LoginWithHuaweiIDButton
 * 重新走一次授权，拿 idToken + authorizationCode **一起**交 POST /me/delete——
 * 服务端验 idToken 并用授权码撤销华为账号授权（撤销失败不阻断注销）；
 * 授权码 5 分钟内有效、只能用一次，**不缓存**：取消注销时丢掉，下次重新授权。
 *
 * ## 删什么、不删什么（文案必须讲清楚）
 * 只删**我们服务器上**的账号数据。日记、照片、录音、已经收到的信都在用户自己
 * 的手机里，我们本来就拿不到，注销后照样在（R-ACCOUNT-08：本地日记一篇不少）。
 *
 * 错误直接写在这一页上（inlineError，不走路由级 toast——错误必须出现在
 * 用户正在看的输入框旁边，R-ACCOUNT-07）。
 * 路由：系统路由表（router_map.json → name `DeleteAccount`），账户页注销行推入。
 */
import { LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AuthLogic } from '../../services/auth/AuthLogic';
import { HuaweiIdProof, HuaweiAuthLogic } from '../../services/auth/HuaweiAuthLogic';
import { HttpError } from '../../services/http/HttpError';
import { STORAGE_KEY_SESSION_TICK } from '../../services/auth/UserSession';
import { SendCodeResponse } from '../../models/Api';

const DOMAIN = 0x0000;
const TAG = 'DeleteAccountView';

/** 顶栏一行的高（返回圆钮 + 居中标题） */
const TOP_BAR_ROW_HEIGHT_VP: number = 44;

@Builder
export function DeleteAccountBuilder() {
  DeleteAccountView()
}

@Component
export struct DeleteAccountView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 两步：0 = 说明（删什么、不删什么），1 = 验证是本人 */
  @State private step: number = 0;
  @State private code: string = '';
  @State private busy: boolean = false;
  /** 重发倒计时剩余秒数（后端 retryAfter 驱动） */
  @State private countdown: number = 0;
  /** 错误写在页上（服务端文案或本地化兜底），不出全局 toast（R-ACCOUNT-07） */
  @State private inlineError: string = '';
  /** 按绑定情况显示验证方式（U02 取代 R-ACCOUNT-07）：手机号验证码 / 华为账号 */
  @State private hasPhone: boolean = false;
  @State private hasHuawei: boolean = false;
  private countdownTimerId: number = -1;
  /** 进页时的手机号快照：注销成功后登录态清空，没有快照的话滑走动画里
   *  掩码手机号会塌掉一半（iOS 模拟器实测同款问题） */
  private currentPhone: string = '';
  private maskedCurrent: string = '';
  /** 华为验证凭证（idToken + authorizationCode）：授权码 5 分钟内有效、只能用一次，
   *  不缓存——取消注销丢掉，每次都重新授权（U02「不要缓存授权码」） */
  private huaweiProof: HuaweiIdProof | null = null;
  private navPathStack: NavPathStack = new NavPathStack();
  /** 华为账号验证按钮控制器（官方组件；回调在 aboutToAppear 注册） */
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
  }

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 22 }) {
            if (this.step === 0) {
              this.explainSection()
            } else {
              this.verifySection()
            }

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
      if (session === undefined || user === null) {
        // 入口只有账户页（已登录才有注销行）；登录态空直接退回
        this.navPathStack.pop();
        return;
      }
      // 按绑定情况显示验证方式（U02）：手机号 / 华为账号，一样都没绑走不了验证
      this.hasPhone = user.phone.length > 0;
      this.hasHuawei = user.bindings.indexOf('huawei') >= 0;
      if (!this.hasPhone && !this.hasHuawei) {
        this.navPathStack.pop();
        return;
      }
      this.currentPhone = user.phone;
      this.maskedCurrent = AuthLogic.maskedPhone(user.phone);
    })
  }

  // ---- 顶栏：返回圆钮（busy 时禁用）+ 居中标题（文档流内首行，随 Column 排、不下坠） ----

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
        .enabled(!this.busy)
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
        Text($r('app.string.s_b1fc6613b2'))
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

  // ---- 第一步：说明（删什么、不删什么、无法恢复） ----

  @Builder
  private explainSection() {
    Column({ space: 16 }) {
      Text($r('app.string.s_085de89c6f'))
        .fontSize(this.theme.headingFont.size)
        .fontWeight(this.theme.headingFont.weight)
        .fontFamily(this.theme.headingFont.family)
        .fontColor(this.theme.textPrimary)
        // 用户要求标题往下来一点（2026-10-24）
        .margin({ top: 12 })

      // 内容组：官方 List/ListItem（系统设置分组同款：单卡 + 官方分隔线）
      List() {
        ListItem() {
          this.notice($r('sys.symbol.trash'), $r('app.string.s_9e5cbe5e55'),
            $r('app.string.s_ebad4d402e'), this.theme.destructive)
        }
        ListItem() {
          this.notice($r('sys.symbol.character_book'), $r('app.string.s_b34f3cc999'),
            $r('app.string.s_10a55ee848'), this.theme.accent)
        }
        ListItem() {
          this.notice($r('sys.symbol.arrow_counterclockwise'), $r('app.string.s_877d91d42a'),
            $r('app.string.s_43680b11bb'), this.theme.textSecondary)
        }
      }
      .width('100%')
      .backgroundColor(this.theme.surfaceBackground)
      .borderRadius(12)
      .divider({ strokeWidth: 0.5, color: this.theme.border, startMargin: 14, endMargin: 14 })

      // 我已了解，继续：官方 Button 纯官方危险态（EMPHASIZED + ButtonRole.ERROR，
      // 颜色/字体全交系统随明暗自适应；R-THEME-10）
      Button($r('app.string.s_9545e4dc22'), {
        buttonStyle: ButtonStyleMode.EMPHASIZED,
        role: ButtonRole.ERROR,
        stateEffect: true
      })
        .type(ButtonType.Capsule)
        .width('100%')
        .margin({ top: 6 })
        .onClick((): void => {
          this.step = 1;
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 说明条目：图标 + 标题 + 正文（官方 ListItem 内，卡片底/分隔线由 List 统一给） */
  @Builder
  private notice(iconRes: Resource, titleRes: Resource, textRes: Resource,
    tint: ResourceColor) {
    Row({ space: 12 }) {
      SymbolGlyph(iconRes)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor([tint])
        .width(22)
      Column({ space: 4 }) {
        Text(titleRes)
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
        // 正文比标题小一档（用户反馈提示页正文偏大，2026-10-24）
        Text(textRes)
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding(14)
  }

  // ---- 第二步：验证是本人（按绑定情况：手机号验证码 / 华为账号 / 两者都给）----

  @Builder
  private verifySection() {
    Column({ space: 16 }) {
      if (this.hasPhone) {
        this.phoneVerifyPart()
      }

      if (this.hasHuawei) {
        if (this.hasPhone) {
          // 绑了手机号又绑了华为账号：两种验证方式之间给一行「或者」
          Text($r('app.string.s_573a605055'))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textTertiary)
            .alignSelf(ItemAlign.Center)
        } else {
          // 只绑了华为账号：标题直接告诉用户用绑定的华为账号验证
          Text($r('app.string.s_76923ad872'))
            .fontSize(this.theme.headingFont.size)
            .fontWeight(this.theme.headingFont.weight)
            .fontFamily(this.theme.headingFont.family)
            .fontColor(this.theme.textPrimary)
            .margin({ top: 12 })
        }

        // 华为账号验证：官方按钮重新走一次授权（U02；R-THEME-10 官方组件纯官方样式）
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

      // 错误写在这一页上（R-ACCOUNT-07）：服务端文案优先，本地化兜底
      if (this.inlineError.length > 0) {
        Text(this.inlineError)
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.destructive)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 手机号验证段（原有路径）：说明头 + 验证码输入行 + 红色注销按钮 */
  @Builder
  private phoneVerifyPart() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        Text($r('app.string.s_fee9c0540f'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)
        Text($r('app.string.s_dfd9e22f59'))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textSecondary)
        // 脱敏手机号是用户数据，不进本地化表
        Text(this.maskedCurrent)
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
      }
      .alignItems(HorizontalAlign.Start)

      Row({ space: 10 }) {
        TextInput({ text: this.code, placeholder: $r('app.string.s_83a302c43c') })
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
            this.code = AuthLogic.digitsOnly(value, 6);
            if (this.code.length > 0) {
              this.inlineError = '';
            }
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
              this.sendCode();
            }
          })
      }
      .alignItems(VerticalAlign.Center)

      // 注销账号：6 位验证码才可点，点了先过官方 AlertDialog 二次确认；
      // 两态逐主题配（R-THEME-10）：可用 = destructive 红底白字，
      // 禁用 = surface 底 + textTertiary 字（CoverEditor apply 同款，不用整块透明度降级）
      Button() {
        Row({ space: 8 }) {
          if (this.busy) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(Color.White)
          }
          Text($r('app.string.s_b1fc6613b2'))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.code.length === 6 ? Color.White : this.theme.textTertiary)
        }
        .justifyContent(FlexAlign.Center)
      }
      .type(ButtonType.Capsule)
      .backgroundColor(this.code.length === 6
        ? this.theme.destructive
        : this.theme.surfaceBackground)
      .enabled(this.code.length === 6 && !this.busy)
      .height(48)
      .width('100%')
      .onClick((): void => {
        this.confirmDelete();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 二次确认（官方 AlertDialog；按钮纯官方默认样式，随明暗自适应） ----

  /** 最后一步：确定要注销账号吗？此操作无法撤销。点了注销账号才算数 */
  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.s_68363aefdc'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.s_4d0b4688c7'),
        action: (): void => {}
      },
      secondaryButton: {
        value: $r('app.string.s_b1fc6613b2'),
        action: (): void => {
          this.deleteAccount();
        }
      }
    });
  }

  // ---- 华为账号验证注销（U02-3）----

  /** 官方按钮回调分流：取消/未登录静默；凭证要 idToken + authorizationCode 双全
   *  （缺一个服务端撤销不了授权）；拿到先过二次确认，授权码拿到就用、不缓存 */
  private onHuaweiCredential(error: BusinessError,
    credential: loginComponentManager.HuaweiIDCredential): void {
    if (error) {
      if (HuaweiAuthLogic.isSilentKitError(error.code)) {
        return;
      }
      hilog.error(DOMAIN, TAG, 'huawei verify failed: %{public}d %{public}s',
        error.code, error.message);
      this.inlineError = this.getString($r('app.string.s_a23663f119'));
      return;
    }
    const proof: HuaweiIdProof | null = HuaweiAuthLogic.deleteProofFor(
      credential.idToken, credential.authorizationCode);
    if (proof === null) {
      hilog.error(DOMAIN, TAG, 'huawei verify no idToken/authorizationCode');
      this.inlineError = this.getString($r('app.string.s_2b42a64cab'));
      return;
    }
    this.huaweiProof = proof;
    this.confirmDeleteWithHuawei();
  }

  /** 华为验证的二次确认（同验证码路径）：取消丢掉授权码，确认才交 /me/delete */
  private confirmDeleteWithHuawei(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.s_68363aefdc'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.s_4d0b4688c7'),
        action: (): void => {
          // 取消注销：授权码丢掉（5 分钟窗口内也不复用，下次重新授权）
          this.huaweiProof = null;
        }
      },
      secondaryButton: {
        value: $r('app.string.s_b1fc6613b2'),
        action: (): void => {
          this.deleteAccountWithHuawei();
        }
      }
    });
  }

  /** 华为验证注销：idToken + authorizationCode 一起交 /me/delete → 清登录态回根；
   *  服务端撤销失败不阻断注销（huaweiRevoked 客户端不区别对待，U02）；日记不动 */
  private async deleteAccountWithHuawei(): Promise<void> {
    if (this.busy) {
      return;
    }
    const proof: HuaweiIdProof | null = this.huaweiProof;
    if (proof === null) {
      return;
    }
    const session = this.env.session;
    const token: string | null = session === undefined ? null : session.token;
    if (token === null) {
      this.inlineError = this.getString($r('app.string.s_0e37efff8d'));
      this.huaweiProof = null;
      return;
    }
    this.busy = true;
    try {
      const auth = this.env.auth;
      if (auth === undefined) {
        return;
      }
      await auth.deleteAccountWithHuawei(proof.idToken, proof.authorizationCode, token);
      if (session !== undefined) {
        session.clear();
      }
      this.bumpSessionTick();
      this.presentResourceToast($r('app.string.s_2ca4a60f15'), ErrorToastKind.Success);
      // 退回设置根：账户页随 tick watch 自行退场，这里清完整栈（NavBar 主页不在栈内不受影响）
      this.navPathStack.clear();
    } catch (e) {
      // 403（不是绑定的那个华为账号）等服务端文案写在页上
      if (e instanceof HttpError) {
        hilog.error(DOMAIN, TAG,
          'delete with huawei failed: kind=%{public}s status=%{public}d body=%{public}s',
          e.kind, e.statusCode, e.body);
      }
      this.showError(e, $r('app.string.s_a23663f119'));
    } finally {
      this.huaweiProof = null;
      this.busy = false;
    }
  }

  // ---- 动作 ----

  /** 给当前绑定的手机号发验证码；不弹「验证码已发送」——错误要贴页，
   *  成功的反馈就是倒计时开始走（iOS 同款：toast 会被盖住的教训） */
  private async sendCode(): Promise<void> {
    if (this.busy || this.currentPhone.length === 0) {
      return;
    }
    this.inlineError = '';
    this.busy = true;
    try {
      const auth = this.env.auth;
      if (auth === undefined) {
        return;
      }
      const resp: SendCodeResponse = await auth.sendCode(this.currentPhone);
      this.startCountdown(resp.retryAfter);
    } catch (e) {
      this.showError(e, $r('app.string.s_e6f8a0b2c4'));
    } finally {
      this.busy = false;
    }
  }

  /** 注销：POST /me/delete → 服务器上的账号已删，本地登录态一并清；
   *  日记等本地数据一律不动（R-ACCOUNT-08）；退回设置根（账户页随 tick 自行退场） */
  private async deleteAccount(): Promise<void> {
    if (this.busy || this.code.length !== 6) {
      return;
    }
    const session = this.env.session;
    const token: string | null = session === undefined ? null : session.token;
    if (token === null) {
      this.inlineError = this.getString($r('app.string.s_0e37efff8d'));
      return;
    }
    this.busy = true;
    try {
      const auth = this.env.auth;
      if (auth === undefined) {
        return;
      }
      await auth.deleteAccount(this.code, token);
      if (session !== undefined) {
        session.clear();
      }
      this.bumpSessionTick();
      this.presentResourceToast($r('app.string.s_2ca4a60f15'), ErrorToastKind.Success);
      // 退回设置根：账户页随 tick watch 自行退场，这里清完整栈（NavBar 主页不在栈内不受影响）
      this.navPathStack.clear();
    } catch (e) {
      this.showError(e, $r('app.string.s_59b153249b'));
      // 验证码可能已被消费（错误次数也累计），失败后让用户重新输入
      this.code = '';
    } finally {
      this.busy = false;
    }
  }

  /** 错误写页上（inlineError）：服务端文案优先，其余用本地化兜底 */
  private showError(e: Object, fallback: Resource): void {
    if (e instanceof HttpError && e.envelope !== null && e.envelope.message.length > 0) {
      this.inlineError = e.envelope.message;
      return;
    }
    this.inlineError = this.getString(fallback);
  }

  /** 登录态变化信号：账户页 / 设置页账户卡 @Watch 刷新用 */
  private bumpSessionTick(): void {
    AppStorage.setOrCreate(STORAGE_KEY_SESSION_TICK,
      (AppStorage.get<number>(STORAGE_KEY_SESSION_TICK) ?? 0) + 1);
  }

  /** 按资源词条上 toast（present 收 string 不收 Resource，这里转一次） */
  private presentResourceToast(res: Resource, kind: ErrorToastKind): void {
    const message: string = this.getString(res);
    this.env.errors.present(message, kind);
  }

  /** Resource → string（resourceManager 同步取） */
  private getString(res: Resource): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringSync(res.id);
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
