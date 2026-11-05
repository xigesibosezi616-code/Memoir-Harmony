/**
 * 设置 tab（10_BUILD_MANUAL.md 4.2 起步；4.3 账户卡；6.1 按 R-SETTINGS-01 排齐一级页）。
 * 对应 iOS `SettingsView.swift`。
 *
 * 一级页序（R-SETTINGS-01）：账户卡 →（尺素会员：阶段 7）→
 * 外观 / 日记 / 笔友 / 位置与天气 / 语言 / 数据与备份 / 写作统计 →
 * 给我们评分（在「关于」上方）→ 关于。
 *
 * - 账户卡不收进二级页；🔴 未绑手机号的红色警告也留在一级页卡上
 *   （R-ACCOUNT-03，2026-08-12 账号分裂事故的直接对策——收进二级页等于取消警告）
 * - 图标优先官方 `sys.symbol`（2026-10-24 拍板；名称均经资源表 ∩ 字体验证）
 * - 语言行直通选择页（R-SETTINGS-02 不套二级页），右侧顺带显示当前语言自称
 * - 写作统计单列一行（内容页；6.3 接路由）
 * - 给我们评分（R-SETTINGS-04）：直接跳应用市场评论页 `appmarket://comment`，
 *   不用系统评分弹窗；打不开（未上架 / 无应用市场）toast 提示
 * - 🔴 离开设置 tab 时把导航栈重置回首页（R-SETTINGS-03：MainTabsView 切走时
 *   bump `STORAGE_KEY_SETTINGS_RESET_TICK`，这里 @Watch 后 clear——不是进入时清，
 *   快捷方式直达不受影响）
 * - 登录态刷新：UserSession 无观察机制，用 STORAGE_KEY_SESSION_TICK
 *   （登录 / 绑定 / 401 清理时 +1）驱动重读
 *
 * 顶部定格居中小标题「设置」：内容 Scroll 上滑从标题底下穿过（官方组件化改造）。
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
import { STORAGE_KEY_APP_LANGUAGE, LanguageManager,
  LanguageOption } from '../../services/LanguageManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import BuildProfile from 'entry/BuildProfile';
import { SettingIconTile } from './SettingIconTile';

/** AppStorage key：离开设置 tab 的信号（MainTabsView bump，本页 @Watch 后清导航栈） */
export const STORAGE_KEY_SETTINGS_RESET_TICK = 'settingsResetTick';

/** 定格标题行的高（居中小标题「设置」悬浮在顶部） */
const TOP_BAR_ROW_HEIGHT_VP: number = 44;

const DOMAIN = 0x0000;
const TAG = 'SettingsTabView';

