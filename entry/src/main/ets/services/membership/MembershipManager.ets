/**
 * 尺素会员管理器（10_BUILD_MANUAL.md 7.1/7.2；U02 R-MEMBER-09/10/11）。
 * 对应 iOS `Services/StoreKitManager.swift`——商品、购买、本机会员判定。
 *
 * ## 两处判定，各管一摊（R-MEMBER-08）
 * - **本机（这里）**：相纸、封面版式这类界面上的会员能力。按华为 IAP 的订阅状态判，
 *   断网、没登录也能用——订阅属于 HUAWEI ID，不需要我们的服务器点头
 * - **服务器**：笔友来信这种有成本的权益，只认服务器的订阅表（stamps）。
 *   拿到 `jwsSubscriptionStatus` 后交 `POST /subscription/sync-huawei`（AuthService）
 *
 * ## 确认发货（U02 R-MEMBER-09 第 6 步，🔴 不能省）
 * 华为要求每一期订阅都「确认发货」，否则下一期自动续费扣不了款。服务端能确认就替你确认
 * （响应 `finished: true`）；`finished == false`、没登录、同步失败时客户端自己调
 * `iap.finishPurchase`。华为报「已确认」当成功（每次回前台都试一次没关系）。
 *
 * ## 测试期：假开通（TEST_UNLOCK）
 * AGC 的订阅还没建好之前会员要能全部试用：付费页照常显示（商品拉不到用预设价
 * ¥58 / ¥88 / ¥12 把页面画出来），点「开通尺素会员」不走付款、直接本机记成会员；
 * 会员页可「关闭测试会员」回到免费。假会员**不交服务器**。上架前改 false（清单 A0c）。
 *
 * UI 响应式：状态变化 +1 `membership.tick`（AppStorage），视图 @StorageProp/@Watch 重读
 * ——UserSession tick 同款手法。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { iap } from '@kit.IAPKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPrefs, PREF_KEY_TEST_MEMBER } from '../AppPrefs';
import { UserSession } from '../auth/UserSession';
import { AuthService } from '../auth/AuthService';
import { DecodedSubscription, decodePurchaseData, bestEntitlement } from './JwsDecode';

const DOMAIN = 0x0000;
const TAG = 'Membership';

/** 会员商品 ID（和 AGC、后端 membership 完全一致；以 AGC 实际建的为准） */
export const PRODUCT_ID_YEARLY = 'com.sinaratech.memoir.plus.yearly';
export const PRODUCT_ID_MONTHLY = 'com.sinaratech.memoir.plus.monthly';
export const PRODUCT_IDS: string[] = [PRODUCT_ID_YEARLY, PRODUCT_ID_MONTHLY];

/** 🔴 **上架前必须改成 `false`**（上架清单 A0c） */
export const TEST_UNLOCK = true;

/** AppStorage key：会员状态变化信号（isMember/有效期/商品变化时 +1） */
export const STORAGE_KEY_MEMBERSHIP_TICK = 'membership.tick';

/** 购买结果（付费页据此收场） */
export enum PurchaseOutcome {
  /** 买到（权益已给、已同步、已按需确认发货） */
  Purchased = 0,
  /** 用户取消支付（静默，不弹错） */
  Cancelled = 1,
  /** 其余失败（付费页提示「没能完成购买」） */
  Failed = 2
}

/** 本机会员状态快照（视图按 tick 重读） */
export class MembershipSnapshot {
  readonly isMember: boolean;
  readonly isTestMember: boolean;
  readonly activeProductId: string;
  readonly expiresAtMs: number;

  constructor(isMember: boolean, isTestMember: boolean, activeProductId: string,
    expiresAtMs: number) {
    this.isMember = isMember;
    this.isTestMember = isTestMember;
    this.activeProductId = activeProductId;
    this.expiresAtMs = expiresAtMs;
  }
}

export class MembershipManager {
  private readonly context: common.UIAbilityContext;
  private readonly session?: UserSession;
  private readonly auth?: AuthService;

  private isMemberValue = false;
  private activeProductIdValue = '';
  private expiresAtMsValue = 0;
  /** 拉到的订阅商品（年付在前） */
  private productsValue: iap.Product[] = [];
  /** 商品 / IAP 环境拿不到（付费页显示「暂时无法连接」并禁购） */
  private productsUnavailableValue = false;
  /** 首年优惠还有没有资格（拉不到商品时按有，测试期照预设价画） */
  private introEligibleValue = true;

  constructor(context: common.UIAbilityContext, session?: UserSession, auth?: AuthService) {
    this.context = context;
    this.session = session;
    this.auth = auth;
  }

  // ---- 状态读取（视图用）----

  get isMember(): boolean {
    return this.isMemberValue;
  }

