/**
 * 尺素会员付费页（10_BUILD_MANUAL.md 7.1/7.2；U02 R-MEMBER-09/11；MEMBERSHIP.md）。
 * 对应 iOS `Views/Membership/PaywallView.swift`。
 *
 * 调性是**一封邀请函**，不是促销页：顶上一枚 68vp 火漆印（ICONS.md 用法表），
 * 中间一张纸写清会员有什么（六条，含今雨与雅故、情绪小结、精装 PDF），
 * 年付默认选中排第一，续费说明紧贴按钮下方（R-MEMBER-04 硬性要求），
 * 最后一句「不开通也没关系」。
 *
 * 华为版措辞（U02 R-MEMBER-11）：续费三句用华为账号的订阅管理版
 * （xcstrings 里的 Apple 版一句不用）；恢复购买没找到提示
 * 「这个华为账号下没有找到尺素会员」；IAP 环境/商品拿不到提示
 * 「暂时无法连接，请稍后再试」并禁购、不显写死价格
 * （测试期 TEST_UNLOCK 例外：按预设价 ¥58 / ¥88 / ¥12 把页面画出来）。
 *
 * 测试期（MembershipManager.TEST_UNLOCK）：点「开通尺素会员」不走付款、
 * 直接本机记成会员（testActivate），成功即关页——成功后的「眼前一亮」
 * 由各功能自己呈现（相纸当场解锁）。
 *
 * 只在心动的时刻出现（设置会员行、相纸选择器的火漆标记、封面保存拦截），
 * **绝不打断写作**。
 *
 * 路由：系统路由表（router_map.json → name `Paywall`，全屏页）。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_HIDE_TAB_BAR } from '../../services/ImmersiveChrome';
import { PostingRun } from '../../models/LetterPostingFlightGeometry';
import { WaxSeal } from '../postbox/WaxSeal';
import { iap } from '@kit.IAPKit';
import { MembershipManager, PRODUCT_ID_YEARLY, PRODUCT_ID_MONTHLY, TEST_UNLOCK,
  PurchaseOutcome, STORAGE_KEY_MEMBERSHIP_TICK } from '../../services/membership/MembershipManager';

/** 付费页火漆印直径（ICONS.md 用法表：付费页 68vp） */
const SEAL_SIZE_VP: number = 68;

/** 一条会员权益（图标 + 标题 + 说明） */
class BenefitItem {
  readonly key: string;
  readonly icon: Resource;
  readonly title: Resource;
  readonly detail: Resource;

  constructor(key: string, icon: Resource, title: Resource, detail: Resource) {
    this.key = key;
    this.icon = icon;
    this.title = title;
    this.detail = detail;
  }
}

/** 六条权益（iOS PaywallView.benefits 逐条对应；图标对照 U19 ICONS.md「付费页」节） */
const BENEFITS: BenefitItem[] = [
  new BenefitItem('stamps',
    $r('sys.symbol.envelope_open'),
    $r('app.string.s_167e9b5f39'), $r('app.string.s_a1293d0d15')),
  new BenefitItem('sealed',
    $r('sys.symbol.seal'),
    $r('app.string.s_edd53ba0ee'), $r('app.string.s_686748c67b')),
  new BenefitItem('penpals',
    $r('sys.symbol.worldclock'),
    $r('app.string.s_2870d2ab3b'), $r('app.string.s_b27ed81c0c')),
  new BenefitItem('insights',
    $r('sys.symbol.point_bottomleft_forward_to_point_topright_scurvepath'),
    $r('app.string.s_4cbf770f3e'), $r('app.string.s_0d7248908c')),
  new BenefitItem('styles',
    $r('sys.symbol.picture'),
    $r('app.string.s_d67f0e000d'), $r('app.string.s_5272cb33b0')),
  new BenefitItem('book',
    $r('sys.symbol.ebook'),
    $r('app.string.s_7bf3cf769a'), $r('app.string.s_375d6fd193'))
];

