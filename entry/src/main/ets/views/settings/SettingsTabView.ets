/**
 * 设置 tab（10_BUILD_MANUAL.md 4.2 起步；4.3 账户卡；6.1 华为结构；U10 全量重排）。
 * 对应 iOS `SettingsView.swift`。
 *
 * U10 R-SETTINGS-01 一级页序（2026-11-07 全量交付）：
 * 大标题「设置」（固定不滚动）→ 账户卡（R-SETTINGS-10）→ 尺素会员 →
 * 【外观 / 日记 / 笔友 / 位置与天气 / 语言】→【数据与备份 / 写作统计】→
 * 【给我们评分 / 反馈与建议 / 关于】→「关注我们」组（R-SETTINGS-07）。
 *
 * U10 R-SETTINGS-08 分层配色：页底 settingsPageBackground / 分组卡
 * settingsCardBackground / 大标题 settingsTitleColor（按主题定死不跟系统深浅）。
 *
 * U10 R-SETTINGS-09 行首图标：一律 iOS 侧出好的图片（单色线条 + 细线圆框，
 * HarmonyAssets/settings_icons；30×30vp 高清 4 倍图，不加工不填色）。
 * 2026-11-07 用户拍板：彩底 tile 方案否决，线框图片为唯一方案（开关已删）。
 *
 * U10 R-SETTINGS-10 账户卡：60vp 手写 m. 头像图（img_avatar_mark_*，
 * 🔴 不显示华为账号头像）+ 名字 +「账号、手机号与登录方式」；未绑手机号
 * → 卡里多一行「还没有绑定手机号」+ 红点「1」，卡下小字后果说明（警示色）。
 * 🔴 账户卡不收进二级页、警告留在一级页（R-ACCOUNT-03）。
 *
 * 尺素会员行（用户裁决「连会员页一起做」）：WaxSeal 26vp 火漆印不套框
 * （占同样 30vp 宽）+ 推 MembershipView 骨架页（Stage 7 IAP 后点亮）。
 *
 * 关注我们（R-SETTINGS-07，大陆版）：小红书 / 抖音 / 微博一行一个，logo
 * 图片 ic_follow_*；点了装了进 App（scheme→startAbility），没装开网页
 * （openLink 兜底）；名单为空整组不出现（全球版账号未给）。
 * 反馈与建议（R-SETTINGS-11）：mailto connect@sinaratech.com.cn，
 * 无邮件处理方 → 复制邮箱 + toast「邮箱地址已复制：%s」。
 *
 * 华为量测规格沿用（存档 .tmp-ui/hw_settings/）：页边距 16 / 卡圆角 20 /
 * 卡距 26 / 卡内边距 12 / 行上下边距 8 / 行标题 fp16 / 行值 fp14 / 昵称 fp22 /
 * 本页字号硬编码系统无衬线（用户拍板，主题字体在其它 tab 保留）；
 * 🔴 大标题 fp26 左上固定不滚动（滚动态实锤，无折叠态）。
 * 离开设置 tab 重置导航栈（R-SETTINGS-03）；登录态用
 * STORAGE_KEY_SESSION_TICK 驱动重读。
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
import { PostingRun } from '../../models/LetterPostingFlightGeometry';
import { WaxSeal } from '../postbox/WaxSeal';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError, deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { bundleManager, common, Want } from '@kit.AbilityKit';
import BuildProfile from 'entry/BuildProfile';
import { settingsIcon } from './SettingsIcons';

/** AppStorage key：离开设置 tab 的信号（MainTabsView bump，本页 @Watch 后清导航栈） */
export const STORAGE_KEY_SETTINGS_RESET_TICK = 'settingsResetTick';

/** 华为大标题「设置」字号（真机量测 103px ÷ 3.375 ≈ 26） */
const BIG_TITLE_FONT_SIZE_FP: number = 26;

/** 大标题距安全区顶（华为实测 174px − 状态栏 121px ≈ 16vp） */
const TITLE_TOP_GAP_VP: number = 16;

