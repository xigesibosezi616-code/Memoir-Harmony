/**
 * 设置 →「尺素会员」页（10_BUILD_MANUAL.md 7.1/7.2；U02 R-MEMBER-11）。
 * 对应 iOS `Views/Membership/MembershipStatusView.swift`。
 *
 * 会员状态页：方案、有效期至、管理订阅（`iap.showManagedSubscriptions` 打开
 * 系统的订阅管理页——换方案、退订只能在华为那边做）、恢复购买。
 * 测试期假会员（TEST_UNLOCK）多一节「关闭测试会员」回到免费版。
 *
 * 非会员不会进这页（设置会员行非会员直进付费页）；万一进来了
 * （假会员刚被关掉等）显示「了解尺素会员」引导去付费页。
 *
 * 路由：系统路由表（router_map.json → name `Membership`）。
 */
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { fullDate } from '../../services/AppDateFormatters';
import { PostingRun } from '../../models/LetterPostingFlightGeometry';
import { WaxSeal } from '../postbox/WaxSeal';
import { MembershipManager, PRODUCT_ID_MONTHLY,
  TEST_UNLOCK, STORAGE_KEY_MEMBERSHIP_TICK } from '../../services/membership/MembershipManager';

/** 会员页火漆印直径（ICONS.md 用法表：会员页 60vp） */
const SEAL_SIZE_VP: number = 60;

@Builder
export function MembershipBuilder() {
  MembershipView()
}