  get isTestMember(): boolean {
    return TEST_UNLOCK && AppPrefs.getBool(PREF_KEY_TEST_MEMBER, false);
  }

  get activeProductId(): string {
    return this.activeProductIdValue;
  }

  get expiresAtMs(): number {
    return this.expiresAtMsValue;
  }

  get products(): iap.Product[] {
    return this.productsValue;
  }

  get productsUnavailable(): boolean {
    return this.productsUnavailableValue;
  }

  get isEligibleForIntroOffer(): boolean {
    return this.introEligibleValue;
  }

  snapshot(): MembershipSnapshot {
    return new MembershipSnapshot(this.isMemberValue, this.isTestMember,
      this.activeProductIdValue, this.expiresAtMsValue);
  }

  // ---- 启动 / 同步时机（U02 R-MEMBER-10：启动、回前台、登录成功、恢复购买）----

  /**
   * 查现有权益并按需同步 + 确认发货。返回「这次有没有从华为查到生效权益」——
   * 恢复购买据此提示「这个华为账号下没有找到尺素会员」。
   */
  async syncPurchases(): Promise<boolean> {
    let purchases: string[] = [];
    try {
      const result = await iap.queryPurchases(this.context, {
        productType: iap.ProductType.AUTORENEWABLE,
        queryType: iap.PurchaseQueryType.CURRENT_ENTITLEMENT
      });
      purchases = result.purchaseDataList;
    } catch (err) {
      // 没登录华为账号 / 环境不支持：安静地按无权益处理（本机假会员兜底还在）
      hilog.warn(DOMAIN, TAG, 'queryPurchases failed: %{public}s', JSON.stringify(err));
      this.applyNoEntitlement();
      return false;
    }
    const decoded: DecodedSubscription[] = [];
    for (const data of purchases) {
      const item = decodePurchaseData(data);
      if (item !== null) {
        decoded.push(item);
      }
    }
    const best = bestEntitlement(decoded);
    if (best !== null) {
      this.applyEntitlement(best);
    } else {
      this.applyNoEntitlement();
    }
    // 每一条都走同步 + 确认发货（续费的那几期靠这条兜底；重复确认华为当成功）
    for (const item of decoded) {
      if (item.isActive) {
        await this.syncAndFinish(item);
      }
    }
    return best !== null;
  }

  /** App 启动 / 回前台：查权益 + 拉商品 */
  async start(): Promise<void> {
    await this.syncPurchases();
    await this.loadProducts();
  }

  // ---- 商品 ----