/** 首卡距安全区顶（华为实测搜索卡顶 368px − 状态栏 ≈ 73vp；标题区占位） */
const CONTENT_TOP_GAP_VP: number = 73;

/** 华为量测 token：页边距 / 卡圆角 / 卡距 / 卡内边距 / 行上下边距 / 图标到文字间距 */
const PAGE_PADDING_VP: number = 16;
const CARD_RADIUS_VP: number = 20;
const CARD_GAP_VP: number = 26;
const CARD_PADDING_VP: number = 12;
const ROW_PADDING_V_VP: number = 8;
const ICON_TEXT_GAP_VP: number = 12;

/** U10 行首图标显示尺寸（R-SETTINGS-09） */
const U10_ICON_SIZE_VP: number = 30;

/** 账户卡头像（R-SETTINGS-10：60pt 手写 m.） */
const AVATAR_SIZE_VP: number = 60;

/** 会员行火漆印（R-SETTINGS-09：26pt 不套框，占同样 30pt 宽） */
const SEAL_SIZE_VP: number = 26;

/** 行标题字号（华为实测 63px ≈ fp16；本页系统无衬线，不走主题字体） */
const ROW_TITLE_FONT_SIZE_FP: number = 16;
/** 行值 / 副标题字号（华为实测 55px ≈ fp14） */
const ROW_VALUE_FONT_SIZE_FP: number = 14;
/** 账户昵称字号（华为实测 91px ≈ fp22） */
const ACCOUNT_NAME_FONT_SIZE_FP: number = 22;

/** 反馈邮箱（R-SETTINGS-11） */
const FEEDBACK_EMAIL: string = 'connect@sinaratech.com.cn';

/** 关注我们名单（大陆版；R-SETTINGS-07。空名单整组不出现） */
class FollowAccountSpec {
  /** SettingsIcons.ets 的取图 key（ic_follow_<id>_<主题>） */
  readonly iconKey: string;
  /** 读屏 / 显示的平台名 */
  readonly nameRes: Resource;
  /** 平台 scheme（'' = 没有，直接开网页；抖音只拿得到短链） */
  readonly scheme: string;
  /** 没装 App 时的网页（尽量用平台分享短链） */
  readonly webUrl: string;

  constructor(iconKey: string, nameRes: Resource, scheme: string, webUrl: string) {
    this.iconKey = iconKey;
    this.nameRes = nameRes;
    this.scheme = scheme;
    this.webUrl = webUrl;
  }
}