@Component
export struct MembershipView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  /** 会员状态变化（权益到账 / 假会员开关）→ 重读状态 */
  @StorageProp(STORAGE_KEY_MEMBERSHIP_TICK) @Watch('reloadState')
  membershipTick: number = 0;

  /** 火漆印面：用户昵称首字（「素」兜底） */
  @State private sealMark: string = '素';
  @State private isMember: boolean = false;
  @State private isTestMember: boolean = false;
  /** 月付 = true（年付 = false） */
  @State private isMonthly: boolean = false;
  /** 有效期（毫秒）；0 = 不显示这行 */
  @State private expiresAtMs: number = 0;
  /** 恢复购买进行中 */
  @State private restoring: boolean = false;
  /** 恢复购买结果（成功 / 失败提示）；空串 = 没有 */
  @State private restoreMessage: string = '';

  private navPathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    const session = this.env.session;
    const user = session !== undefined && session.isLoggedIn() ? session.user : null;
    this.sealMark = PostingRun.sealMarkOf(user !== null ? user.displayName : undefined);
    this.reloadState();
  }

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          if (this.isMember) {
            Column({ space: 20 }) {
              // 印 + 标题
              Column({ space: 12 }) {
                WaxSeal({ sizeVp: SEAL_SIZE_VP, mark: this.sealMark })
                Text($r('app.string.s_7402638ab2'))
                  .fontSize(this.theme.headingFont.size)
                  .fontWeight(this.theme.headingFont.weight)
                  .fontFamily(this.theme.headingFont.family)
                  .fontColor(this.theme.textPrimary)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 12, bottom: 12 })

              // 方案 / 有效期
              Column() {
                this.valueRow($r('app.string.s_0fee25f074'),
                  this.isMonthly ? $r('app.string.s_ccf97f8d85') : $r('app.string.s_1017debe4c'))
                if (this.expiresAtMs > 0) {
                  this.rowDivider()
                  this.valueRow($r('app.string.s_37eb470096'),
                    fullDate(new Date(this.expiresAtMs), this.appLanguage))
                }
              }
              .borderRadius(16)
              .backgroundColor(this.theme.settingsCardBackground)
              .width('100%')

              // 管理订阅 / 恢复购买
              Column() {
                this.actionRow($r('app.string.s_2e529b5331'), (): void => {
                  this.openManagedSubscriptions();
                })
                this.rowDivider()
                Row() {
                  Text($r('app.string.s_781c5c7050'))
                    .fontSize(this.theme.bodyFont.size)
                    .fontWeight(this.theme.bodyFont.weight)
                    .fontFamily(this.theme.bodyFont.family)
                    .fontColor(this.theme.textPrimary)
                    .layoutWeight(1)
                  if (this.restoring) {
                    LoadingProgress()
                      .width(18)
                      .height(18)
                      .color(this.theme.textTertiary)
                  }
                }
                .width('100%')
                .padding({ top: 14, bottom: 14, left: 16, right: 16 })
                .alignItems(VerticalAlign.Center)
                .onClick((): void => {
                  this.restore();
                })
              }
              .borderRadius(16)
              .backgroundColor(this.theme.settingsCardBackground)
              .width('100%')

              // footer：恢复结果 + 管理订阅说明
              Column({ space: 6 }) {
                if (this.restoreMessage.length > 0) {
                  Text(this.restoreMessage)
                    .fontSize(this.theme.labelFont.size)
                    .fontWeight(this.theme.labelFont.weight)
                    .fontFamily(this.theme.labelFont.family)
                    .fontColor(this.theme.textTertiary)
                }
                Text($r('app.string.s_09638dca5f'))
                  .fontSize(this.theme.labelFont.size)
                  .fontWeight(this.theme.labelFont.weight)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textTertiary)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 8, right: 8 })

              // 测试期假会员：可关掉回到免费版（上架前 TEST_UNLOCK 关掉即整节消失）
              if (this.isTestMember) {
                Column() {
                  Text($r('app.string.s_172e681d96'))
                    .fontSize(this.theme.bodyFont.size)
                    .fontWeight(this.theme.bodyFont.weight)
                    .fontFamily(this.theme.bodyFont.family)
                    .fontColor(this.theme.destructive)
                    .width('100%')
                    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
                    .onClick((): void => {
                      this.closeTestMembership();
                    })
                }
                .borderRadius(16)
                .backgroundColor(this.theme.settingsCardBackground)
                .width('100%')

                Text($r('app.string.s_1e2443b94b'))
                  .fontSize(this.theme.labelFont.size)
                  .fontWeight(this.theme.labelFont.weight)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textTertiary)
                  .padding({ left: 8, right: 8 })
              }

              // 底部：手势条让位
              Column().width('100%').height(this.safeAreaBottomVp + 32)
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
          } else {
            // 非会员（不会从设置进来；假会员刚关掉等场景）：引导去付费页
            Column({ space: 14 }) {
              WaxSeal({ sizeVp: SEAL_SIZE_VP, mark: this.sealMark })
              Text($r('app.string.s_7402638ab2'))
                .fontSize(this.theme.titleFont.size)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.theme.textPrimary)
              Text($r('app.string.s_cf9d76b498'))
                .fontSize(this.theme.captionFont.size)
                .fontColor(this.theme.textTertiary)
                .onClick((): void => {
                  this.navPathStack.pushPathByName('Paywall', '');
                })

              // 底部：手势条让位
              Column().width('100%').height(this.safeAreaBottomVp + 32)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .padding({ bottom: 64 })
          }
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.safeAreaTopVp })
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.settingsPageBackground)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题（各二级页同款） ----

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
        Text($r('app.string.s_7402638ab2'))
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

  // ---- 行组件 ----

  /** 左标签 + 右值行 */
  @Builder
  private valueRow(label: Resource, value: Resource | string) {
    Row() {
      Text(label)
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      if (typeof value === 'string') {
        Text(value)
          .fontSize(this.theme.captionFont.size)
          .fontColor(this.theme.textTertiary)
      } else {
        Text(value)
          .fontSize(this.theme.captionFont.size)
          .fontColor(this.theme.textTertiary)
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  /** 可点动作行 */
  @Builder
  private actionRow(label: Resource, onTap: () => void) {
    Text(label)
      .fontSize(this.theme.bodyFont.size)
      .fontWeight(this.theme.bodyFont.weight)
      .fontFamily(this.theme.bodyFont.family)
      .fontColor(this.theme.textPrimary)
      .width('100%')
      .padding({ top: 14, bottom: 14, left: 16, right: 16 })
      .onClick(onTap)
  }

  @Builder
  private rowDivider() {
    Row()
      .height(0.5)
      .backgroundColor(this.theme.border)
      .margin({ left: 16, right: 16 })
      .width('100%')
  }

  // ---- 动作 ----

  /** 会员状态变化（tick）→ 重读本机快照 */
  private reloadState(): void {
    const membership = this.env.membership;
    if (membership === undefined) {
      return;
    }
    this.isMember = membership.isMember;
    this.isTestMember = TEST_UNLOCK && membership.isTestMember;
    this.isMonthly = membership.activeProductId === PRODUCT_ID_MONTHLY;
    this.expiresAtMs = membership.expiresAtMs;
  }

  /** 管理订阅（R-MEMBER-11）：打开系统的订阅管理页（换方案、退订都在那边） */
  private openManagedSubscriptions(): void {
    const membership = this.env.membership;
    if (membership === undefined) {
      return;
    }
    membership.manageSubscriptions();
  }

  /** 恢复购买：重查华为权益 + 同步；完成提示「已与华为账号同步」 */
  private async restore(): Promise<void> {
    if (this.restoring) {
      return;
    }
    const membership = this.env.membership;
    if (membership === undefined) {
      return;
    }
    this.restoring = true;
    await membership.restore();
    this.restoring = false;
    this.reloadState();
    const context = this.getUIContext().getHostContext();
    this.restoreMessage = context !== undefined
      ? context.resourceManager.getStringSync($r('app.string.s_761f4e7e7d').id) : '';
  }

  /** 关闭测试会员：已经不是会员，这页没有可看的，退回设置 */
  private closeTestMembership(): void {
    const membership = this.env.membership;
    if (membership === undefined) {
      return;
    }
    membership.testDeactivate();
    this.navPathStack.pop();
  }
}