  /** R-MEMBER-09 第 1–2 步：环境可用性 + 商品（年付在前）；不可用只记状态不抛错 */
  async loadProducts(): Promise<void> {
    try {
      await iap.queryEnvironmentStatus(this.context);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'queryEnvironmentStatus failed: %{public}s', JSON.stringify(err));
      this.productsUnavailableValue = true;
      this.bumpTick();
      return;
    }
    try {
      const loaded = await iap.queryProducts(this.context, {
        productType: iap.ProductType.AUTORENEWABLE,
        productIds: PRODUCT_IDS
      });
      this.productsValue = loaded.slice().sort((a: iap.Product, b: iap.Product): number => {
        const av = a.id === PRODUCT_ID_YEARLY ? 0 : 1;
        const bv = b.id === PRODUCT_ID_YEARLY ? 0 : 1;
        return av - bv;
      });
      this.productsUnavailableValue = false;
      const missing = PRODUCT_IDS.filter((id: string): boolean =>
        !this.productsValue.some((p: iap.Product): boolean => p.id === id));
      if (missing.length > 0) {
        hilog.warn(DOMAIN, TAG, 'products missing (not in AGC?): %{public}s', missing.join(','));
      }
      const yearly = this.productsValue.find((p: iap.Product): boolean => p.id === PRODUCT_ID_YEARLY);
      if (yearly !== undefined && yearly.subscriptionInfo !== undefined &&
        yearly.subscriptionInfo.hasEligibilityForIntroOffer !== undefined) {
        this.introEligibleValue = yearly.subscriptionInfo.hasEligibilityForIntroOffer;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'queryProducts failed: %{public}s', JSON.stringify(err));
      this.productsUnavailableValue = true;
    }
    this.bumpTick();
  }

  // ---- 购买 / 恢复 ----

  /**
   * 买（R-MEMBER-09 第 3–7 步）：createPurchase → 解码本机给权益 → 同步 →
   * 按需确认发货。用户取消（1001860000）静默返回 Cancelled。
   */
  async purchase(productId: string): Promise<PurchaseOutcome> {
    try {
      const result = await iap.createPurchase(this.context, {
        productId: productId,
        productType: iap.ProductType.AUTORENEWABLE
      });
      const decoded = decodePurchaseData(result.purchaseData);
      if (decoded === null) {
        hilog.error(DOMAIN, TAG, 'purchaseData undecodable');
        return PurchaseOutcome.Failed;
      }
      // 先在本机给权益（界面锁按本机判，R-MEMBER-08）
      if (decoded.isActive) {
        this.applyEntitlement(decoded);
        await this.syncAndFinish(decoded);
        return PurchaseOutcome.Purchased;
      }
      hilog.warn(DOMAIN, TAG, 'purchase returned inactive subscription, status=%{public}s', decoded.status);
      return PurchaseOutcome.Failed;
    } catch (err) {
      const code = (err as BusinessError).code;
      if (code === 1001860000) {
        return PurchaseOutcome.Cancelled;
      }
      hilog.error(DOMAIN, TAG, 'createPurchase failed code=%{public}d: %{public}s',
        code, JSON.stringify(err));
      return PurchaseOutcome.Failed;
    }
  }

  /**
   * 恢复购买（R-MEMBER-10）：重新查一遍现有权益（华为按 HUAWEI ID 全量返回，
   * 没有 AppStore.sync 那种动作），查到 → 同步 + 确认发货 → true；
   * 一条都没有 → false（付费页提示「这个华为账号下没有找到尺素会员」）。
   */
  async restore(): Promise<boolean> {
    return this.syncPurchases();
  }

  // ---- 管理订阅（R-MEMBER-11）----

  /** 会员状态页「管理订阅」：打开系统的订阅管理页 */
  async manageSubscriptions(): Promise<void> {
    try {
      await iap.showManagedSubscriptions(this.context, {
        windowScreenMode: iap.WindowScreenMode.FULLSCREEN
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'showManagedSubscriptions failed: %{public}s', JSON.stringify(err));
    }
  }

  // ---- 测试期假开通（TEST_UNLOCK；上架前关掉）----

  /** 点「开通」不走付款，直接记成会员（真买过的话以真的为准） */
  testActivate(): void {
    if (!TEST_UNLOCK) {
      return;
    }
    AppPrefs.putBool(PREF_KEY_TEST_MEMBER, true);
    this.applyNoEntitlement();
  }

  /** 回到免费，方便测免费版 */
  testDeactivate(): void {
    AppPrefs.putBool(PREF_KEY_TEST_MEMBER, false);
    this.applyNoEntitlement();
  }

  // ---- 内部 ----

  /** 解码后的一笔：交服务端验证；`finished:false` / 没登录 / 同步失败 → 自己确认发货 */
  private async syncAndFinish(decoded: DecodedSubscription): Promise<void> {
    let finished = false;
    const session = this.session;
    if (session !== undefined && session.isLoggedIn() && this.auth !== undefined) {
      try {
        const response = await this.auth.syncHuawei(decoded.jwsSubscriptionStatus, session.token ?? '');
        finished = response.finished;
      } catch (err) {
        // 503（后端没部署）/ 断网：下次启动或回前台时再交，本机权益照常
        hilog.warn(DOMAIN, TAG, 'sync-huawei failed (retry next launch): %{public}s', JSON.stringify(err));
      }
    }
    if (!finished) {
      try {
        await iap.finishPurchase(this.context, {
          productType: iap.ProductType.AUTORENEWABLE,
          purchaseToken: decoded.purchaseToken,
          purchaseOrderId: decoded.purchaseOrderId
        });
      } catch (err) {
        // 华为报「已确认」当成功；确认失败不打扰用户，下次回前台兜底再试
        hilog.warn(DOMAIN, TAG, 'finishPurchase failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  /** 本机给权益（快照 + tick） */
  private applyEntitlement(decoded: DecodedSubscription): void {
    const productId = decoded.productId.length > 0 ? decoded.productId : PRODUCT_ID_YEARLY;
    this.isMemberValue = true;
    this.activeProductIdValue = productId;
    this.expiresAtMsValue = decoded.expiresAtMs;
    this.bumpTick();
  }

  /** 没有华为权益：测试假会员兜底（yearly + 一年），否则免费 */
  private applyNoEntitlement(): void {
    if (this.isTestMember) {
      this.isMemberValue = true;
      this.activeProductIdValue = PRODUCT_ID_YEARLY;
      this.expiresAtMsValue = Date.now() + 365 * 24 * 3600 * 1000;
    } else {
      this.isMemberValue = false;
      this.activeProductIdValue = '';
      this.expiresAtMsValue = 0;
    }
    this.bumpTick();
  }

  private bumpTick(): void {
    AppStorage.setOrCreate(STORAGE_KEY_MEMBERSHIP_TICK,
      (AppStorage.get<number>(STORAGE_KEY_MEMBERSHIP_TICK) ?? 0) + 1);
  }
}
