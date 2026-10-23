/**
 * 设置 →「账户」二级页（10_BUILD_MANUAL.md 4.3）。对应 iOS `SettingsAccountView.swift`。
 *
 * 🔴「未绑定手机号」的红色警告不在这里，而在一级页账户卡上（R-ACCOUNT-03，
 * 2026-08-12 账号分裂事故对策——收进二级页等于取消警告）；这里只保留可操作入口：
 * 未绑时行值标红 + 红色 footer。
 *
 * - 昵称：编辑弹窗 → PATCH /me（≤64，空串 = 清空，R-ACCOUNT-06）。成功就地拷贝
 *   快照（updateUser），不为一个字段再跑一趟 GET /me（iOS 同款；下次进页与服务端对齐）
 * - 手机号：已绑 → ChangePhone 换绑两步流；未绑 → Login bindPhone 模式
 * - 退出登录：官方 AlertDialog 确认（按钮纯官方默认样式，随明暗自适应）
 *   → session.clear()；本地日记一律不动（R-ACCOUNT-08）
 * - 注销账号：单独一组、红色、放最底 + footer 说明日记不受影响（上架清单 A9：
 *   支持注册的 App 必须提供 App 内注销；与退出登录用颜色区分——暂时离开 vs 永久删除）
 * - 退出 / 注销后登录态空了：本页自动退回上一级（iOS onChange(isLoggedIn) 同款），
 *   别把用户留在一张空页上
 *
 * 路由：系统路由表（router_map.json → name `Account`），设置页账户卡推入。
 * 华为账号绑定行（U02）后端 /auth/huawei 未实现（09 Q1），4.4 再加，不预留死 UI。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { STORAGE_KEY_SESSION_TICK } from '../../services/auth/UserSession';
import { AuthLogic } from '../../services/auth/AuthLogic';
import { HttpError } from '../../services/http/HttpError';
import { UserDTO } from '../../models/Api';

/** 顶栏一行的高（返回圆钮 + 居中标题） */
const TOP_BAR_ROW_HEIGHT_VP: number = 44;

@Builder
export function SettingsAccountBuilder() {
  SettingsAccountView()
}