/** 大陆版关注名单：小红书 / 抖音 / 微博（2026-10-24 用户给的官方账号） */
const FOLLOW_ACCOUNTS: FollowAccountSpec[] = [
  new FollowAccountSpec('follow_xiaohongshu', $r('app.string.s_e2866d0815'),
    'xhsdiscover://user/5a0af5e94eacab4314599675', 'https://xhslink.cn/o/4zXwDZk0tsn'),
  // 抖音只拿得到 sec_uid，App 的 scheme 要数字 uid —— 直接开分享短链（装了会被 App 接住）
  new FollowAccountSpec('follow_douyin', $r('app.string.s_21a8e41cf6'),
    '', 'https://v.douyin.com/hs0l7Jku-5M/'),
  new FollowAccountSpec('follow_weibo', $r('app.string.s_9d972e7230'),
    'sinaweibo://userinfo?uid=7934302970', 'https://weibo.com/u/7934302970')
];

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
  /** 🔴 未绑手机号 → 一级页卡上红点行 + 卡下警告（R-ACCOUNT-03） */
  @State private phoneMissing: boolean = false;
  /** 会员行火漆印的印面：用户昵称首字（PostingRun.sealMarkOf 取字口径） */
  @State private sealMark: string = '素';
  private navPathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.refreshSessionState();
  }

  build() {
    Navigation(this.navPathStack) {
      Stack({ alignContent: Alignment.TopStart }) {
        // 内容：整屏滚动，从状态栏和固定大标题底下穿过（华为同款）
        Scroll() {
          Column() {
            // 标题区占位：首卡顶 = 安全区顶 + 73vp（华为实测）；滚动时内容从标题底下穿过
            Column().height(this.safeAreaTopVp + CONTENT_TOP_GAP_VP)
            if (this.loggedIn) {
              this.loggedInAccountCard()
            } else {
              this.loginEntryCard()
            }
            this.membershipCard()
            // 三组框框（R-SETTINGS-01 顺序；规格统一：圆角 20 / 卡距 26）
            this.appearanceGroupCard()
            this.dataGroupCard()
            this.rateFeedbackAboutGroupCard()
            this.followUsSection()
            // 底部：悬浮 Tab 栏 + 手势条让位
            Column().width('100%').height(this.safeAreaBottomVp + 88)
          }
          .padding({ left: PAGE_PADDING_VP, right: PAGE_PADDING_VP })
          .constraintSize({ maxWidth: 840 })
          .width('100%')
        }
        .width('100%')
        .height('100%')
        // 🔴 Scroll 设高度限制后内容小于视口默认居中（官方 FAQ faqs-arkui-725，
        // 2026-10-24 真机「账户卡在屏幕中间」三轮排查后定位）——必须显式顶对齐
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        // 华为大标题「设置」：fp26 左上**固定**，不随内容滚动、无折叠态（滚动态实锤）；
        // 颜色按主题定死（R-SETTINGS-08：浅色主题手机开深色模式时也是深色字）
        Text($r('app.string.s_7debf9cb03'))
          .fontSize(BIG_TITLE_FONT_SIZE_FP)
          .fontColor(this.theme.settingsTitleColor)
          .margin({
            top: this.safeAreaTopVp + TITLE_TOP_GAP_VP,
            left: PAGE_PADDING_VP
          })
      }
      .width('100%')
      .height('100%')
      // 页底比卡深一档（R-SETTINGS-08 配色表）
      .backgroundColor(this.theme.settingsPageBackground)
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }

  // ---- 账户卡（R-SETTINGS-10）----

  /** 已登录账户卡：60vp 手写 m. 头像 + 名字 +「账号、手机号与登录方式」；
   *  🔴 未绑手机号时卡里多一行红点提醒，卡下小字后果说明（R-ACCOUNT-03） */
  @Builder
  private loggedInAccountCard() {
    Column() {
      Row({ space: ICON_TEXT_GAP_VP }) {
        // 手写 m. 头像（img_avatar_mark_* 图片；🔴 不显示华为账号头像，两端一致）
        Image(settingsIcon(this.theme.id, 'avatar'))
          .width(AVATAR_SIZE_VP)
          .height(AVATAR_SIZE_VP)
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.High)
        Column({ space: 2 }) {
          // 有昵称就以昵称为准——一串脱敏手机号当账号名，用户看不出「这是我」（iOS 同款）
          Text(this.accountTitle)
            .fontSize(ACCOUNT_NAME_FONT_SIZE_FP)
            .fontColor(this.theme.textPrimary)
          Text($r('app.string.s_dce5f6e4df'))
            .fontSize(ROW_VALUE_FONT_SIZE_FP)
            .fontColor(this.theme.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.textTertiary])
      }
      .width('100%')
      .padding({ top: CARD_PADDING_VP, bottom: this.phoneMissing ? 0 : CARD_PADDING_VP,
        left: CARD_PADDING_VP, right: CARD_PADDING_VP })
      .onClick((): void => {
        this.navPathStack.pushPathByName('Account', '');
      })

      // 🔴 未绑手机号：卡里一行红点提醒（U10 R-SETTINGS-10；点了也进账号页）
      if (this.phoneMissing) {
        Divider()
          .color(this.theme.border)
          .strokeWidth(0.5)
          .margin({ left: CARD_PADDING_VP + AVATAR_SIZE_VP + ICON_TEXT_GAP_VP,
            right: CARD_PADDING_VP })
        Row() {
          Text($r('app.string.s_5cc6e4a916'))
            .fontSize(ROW_TITLE_FONT_SIZE_FP)
            .fontColor(this.theme.textPrimary)
            .layoutWeight(1)
          // 红点 22pt + 白色「1」（红 = 主题警示色）
          Stack() {
            Circle()
              .fill(this.theme.destructive)
              .width(22)
              .height(22)
            Text('1')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
          .width(22)
          .height(22)
        }
        .width('100%')
        .padding({ top: 10, bottom: 10,
          left: CARD_PADDING_VP, right: CARD_PADDING_VP })
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.navPathStack.pushPathByName('Account', '');
        })
      }
    }
    .borderRadius(CARD_RADIUS_VP)
    .backgroundColor(this.theme.settingsCardBackground)
    .width('100%')

    // 🔴 未绑手机号后果说明必须留在一级页卡下（R-ACCOUNT-03；U02 华为版文案）
    if (this.phoneMissing) {
      Text($r('app.string.s_ab8da9843c'))
        .fontSize(ROW_VALUE_FONT_SIZE_FP)
        .fontColor(this.theme.destructive)
        .margin({ top: 8, left: 12, right: 12 })
        .width('100%')
    }
  }

  /** 未登录：登录 / 注册入口卡（同款头像 + 说明，点了推登录页） */
  @Builder
  private loginEntryCard() {
    Column() {
      Row({ space: ICON_TEXT_GAP_VP }) {
        Image(settingsIcon(this.theme.id, 'avatar'))
          .width(AVATAR_SIZE_VP)
          .height(AVATAR_SIZE_VP)
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.High)
        Column({ space: 2 }) {
          Text($r('app.string.s_5d2df2c92d'))
            .fontSize(ACCOUNT_NAME_FONT_SIZE_FP)
            .fontColor(this.theme.textPrimary)
          Text($r('app.string.s_486e6b598c'))
            .fontSize(ROW_VALUE_FONT_SIZE_FP)
            .fontColor(this.theme.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.textTertiary])
      }
      .width('100%')
      .padding({ top: CARD_PADDING_VP, bottom: CARD_PADDING_VP,
        left: CARD_PADDING_VP, right: CARD_PADDING_VP })
      .onClick((): void => {
        this.navPathStack.pushPathByName('Login', '');
      })
    }
    .borderRadius(CARD_RADIUS_VP)
    .backgroundColor(this.theme.settingsCardBackground)
    .width('100%')
  }

  // ---- 尺素会员（用户裁决：连会员页骨架一起做，Stage 7 IAP 后点亮）----

  @Builder
  private membershipCard() {
    Row({ space: ICON_TEXT_GAP_VP }) {
      // 火漆印本身就是这一行的图标，不套框（R-SETTINGS-09），占同样 30vp 宽对齐下行文字
      Stack() {
        WaxSeal({ sizeVp: SEAL_SIZE_VP, mark: this.sealMark })
      }
      .width(U10_ICON_SIZE_VP)
      Text($r('app.string.s_7402638ab2'))
        .fontSize(ROW_TITLE_FONT_SIZE_FP)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textTertiary])
    }
    .width('100%')
    .padding({ top: ROW_PADDING_V_VP, bottom: ROW_PADDING_V_VP,
      left: CARD_PADDING_VP, right: CARD_PADDING_VP })
    .alignItems(VerticalAlign.Center)
    .borderRadius(CARD_RADIUS_VP)
    .backgroundColor(this.theme.settingsCardBackground)
    .width('100%')
    .margin({ top: CARD_GAP_VP })
    .onClick((): void => {
      this.navPathStack.pushPathByName('Membership', '');
    })
  }

  // ---- 第一组：外观 / 日记 / 笔友 / 位置与天气 / 语言 ----

  @Builder
  private appearanceGroupCard() {
    Column() {
      this.entryRow('appearance',
        $r('app.string.s_09b58aa342'),
        (): void => {
          this.navPathStack.pushPathByName('Appearance', '');
        })
      this.rowDivider()
      this.entryRow('journal',
        $r('app.string.s_bf50d67138'),
        (): void => {
          this.navPathStack.pushPathByName('JournalSettings', '');
        })
      this.rowDivider()
      this.entryRow('penpal',
        $r('app.string.s_8dcc9a2d73'),
        (): void => {
          this.navPathStack.pushPathByName('PenPalSettings', '');
        })
      this.rowDivider()
      this.entryRow('location',
        $r('app.string.s_ef86be8969'),
        (): void => {
          this.navPathStack.pushPathByName('LocationSettings', '');
        })
      this.rowDivider()
      // 语言：直通选择页（R-SETTINGS-02），右侧顺带显示当前语言自称
      Row() {
        this.rowLeadingIcon('language')
        Text($r('app.string.s_cd99b225a0'))
          .fontSize(ROW_TITLE_FONT_SIZE_FP)
          .fontColor(this.theme.textPrimary)
          .margin({ left: ICON_TEXT_GAP_VP })
          .layoutWeight(1)
        Text(this.currentLanguageOption().nameResource)
          .fontSize(ROW_VALUE_FONT_SIZE_FP)
          .fontColor(this.theme.textTertiary)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.textTertiary])
          .margin({ left: 4 })
      }
      .width('100%')
      .padding({ top: ROW_PADDING_V_VP, bottom: ROW_PADDING_V_VP,
        left: CARD_PADDING_VP, right: CARD_PADDING_VP })
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.navPathStack.pushPathByName('Language', '');
      })
    }
    .borderRadius(CARD_RADIUS_VP)
    .backgroundColor(this.theme.settingsCardBackground)
    .width('100%')
    .margin({ top: CARD_GAP_VP })
  }

  // ---- 第二组：数据与备份 / 写作统计 ----

  @Builder
  private dataGroupCard() {
    Column() {
      this.entryRow('data',
        $r('app.string.s_9199a16092'),
        (): void => {
          this.navPathStack.pushPathByName('Data', '');
        })
      this.rowDivider()
      // 写作统计：内容页单列一行（R-SETTINGS-02；6.3 接路由）
      this.entryRow('stats',
        $r('app.string.s_9392c3c977'),
        (): void => {
          // 6.3：this.navPathStack.pushPathByName('Stats', '');
        })
    }
    .borderRadius(CARD_RADIUS_VP)
    .backgroundColor(this.theme.settingsCardBackground)
    .width('100%')
    .margin({ top: CARD_GAP_VP })
  }

  // ---- 第三组：给我们评分 / 反馈与建议 / 关于（外跳行右侧 ↗）----

  @Builder
  private rateFeedbackAboutGroupCard() {
    Column() {
      // 给我们评分：直接跳应用市场评论页（R-SETTINGS-04，不用系统评分弹窗）；
      // 图标是华为应用市场购物袋（ic_settings_rate，U10）
      this.actionRow('rate',
        $r('app.string.s_f85412ce62'),
        (): void => {
          this.openAppGalleryComment();
        })
      this.rowDivider()
      // 反馈与建议（R-SETTINGS-11）：mailto；无邮件处理方复制邮箱 + toast
      this.actionRow('feedback',
        $r('app.string.s_2895d69933'),
        (): void => {
          this.openFeedbackMail();
        })
      this.rowDivider()
      this.entryRow('about',
        $r('app.string.s_bed172efc9'),
        (): void => {
          this.navPathStack.pushPathByName('About', '');
        })
    }
    .borderRadius(CARD_RADIUS_VP)
    .backgroundColor(this.theme.settingsCardBackground)
    .width('100%')
    .margin({ top: CARD_GAP_VP })
  }

  // ---- 关注我们（R-SETTINGS-07；空名单整组不出现）----

  @Builder
  private followUsSection() {
    if (FOLLOW_ACCOUNTS.length > 0) {
      Column() {
        // 组头「关注我们」（系统组头样式）
        Text($r('app.string.s_d89283676b'))
          .fontSize(ROW_VALUE_FONT_SIZE_FP)
          .fontColor(this.theme.textTertiary)
          .margin({ left: 12, bottom: 6 })
          .width('100%')
        Column() {
          ForEach(FOLLOW_ACCOUNTS, (account: FollowAccountSpec) => {
            this.followRow(account)
          }, (account: FollowAccountSpec): string => account.iconKey)
        }
        .borderRadius(CARD_RADIUS_VP)
        .backgroundColor(this.theme.settingsCardBackground)
        .width('100%')
      }
      .width('100%')
      .margin({ top: CARD_GAP_VP })
    }
  }

  /** 一个平台一行：ic_follow_* 单色 logo 图片 + 平台名 + ↗（logo 不上平台品牌色） */
  @Builder
  private followRow(account: FollowAccountSpec) {
    Row({ space: ICON_TEXT_GAP_VP }) {
      Image(settingsIcon(this.theme.id, account.iconKey))
        .width(U10_ICON_SIZE_VP)
        .height(U10_ICON_SIZE_VP)
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.High)
      Text(account.nameRes)
        .fontSize(ROW_TITLE_FONT_SIZE_FP)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.arrow_up_right'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textTertiary])
    }
    .width('100%')
    .padding({ top: ROW_PADDING_V_VP, bottom: ROW_PADDING_V_VP,
      left: CARD_PADDING_VP, right: CARD_PADDING_VP })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.openFollowAccount(account);
    })
  }

  // ---- 行零件 ----

  /** 组内分隔线（左端对齐行文字、右端到 chevron 右缘，华为同款；
   *  左缩进 = 卡内边距 + 图标宽 + 图标到文字间距） */
  @Builder
  private rowDivider() {
    Divider()
      .color(this.theme.border)
      .strokeWidth(0.5)
      .margin({ left: CARD_PADDING_VP + U10_ICON_SIZE_VP + ICON_TEXT_GAP_VP,
        right: CARD_PADDING_VP })
  }

  /** 行首图标：iOS 侧出好的成品图（圆框、颜色已画好，不再加工；GUIDE.md） */
  @Builder
  private rowLeadingIcon(iconKey: string) {
    Image(settingsIcon(this.theme.id, iconKey))
      .width(U10_ICON_SIZE_VP)
      .height(U10_ICON_SIZE_VP)
      .objectFit(ImageFit.Contain)
      .interpolation(ImageInterpolation.High)
  }

  /** 通用图标行（行首图标 + 标题 + chevron；点按走 onTap） */
  @Builder
  private entryRow(iconKey: string,
    titleRes: Resource, onTap: () => void) {
    Row() {
      this.rowLeadingIcon(iconKey)
      Text(titleRes)
        .fontSize(ROW_TITLE_FONT_SIZE_FP)
        .fontColor(this.theme.textPrimary)
        .margin({ left: ICON_TEXT_GAP_VP })
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textTertiary])
    }
    .width('100%')
    .padding({ top: ROW_PADDING_V_VP, bottom: ROW_PADDING_V_VP,
      left: CARD_PADDING_VP, right: CARD_PADDING_VP })
    .alignItems(VerticalAlign.Center)
    .onClick(onTap)
  }

  /** 动作行（点了是动作不是进页面：右侧 ↗ 外跳箭头，R-SETTINGS-09） */
  @Builder
  private actionRow(iconKey: string,
    titleRes: Resource, onTap: () => void) {
    Row() {
      this.rowLeadingIcon(iconKey)
      Text(titleRes)
        .fontSize(ROW_TITLE_FONT_SIZE_FP)
        .fontColor(this.theme.textPrimary)
        .margin({ left: ICON_TEXT_GAP_VP })
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.arrow_up_right'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textTertiary])
    }
    .width('100%')
    .padding({ top: ROW_PADDING_V_VP, bottom: ROW_PADDING_V_VP,
      left: CARD_PADDING_VP, right: CARD_PADDING_VP })
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

  /**
   * 反馈与建议（R-SETTINGS-11）：用手机自己的邮件 App 写一封到 connect@。
   * 正文空三行给用户写，分隔线下附一行版本 / 系统 / 机型（给我们查问题用，不翻译）。
   * 没有能接 mailto 的邮件 App：复制邮箱 + toast「邮箱地址已复制：%s」。
   */
  private openFeedbackMail(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      return;
    }
    // 版本号走 bundleManager（取不到时照发，不带版本行）
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo): void => {
        this.launchFeedbackMail(context, info.versionName);
      })
      .catch((): void => {
        this.launchFeedbackMail(context, '');
      });
  }

  /** 拼 mailto 并拉起邮件（subject 编码；body = 空三行 + 分隔线 + 设备行） */
  private launchFeedbackMail(context: common.UIAbilityContext, versionName: string): void {
    const subject: string = this.getString($r('app.string.s_2895d69933'));
    const versionPart: string = versionName.length > 0 ? `Memoir ${versionName} · ` : '';
    const deviceLine: string =
      `\n\n\n——\n${versionPart}HarmonyOS ${deviceInfo.osFullName} · ${deviceInfo.productModel}`;
    const mailto: string =
      `mailto:${FEEDBACK_EMAIL}?subject=${encodeURIComponent(subject)}` +
      `&body=${encodeURIComponent(deviceLine)}`;
    const want: Want = { uri: mailto };
    context.startAbility(want)
      .catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'open mailto failed: %{public}d %{public}s',
          err.code, err.message);
        this.copyFeedbackAddress(context);
      });
  }

  /** 无邮件处理方兜底：复制邮箱地址 + toast（不让用户点了没反应） */
  private copyFeedbackAddress(context: common.UIAbilityContext): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, FEEDBACK_EMAIL);
    pasteboard.getSystemPasteboard().setData(data)
      .then((): void => {
        const message: string =
          context.resourceManager.getStringSync($r('app.string.s_c446cab9ee').id, FEEDBACK_EMAIL);
        this.env.errors.present(message, ErrorToastKind.Success);
      })
      .catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'copy email failed: %{public}d %{public}s',
          err.code, err.message);
      });
  }

  /**
   * 关注我们（R-SETTINGS-07）：装了平台 App 直接打开到主页（scheme → startAbility），
   * 没装开网页（openLink 短链兜底）。
   */
  private openFollowAccount(account: FollowAccountSpec): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      return;
    }
    if (account.scheme.length === 0) {
      this.openWebLink(context, account.webUrl);
      return;
    }
    const want: Want = { uri: account.scheme };
    context.startAbility(want)
      .catch((err: BusinessError): void => {
        hilog.info(DOMAIN, TAG, 'scheme %{public}s not handled: %{public}d, fallback to web',
          account.scheme, err.code);
        this.openWebLink(context, account.webUrl);
      });
  }

  /** 浏览器打开网页（分享短链；失败静默记日志） */
  private openWebLink(context: common.UIAbilityContext, url: string): void {
    context.openLink(url)
      .catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'open web link failed: %{public}d %{public}s',
          err.code, err.message);
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

  /** 从会话容器重读登录态：主标题昵称优先、其次脱敏手机号、再兜底「已登录」；
   *  会员行火漆印面 = 昵称首字（PostingRun.sealMarkOf 取字口径） */
  private refreshSessionState(): void {
    const session = this.env.session;
    if (session === undefined || !session.isLoggedIn()) {
      this.loggedIn = false;
      this.accountTitle = '';
      this.phoneMissing = false;
      this.sealMark = PostingRun.sealMarkOf(undefined);
      return;
    }
    this.loggedIn = true;
    const user = session.user;
    if (user === null) {
      // 有 token 无快照（快照损坏 / 401 前一瞬）：也算已登录，兜底展示
      this.accountTitle = this.getString($r('app.string.s_00e69bd114'));
      this.phoneMissing = false;
      this.sealMark = PostingRun.sealMarkOf(undefined);
      return;
    }
    this.phoneMissing = user.phone.length === 0;
    const masked: string = AuthLogic.maskedPhone(user.phone);
    if (user.displayName.length > 0) {
      this.accountTitle = user.displayName;
    } else {
      this.accountTitle = user.phone.length > 0 ? masked
        : this.getString($r('app.string.s_00e69bd114'));
    }
    this.sealMark = PostingRun.sealMarkOf(user.displayName);
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