/** 一个可选方案（年付 / 月付）；价格串已按语言格式化好 */
class PlanOption {
  readonly id: string;
  /** 年付 / 月付 */
  readonly nameRes: Resource;
  /** 大字价格（「首年 ¥58」「¥12 / 月」） */
  readonly headline: string;
  /** 小字说明（「首年约每月 ¥4.8，之后每年 ¥88」）；空串 = 没有 */
  readonly detail: string;
  /** 「首年优惠」胶囊 */
  readonly hasBadge: boolean;
  /** 按钮下的续费说明（华为版三句之一，R-MEMBER-04） */
  readonly renewal: string;

  constructor(id: string, nameRes: Resource, headline: string, detail: string,
    hasBadge: boolean, renewal: string) {
    this.id = id;
    this.nameRes = nameRes;
    this.headline = headline;
    this.detail = detail;
    this.hasBadge = hasBadge;
    this.renewal = renewal;
  }
}

/** 从本地价里抠货币符号（「¥58.00」→「¥」；折合月价要跟着原价的符号走） */
function currencySymbolOf(localPrice: string): string {
  const symbol = localPrice.replace(/[0-9.,\s]/g, '');
  return symbol.length > 0 ? symbol : '';
}

/** 微元价折合每月多少钱（最多一位小数，整数不带小数点；¥58 → 「4.8」） */
function perMonthFromMicro(microPrice: number): string {
  const rounded = Math.round(microPrice / 12000000) / 10;
  return `${rounded}`;
}

@Builder
export function PaywallBuilder() {
  PaywallView()
}