@Component
export struct SettingsTabView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @StorageProp(STORAGE_KEY_SESSION_TICK) @Watch('onSessionTick') sessionTick: number = 0;
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'en';
  /** 离开设置 tab → 导航栈重置回首页（R-SETTINGS-03） */
  @StorageProp(STORAGE_KEY_SETTINGS_RESET_TICK) @Watch('onResetTick') resetTick: number = 0;

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
            // 通用设置组（华为系统设置模板：分组卡 + 图标行 + 右侧箭头；R-SETTINGS-01）
            this.mainGroupCard()
            // 评分 + 关于（评分在「关于」上方，R-SETTINGS-01）
            this.rateAboutGroupCard()
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

  // ---- 账户卡 ----

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

  // ---- 通用设置组（外观 → 写作统计；R-SETTINGS-01） ----

  @Builder
  private mainGroupCard() {
    Column() {
      this.entryRow($r('sys.symbol.paintbrush'), 0xFF4A7CF7, $r('app.string.s_09b58aa342'),
        (): void => {
          this.navPathStack.pushPathByName('Appearance', '');
        })
      this.rowDivider()
      this.entryRow($r('sys.symbol.book'), 0xFF34C759, $r('app.string.s_bf50d67138'),
        (): void => {
          this.navPathStack.pushPathByName('JournalSettings', '');
        })
      this.rowDivider()
      this.entryRow($r('sys.symbol.envelope'), 0xFFFF9500, $r('app.string.s_8dcc9a2d73'),
        (): void => {
          this.navPathStack.pushPathByName('PenPalSettings', '');
        })
      this.rowDivider()
      this.entryRow($r('sys.symbol.compass'), 0xFF32ADE6, $r('app.string.s_ef86be8969'),
        (): void => {
          this.navPathStack.pushPathByName('LocationSettings', '');
        })
      this.rowDivider()
      // 语言：直通选择页（R-SETTINGS-02），右侧顺带显示当前语言自称
      Row({ space: 10 }) {
        SettingIconTile({ icon: $r('sys.symbol.translate'), tileColor: 0xFFAF52DE })
        Text($r('app.string.s_cd99b225a0'))
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .layoutWeight(1)
        Text(this.currentLanguageOption().nameResource)
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
        this.navPathStack.pushPathByName('Language', '');
      })
      this.rowDivider()
      this.entryRow($r('sys.symbol.externaldrive'), 0xFFFF6B22, $r('app.string.s_9199a16092'),
        (): void => {
          this.navPathStack.pushPathByName('Data', '');
        })
      this.rowDivider()
      // 写作统计：内容页单列一行（R-SETTINGS-02；6.3 接路由）
      this.entryRow($r('sys.symbol.calendar'), 0xFFFF2D55, $r('app.string.s_9392c3c977'),
        (): void => {
          // 6.3：this.navPathStack.pushPathByName('Stats', '');
        })
    }
    .borderRadius(16)
    .backgroundColor(this.theme.cardBackground)
    .width('100%')
    .margin({ top: 20 })
  }

  // ---- 评分 + 关于（评分在「关于」上方） ----

  @Builder
  private rateAboutGroupCard() {
    Column() {
      // 给我们评分：直接跳应用市场评论页（R-SETTINGS-04，不用系统评分弹窗）
      Row({ space: 10 }) {
        SettingIconTile({ icon: $r('sys.symbol.star'), tileColor: 0xFFF7A300 })
        Text($r('app.string.s_f85412ce62'))
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.arrow_up_right'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.textTertiary])
      }
      .width('100%')
      .padding({ top: 15, bottom: 15, left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.openAppGalleryComment();
      })
      this.rowDivider()
      this.entryRow($r('sys.symbol.info_circle'), 0xFF8E8E93, $r('app.string.s_bed172efc9'),
        (): void => {
          this.navPathStack.pushPathByName('About', '');
        })
    }
    .borderRadius(16)
    .backgroundColor(this.theme.cardBackground)
    .width('100%')
    .margin({ top: 20 })
  }

  // ---- 行零件 ----

  /** 组内分隔线（左侧留出文字对齐位） */
  @Builder
  private rowDivider() {
    Divider()
      .color(this.theme.border)
      .strokeWidth(0.5)
      .margin({ left: 20 })
  }

  /** 通用图标行（华为风格彩色底座 + 官方 sys.symbol + 标题 + chevron；点按走 onTap） */
  @Builder
  private entryRow(iconRes: Resource, tileColor: ResourceColor,
    titleRes: Resource, onTap: () => void) {
    Row({ space: 10 }) {
      SettingIconTile({ icon: iconRes, tileColor: tileColor })
      Text(titleRes)
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
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick(onTap)
  }

  // ---- 动作 ----

  /** 给我们评分：跳应用市场评论页（appmarket://comment?id=包名）。
   *  未上架 / 无应用市场时 openLink 抛错 → toast「打不开应用市场」 */
  private openAppGalleryComment(): void {
    // 窄化到 UIAbilityContext：openLink 在它上面
    // （getHostContext 返回基类 Context，ComposeView.openLocationSettings 同款窄化）
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      return;
    }
    context.openLink(`appmarket://comment?id=${BuildProfile.BUNDLE_NAME}`)
      .catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'open AppGallery comment failed: %{public}d %{public}s',
          err.code, err.message);
        this.env.errors.present(this.getString($r('app.string.s_f6f7c46fd6')), ErrorToastKind.Error);
      });
  }

  /** 登录 / 绑定 / 401 清理信号 → 重读会话（UserSession 无观察机制，tick 补） */
  onSessionTick(): void {
    this.refreshSessionState();
  }

  /** 离开设置 tab → 导航栈重置回首页（R-SETTINGS-03：离开时清，不是进入时） */
  onResetTick(): void {
    this.navPathStack.clear();
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

  /** 当前语言选项（显示自称；id 不在名单时兜底第一项，行值不至于空白） */
  private currentLanguageOption(): LanguageOption {
    const options = LanguageManager.supportedOptions();
    const found = options.find((option: LanguageOption): boolean => option.id === this.appLanguage);
    return found === undefined ? options[0] : found;
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