@Component
export struct SettingsAccountView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @StorageProp(STORAGE_KEY_SESSION_TICK) @Watch('onSessionTick') sessionTick: number = 0;

  @State private displayName: string = '';
  @State private maskedPhone: string = '';
  /** '' = 未绑定手机号（行值标红 + 红色 footer） */
  @State private phoneBound: boolean = false;
  @State private showNicknameEditor: boolean = false;
  @State private nicknameDraft: string = '';
  @State private savingNickname: boolean = false;

  private navPathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.refreshFromSession();
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.topBar()

          Scroll() {
            Column({ space: 20 }) {
              // 账户信息组：昵称 + 手机号（未绑时为绑定入口 + 红色 footer）
              Column() {
                this.nicknameRow()
                Divider()
                  .color(this.theme.border)
                  .strokeWidth(0.5)
                  .margin({ left: 20 })
                this.phoneRow()
              }
              .borderRadius(16)
              .backgroundColor(this.theme.cardBackground)
              .width('100%')

              // 退出登录（单独一组；确认走官方 AlertDialog）
              Row({ space: 10 }) {
                SymbolGlyph($r('sys.symbol.power'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.theme.textSecondary])
                  .width(20)
                Text($r('app.string.s_094774b4a7'))
                  .fontSize(this.theme.bodyFont.size)
                  .fontWeight(this.theme.bodyFont.weight)
                  .fontFamily(this.theme.bodyFont.family)
                  .fontColor(this.theme.textPrimary)
              }
              .width('100%')
              .padding({ top: 15, bottom: 15, left: 20, right: 20 })
              .borderRadius(16)
              .backgroundColor(this.theme.cardBackground)
              .onClick((): void => {
                this.confirmLogout();
              })

              // 注销账号：红色 + 放最底，与退出登录区分开（暂时离开 vs 永久删除）
              Column({ space: 8 }) {
                Row({ space: 10 }) {
                  SymbolGlyph($r('sys.symbol.person_crop_circle_dashed'))
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor([this.theme.destructive])
                    .width(20)
                  Text($r('app.string.s_b1fc6613b2'))
                    .fontSize(this.theme.bodyFont.size)
                    .fontWeight(this.theme.bodyFont.weight)
                    .fontFamily(this.theme.bodyFont.family)
                    .fontColor(this.theme.destructive)
                }
                .width('100%')
                .padding({ top: 15, bottom: 15, left: 20, right: 20 })
                .borderRadius(16)
                .backgroundColor(this.theme.cardBackground)
                .onClick((): void => {
                  this.navPathStack.pushPathByName('DeleteAccount', '');
                })

                Text($r('app.string.s_295cb60c39'))
                  .fontSize(this.theme.labelFont.size)
                  .fontWeight(this.theme.labelFont.weight)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textTertiary)
                  .padding({ left: 8, right: 8 })
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Column()
                .width('100%')
                .height(this.safeAreaBottomVp + 88)
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

        // 昵称编辑弹窗（PATCH /me；成功就地改本地快照）
        if (this.showNicknameEditor) {
          this.nicknameDialog()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.background)
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.background)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      this.refreshFromSession();
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
        Text($r('app.string.s_c3d92b20c8'))
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

  // ---- 昵称行：值 = 昵称 / 未设置 ----

  @Builder
  private nicknameRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.pencil_line'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_25124ed74c'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
      Blank()
      Text(this.displayName.length > 0 ? this.displayName : this.unsetLabel())
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 160 })
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textTertiary])
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.nicknameDraft = this.displayName;
      this.showNicknameEditor = true;
    })
  }

  // ---- 手机号行：已绑 → 换绑；未绑 → 绑定入口 + 红色 footer ----

  @Builder
  private phoneRow() {
    Column() {
      if (this.phoneBound) {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.phone'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textSecondary])
            .width(20)
          Text($r('app.string.s_5a9cc5e891'))
            .fontSize(this.theme.bodyFont.size)
            .fontWeight(this.theme.bodyFont.weight)
            .fontFamily(this.theme.bodyFont.family)
            .fontColor(this.theme.textPrimary)
          Blank()
          Text(this.maskedPhone)
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textTertiary)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textTertiary])
        }
        .width('100%')
        .padding({ top: 15, bottom: 15, left: 20, right: 20 })
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.navPathStack.pushPathByName('ChangePhone', '');
        })
      } else {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.destructive])
            .width(20)
          Text($r('app.string.s_7fbe49401c'))
            .fontSize(this.theme.bodyFont.size)
            .fontWeight(this.theme.bodyFont.weight)
            .fontFamily(this.theme.bodyFont.family)
            .fontColor(this.theme.textPrimary)
          Blank()
          Text($r('app.string.s_3bf179d8d0'))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.destructive)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textTertiary])
        }
        .width('100%')
        .padding({ top: 15, bottom: 15, left: 20, right: 20 })
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.navPathStack.pushPathByName('Login', 'bindPhone');
        })

        // 红色 footer：手机号是账号的唯一凭据（一级页警告的补充说明）
        Text($r('app.string.s_eb2a123165'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.destructive)
          .padding({ left: 20, right: 20, bottom: 14 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 昵称编辑弹窗（BookDetail deleteConfirmDialog 同款内联浮层） ----

  @Builder
  private nicknameDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.showNicknameEditor = false;
        })

      Column({ space: 18 }) {
        Text($r('app.string.s_25124ed74c'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)

        Text($r('app.string.s_212c3cace3'))
          .fontSize(13)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textSecondary)
          .textAlign(TextAlign.Center)

        TextInput({ text: this.nicknameDraft, placeholder: $r('app.string.s_83f9f94e0b') })
          .maxLength(64)
          .fontSize(this.theme.bodyFont.size)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .placeholderColor(this.theme.textSecondary)
          .backgroundColor(this.theme.surfaceBackground)
          .borderRadius(12)
          .height(44)
          .onChange((value: string) => {
            this.nicknameDraft = value;
          })

        Row({ space: 12 }) {
          Button({ stateEffect: true }) {
            Text($r('app.string.s_4d0b4688c7'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.textSecondary)
          }
          .layoutWeight(1)
          .padding({ top: 11, bottom: 11 })
          .backgroundColor(this.theme.surfaceBackground)
          .borderRadius(12)
          .border({ width: 0.5, color: this.theme.border })
          .onClick((): void => {
            this.showNicknameEditor = false;
          })

          Button({ stateEffect: true }) {
            Row({ space: 6 }) {
              if (this.savingNickname) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color(this.theme.cardBackground)
              }
              Text($r('app.string.s_fadf24dbc5'))
                .fontSize(this.theme.captionFont.size)
                .fontWeight(this.theme.captionFont.weight)
                .fontFamily(this.theme.captionFont.family)
                .fontColor(this.theme.cardBackground)
            }
            .justifyContent(FlexAlign.Center)
          }
          .layoutWeight(1)
          .padding({ top: 11, bottom: 11 })
          .backgroundColor(this.theme.accent)
          .borderRadius(12)
          .enabled(!this.savingNickname)
          .onClick((): void => {
            this.saveNickname();
          })
        }
      }
      .padding({ left: 22, right: 22, top: 24, bottom: 24 })
      .constraintSize({ maxWidth: 320 })
      .backgroundColor(this.theme.cardBackground)
      .borderRadius(20)
    }
    .width('100%')
    .height('100%')
  }

  // ---- 退出登录确认（官方 AlertDialog；按钮纯官方默认样式，随明暗自适应） ----

  /** 退出登录确认：官方 AlertDialog。按钮字体大小/颜色全交系统（R-THEME-10） */
  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.s_0b1c024ac9'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.s_4d0b4688c7'),
        action: (): void => {}
      },
      secondaryButton: {
        value: $r('app.string.s_094774b4a7'),
        action: (): void => {
          this.logout();
        }
      }
    });
  }

  // ---- 动作 ----

  /** 保存昵称：PATCH /me 成功就地拷贝快照（R-ACCOUNT-06：≤64、空串 = 清空）；
   *  失败 toast（envelope.message 优先，fallback 昵称保存失败），弹窗先关（iOS 同款） */
  private async saveNickname(): Promise<void> {
    if (this.savingNickname) {
      return;
    }
    const session = this.env.session;
    const user: UserDTO | null = session === undefined ? null : session.user;
    const token: string | null = session === undefined ? null : session.token;
    if (user === null || token === null) {
      this.showNicknameEditor = false;
      this.presentResourceToast($r('app.string.s_0e37efff8d'), ErrorToastKind.Error);
      return;
    }
    const trimmed: string = this.nicknameDraft.trim();
    this.savingNickname = true;
    try {
      const auth = this.env.auth;
      if (auth === undefined) {
        return;
      }
      await auth.updateDisplayName(trimmed, token);
      if (session !== undefined) {
        session.updateUser(new UserDTO(user.id, user.phone, trimmed,
          user.penPalName, user.bindings));
      }
      this.showNicknameEditor = false;
      this.refreshFromSession();
      this.bumpSessionTick();
    } catch (e) {
      this.showNicknameEditor = false;
      this.presentAuthError(e, $r('app.string.s_c460390c74'));
    } finally {
      this.savingNickname = false;
    }
  }

  /** 退出登录：只清会话，本地日记一律不动（R-ACCOUNT-08）；pop 交给 tick watch */
  private logout(): void {
    const session = this.env.session;
    if (session !== undefined) {
      session.clear();
    }
    this.bumpSessionTick();
  }

  /** 登录 / 401 / 注销信号 → 刷新字段；登录态空了自动退回（iOS onChange 同款） */
  onSessionTick(): void {
    const session = this.env.session;
    if (session !== undefined && !session.isLoggedIn()) {
      this.navPathStack.pop();
      return;
    }
    this.refreshFromSession();
  }

  /** 从会话快照刷新昵称 / 手机号展示 */
  private refreshFromSession(): void {
    const session = this.env.session;
    const user: UserDTO | null = session === undefined ? null : session.user;
    if (session === undefined || !session.isLoggedIn() || user === null) {
      this.displayName = '';
      this.maskedPhone = '';
      this.phoneBound = false;
      return;
    }
    this.displayName = user.displayName;
    this.phoneBound = user.phone.length > 0;
    this.maskedPhone = AuthLogic.maskedPhone(user.phone);
  }

  /** 未设置占位词条（独立方法防 @Builder 内三元过载） */
  private unsetLabel(): string {
    return this.getString($r('app.string.s_55a04b58cd'));
  }

  /** 登录态变化信号：设置页账户卡 / 本页 @Watch 刷新用 */
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
}