@Component
export struct PaywallView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  /** 会员状态变化（商品加载完、权益到账）→ 重算方案 */
  @StorageProp(STORAGE_KEY_MEMBERSHIP_TICK) @Watch('reloadPlans')
  membershipTick: number = 0;

  /** 当前选中方案（年付默认，R-MEMBER-03） */
  @State private selectedId: string = PRODUCT_ID_YEARLY;
  @State private busy: boolean = false;
  /** 按钮下方的单行错误（购买失败 / 恢复购买没找到）；空串 = 没有 */
  @State private inlineError: string = '';
  /** 可选方案（拉不到商品且非测试期 = 空数组 → 「暂时无法连接」+ 禁购） */
  @State private plans: PlanOption[] = [];
  /** 火漆印面：用户昵称首字（「素」兜底） */
  @State private sealMark: string = '素';

  private navPathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    const session = this.env.session;
    const user = session !== undefined && session.isLoggedIn() ? session.user : null;
    this.sealMark = PostingRun.sealMarkOf(user !== null ? user.displayName : undefined);
    this.reloadPlans();
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Scroll() {
          Column() {
            WaxSeal({ sizeVp: SEAL_SIZE_VP, mark: this.sealMark })
              .margin({ top: 14 })

            Text($r('app.string.s_7402638ab2'))
              .fontSize(this.theme.titleFont.size)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.textPrimary)
              .margin({ top: 12 })
            Text($r('app.string.s_c20e6cdf1d'))
              .fontSize(this.theme.captionFont.size)
              .fontColor(this.theme.textSecondary)
              .letterSpacing(this.theme.letterSpacingWide)
              .margin({ top: 4 })

            this.benefitsCard()

            this.plansBlock()

            this.purchaseButton()

            if (this.inlineError.length > 0) {
              Text(this.inlineError)
                .fontSize(this.theme.captionFont.size)
                .fontColor(this.theme.destructive)
                .textAlign(TextAlign.Center)
                .margin({ top: 8 })
            }

            this.renewalNote()

            this.linksRow()

            Text($r('app.string.s_8a7af824ab'))
              .fontSize(this.theme.labelFont.size)
              .fontColor(this.theme.textTertiary)
              .textAlign(TextAlign.Center)
              .margin({ top: 12 })
          }
          .width('100%')
          .padding({
            left: 24, right: 24,
            top: this.safeAreaTopVp + 16,
            bottom: this.safeAreaBottomVp + 20
          })
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .align(Alignment.Top)

        // 关闭：左上角圆钮（付费页是邀请函，随时可以「不开通也没关系」地离开）
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textSecondary])
        }
        .width(34)
        .height(34)
        .padding(0)
        .backgroundColor(this.theme.surfaceBackground)
        .border({ width: 0.5, color: this.theme.glassBorder })
        .margin({ left: 16, top: this.safeAreaTopVp + 12 })
        .enabled(!this.busy)
        .onClick((): void => {
          this.navPathStack.pop();
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.background)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
    })
    // 悬浮 Tab 栏在付费页期间隐藏（LoginView 同款；从写作页等无 tab 页进也不影响）
    .onShown((): void => {
      AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, true);
    })
    .onHidden((): void => {
      AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, false);
    })
  }

  // ---- 会员有什么 ----

  @Builder
  private benefitsCard() {
    Column({ space: 9 }) {
      ForEach(BENEFITS, (benefit: BenefitItem) => {
        this.benefitRow(benefit)
      }, (benefit: BenefitItem): string => benefit.key)
    }
    .padding(16)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .borderRadius(14)
    .backgroundColor(this.theme.cardBackground)
    .border({ width: 0.5, color: this.theme.border })
    .margin({ top: 16 })
  }

  @Builder
  private benefitRow(benefit: BenefitItem) {
    Row({ space: 12 }) {
      SymbolGlyph(benefit.icon)
        .fontSize(16)
        .fontColor([this.theme.accent])
        .width(22)
      Column({ space: 2 }) {
        Text(benefit.title)
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(600)
          .fontColor(this.theme.textPrimary)
        Text(benefit.detail)
          .fontSize(this.theme.captionFont.size)
          .fontColor(this.theme.textSecondary)
          .lineHeight(this.theme.captionFont.size * 1.35)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  // ---- 方案 ----

  @Builder
  private plansBlock() {
    if (this.plans.length === 0) {
      // R-MEMBER-04：拿不到商品/环境不可用 →「暂时无法连接」并禁购，不显写死价格
      Text($r('app.string.s_d005946611'))
        .fontSize(this.theme.captionFont.size)
        .fontColor(this.theme.textTertiary)
        .margin({ top: 22, bottom: 18 })
    } else {
      Column({ space: 8 }) {
        ForEach(this.plans, (plan: PlanOption) => {
          this.planCard(plan)
        }, (plan: PlanOption): string => plan.id)
      }
      .width('100%')
      .margin({ top: 14 })
    }
  }

  @Builder
  private planCard(plan: PlanOption) {
    Row({ space: 14 }) {
      SymbolGlyph(plan.id === this.selectedId
        ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.checkmark_circle'))
        .fontSize(20)
        .fontColor([plan.id === this.selectedId ? this.theme.accent : this.theme.textTertiary])
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(plan.nameRes)
            .fontSize(this.theme.bodyFont.size)
            .fontWeight(600)
            .fontColor(this.theme.textPrimary)
          if (plan.hasBadge) {
            Text($r('app.string.s_069d0578bc'))
              .fontSize(10)
              .fontWeight(600)
              .fontColor(this.theme.background)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .borderRadius(10)
              .backgroundColor(this.theme.accent)
          }
        }
        if (plan.detail.length > 0) {
          Text(plan.detail)
            .fontSize(this.theme.labelFont.size)
            .fontColor(this.theme.textSecondary)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(plan.headline)
        .fontSize(this.theme.headingFont.size)
        .fontColor(this.theme.textPrimary)
        .maxLines(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(12)
    .backgroundColor(this.theme.cardBackground)
    .border({
      width: plan.id === this.selectedId ? 1.5 : 0.5,
      color: plan.id === this.selectedId ? this.theme.accent : this.theme.border
    })
    .onClick((): void => {
      this.selectedId = plan.id;
    })
  }

  // ---- 购买 ----

  @Builder
  private purchaseButton() {
    Button({ stateEffect: true }) {
      Stack() {
        Text($r('app.string.s_497b5a5707'))
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(600)
          .fontColor(this.theme.background)
          .opacity(this.busy ? 0 : 1)
        if (this.busy) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(this.theme.background)
        }
      }
    }
    .type(ButtonType.Normal)
    .height(48)
    .borderRadius(12)
    .width('100%')
    .margin({ top: 14 })
    .backgroundColor(this.plans.length > 0 ? this.theme.accent : this.theme.textTertiary)
    .enabled(this.plans.length > 0 && !this.busy)
    .onClick((): void => {
      this.purchase();
    })
  }

  /** 续费规则（R-MEMBER-04）：紧贴购买按钮下方，跟选中方案走 */
  @Builder
  private renewalNote() {
    if (this.plans.length > 0) {
      ForEach(this.plans, (plan: PlanOption) => {
        if (plan.id === this.selectedId) {
          Text(plan.renewal)
            .fontSize(this.theme.labelFont.size)
            .fontColor(this.theme.textTertiary)
            .textAlign(TextAlign.Center)
            .lineHeight(this.theme.labelFont.size * 1.4)
            .margin({ top: 8 })
        }
      }, (plan: PlanOption): string => plan.id)
    }
  }

  @Builder
  private linksRow() {
    Row({ space: 14 }) {
      Text($r('app.string.s_781c5c7050'))
        .fontSize(this.theme.labelFont.size)
        .fontColor(this.theme.textSecondary)
        .onClick((): void => {
          this.restore();
        })
      Text('·')
        .fontSize(this.theme.labelFont.size)
        .fontColor(this.theme.textTertiary)
      Text($r('app.string.s_0399ad7167'))
        .fontSize(this.theme.labelFont.size)
        .fontColor(this.theme.textSecondary)
        .onClick((): void => {
          this.navPathStack.pushPathByName('Terms', '');
        })
      Text('·')
        .fontSize(this.theme.labelFont.size)
        .fontColor(this.theme.textTertiary)
      Text($r('app.string.s_8c276c1fea'))
        .fontSize(this.theme.labelFont.size)
        .fontColor(this.theme.textSecondary)
        .onClick((): void => {
          this.navPathStack.pushPathByName('Privacy', '');
        })
    }
    .margin({ top: 10 })
  }

  // ---- 数据 / 动作 ----

  /** 重算可选方案：真商品优先；拿不到且测试期用预设价；否则空（禁购） */
  private reloadPlans(): void {
    const membership = this.env.membership;
    const products: iap.Product[] = membership !== undefined ? membership.products : [];
    let yearly: iap.Product | null = null;
    let monthly: iap.Product | null = null;
    for (const product of products) {
      if (product.id === PRODUCT_ID_YEARLY) {
        yearly = product;
      } else if (product.id === PRODUCT_ID_MONTHLY) {
        monthly = product;
      }
    }
    const result: PlanOption[] = [];
    if (yearly !== null && monthly !== null) {
      const regular = displayPriceOf(yearly);
      const monthlyPrice = displayPriceOf(monthly);
      const symbol = currencySymbolOf(regular);
      const eligible = membership !== undefined && membership.isEligibleForIntroOffer;
      const subscriptionInfo = yearly.subscriptionInfo;
      const offer = eligible && subscriptionInfo !== undefined
        ? subscriptionInfo.introductoryOffer : undefined;
      if (offer !== undefined) {
        const intro = offer.localPrice;
        const perMonth = `${symbol}${perMonthFromMicro(offer.microPrice)}`;
        result.push(new PlanOption(PRODUCT_ID_YEARLY, $r('app.string.s_1017debe4c'),
          this.fmt($r('app.string.s_2ca8ce9b3f'), intro),
          this.fmt($r('app.string.s_c19e7282f7'), perMonth, regular),
          true,
          this.fmt($r('app.string.s_704db62f7a'), intro, regular)));
      } else {
        const perMonth = `${symbol}${perMonthFromMicro(yearly.microPrice)}`;
        result.push(new PlanOption(PRODUCT_ID_YEARLY, $r('app.string.s_1017debe4c'),
          this.fmt($r('app.string.s_1dce997c92'), regular),
          this.fmt($r('app.string.s_263a3081dc'), perMonth),
          false,
          this.fmt($r('app.string.s_e02cabdf13'), regular)));
      }
      result.push(new PlanOption(PRODUCT_ID_MONTHLY, $r('app.string.s_ccf97f8d85'),
        this.fmt($r('app.string.s_eaa6b0540d'), monthlyPrice),
        '',
        false,
        this.fmt($r('app.string.s_27293849b2'), monthlyPrice)));
    } else if (TEST_UNLOCK && membership !== undefined) {
      // 测试期（AGC 还没建商品）：用预设价把页面画出来（R-MEMBER-04 测试期例外）
      const eligible = membership.isEligibleForIntroOffer;
      if (eligible) {
        result.push(new PlanOption(PRODUCT_ID_YEARLY, $r('app.string.s_1017debe4c'),
          this.fmt($r('app.string.s_2ca8ce9b3f'), '¥58'),
          this.fmt($r('app.string.s_c19e7282f7'), '¥4.8', '¥88'),
          true,
          this.fmt($r('app.string.s_704db62f7a'), '¥58', '¥88')));
      } else {
        result.push(new PlanOption(PRODUCT_ID_YEARLY, $r('app.string.s_1017debe4c'),
          this.fmt($r('app.string.s_1dce997c92'), '¥88'),
          this.fmt($r('app.string.s_263a3081dc'), '¥7.3'),
          false,
          this.fmt($r('app.string.s_e02cabdf13'), '¥88')));
      }
      result.push(new PlanOption(PRODUCT_ID_MONTHLY, $r('app.string.s_ccf97f8d85'),
        this.fmt($r('app.string.s_eaa6b0540d'), '¥12'),
        '',
        false,
        this.fmt($r('app.string.s_27293849b2'), '¥12')));
    }
    this.plans = result;
  }

  private async purchase(): Promise<void> {
    if (this.busy || this.plans.length === 0) {
      return;
    }
    const membership = this.env.membership;
    if (membership === undefined) {
      return;
    }
    this.inlineError = '';
    // 测试期：不走付款，直接开通（见 MembershipManager.TEST_UNLOCK）
    if (TEST_UNLOCK) {
      membership.testActivate();
      this.finishWithSuccess();
      return;
    }
    this.busy = true;
    const outcome = await membership.purchase(this.selectedId);
    this.busy = false;
    if (outcome === PurchaseOutcome.Purchased) {
      this.finishWithSuccess();
    } else if (outcome === PurchaseOutcome.Failed) {
      this.inlineError = this.str($r('app.string.s_a428575031'));
    }
    // Cancelled：用户取消支付，静默（R-MEMBER-09 第 7 步）
  }

  private async restore(): Promise<void> {
    if (this.busy) {
      return;
    }
    const membership = this.env.membership;
    if (membership === undefined) {
      return;
    }
    this.inlineError = '';
    this.busy = true;
    const found = await membership.restore();
    this.busy = false;
    if (found && membership.isMember) {
      this.finishWithSuccess();
    } else {
      this.inlineError = this.str($r('app.string.s_0bf835768f'));
    }
  }

  /** 开通成功：关掉付费页（成功后的「眼前一亮」由各功能自己呈现） */
  private finishWithSuccess(): void {
    this.navPathStack.pop();
  }

  // ---- 资源读取 ----

  private str(res: Resource): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringSync(res.id);
  }

  /** 带参格式化（getStringSync 变参；参数都是价格串） */
  private fmt(res: Resource, arg1: string, arg2?: string): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    if (arg2 !== undefined) {
      return context.resourceManager.getStringSync(res.id, arg1, arg2);
    }
    return context.resourceManager.getStringSync(res.id, arg1);
  }
}

/** 商品本地展示价（货币符号+金额）；localPrice 缺省回退 price */
function displayPriceOf(product: iap.Product): string {
  const local = product.localPrice;
  if (local !== undefined && local.length > 0) {
    return local;
  }
  return product.price;
}
