/**
 * 华为 IAP 购买数据解码（10_BUILD_MANUAL.md 7.1；U02 R-MEMBER-09 第 3–6 步）。
 * 纯逻辑、不碰 SDK：createPurchase / queryPurchases 返回的 `purchaseData`
 * （JSON 字符串）里取 `jwsSubscriptionStatus`（JWS），解出：
 * - `lastSubscriptionStatus.status == '1'` → 订阅生效（本机权益，界面锁按它判，R-MEMBER-08）
 * - `expirationDate` → 到期毫秒
 * - `lastPurchaseOrder.purchaseToken / purchaseOrderId` → `iap.finishPurchase` 确认发货用
 * - `jwsSubscriptionStatus` 原样保留 → `POST /subscription/sync-huawei` 交服务端验证
 *
 * 解不动（坏 JSON、缺字段、JWS 不是三段）返回 null，调用方当没有这笔权益；
 * base64url 手写解码（不吃 util），单测可离线跑。
 */

/** 解出来的一笔订阅权益 */
export class DecodedSubscription {
  /** lastSubscriptionStatus.status == '1' */
  readonly isActive: boolean;
  /** 原样 status 串（'0' / '1' / …） */
  readonly status: string;
  /** 到期毫秒；解不出来是 0 */
  readonly expiresAtMs: number;
  /** 确认发货用（U02 R-MEMBER-09 第 6 步） */
  readonly purchaseToken: string;
  readonly purchaseOrderId: string;
  /** 订阅商品 ID（appProduct；缺省 ''） */
  readonly productId: string;
  /** 原样 JWS 串，交 /subscription/sync-huawei */
  readonly jwsSubscriptionStatus: string;

  constructor(isActive: boolean, status: string, expiresAtMs: number,
    purchaseToken: string, purchaseOrderId: string, productId: string,
    jwsSubscriptionStatus: string) {
    this.isActive = isActive;
    this.status = status;
    this.expiresAtMs = expiresAtMs;
    this.purchaseToken = purchaseToken;
    this.purchaseOrderId = purchaseOrderId;
    this.productId = productId;
    this.jwsSubscriptionStatus = jwsSubscriptionStatus;
  }
}

/** purchaseData（JSON 串）的原样形状 */
interface PurchaseDataRaw {
  jwsSubscriptionStatus?: string;
}

/** jwsSubscriptionStatus 载荷的原样形状（华为「订阅状态通知」结构） */
interface JwsPayloadRaw {
  lastSubscriptionStatus?: LastStatusRaw;
}

interface LastStatusRaw {
  status?: string;
  /** 毫秒数字或数字串，两种都收 */
  expirationDate?: number | string;
  appProduct?: string;
  lastPurchaseOrder?: LastOrderRaw;
}

interface LastOrderRaw {
  purchaseToken?: string;
  purchaseOrderId?: string;
  productId?: string;
}

/**
 * base64url 解码（无 padding 也收；RFC 4648 §5）。只认标准字母表，
 * 非法字符一律按 0 处理——解码失败比抛错好：外层还有 JSON 校验兜底。
 */
export function decodeBase64Url(input: string): string {
  let bits = 0;
  let buffer = 0;
  const bytes: number[] = [];
  for (let i = 0; i < input.length; i++) {
    const c = input.charCodeAt(i);
    let value = 0;
    if (c >= 65 && c <= 90) {
      value = c - 65;            // A-Z
    } else if (c >= 97 && c <= 122) {
      value = c - 97 + 26;       // a-z
    } else if (c >= 48 && c <= 57) {
      value = c - 48 + 52;       // 0-9
    } else if (c === 45 || c === 43) {
      value = 62;                // '-'（base64url）/ '+'（宽容）
    } else if (c === 95 || c === 47) {
      value = 63;                // '_'（base64url）/ '/'（宽容）
    } else if (c === 61) {
      continue;                  // '=' padding
    } else {
      value = 0;                 // 非法字符按 0
    }
    buffer = (buffer << 6) | value;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((buffer >> bits) & 0xFF);
    }
  }
  let out = '';
  for (const b of bytes) {
    out += String.fromCharCode(b);
  }
  return out;
}

/** 到期时间归一毫秒：数字 / 数字串都收，别的（NaN / 负数）按 0 */
function normalizeExpiresAt(raw: number | string | undefined): number {
  const value = typeof raw === 'number' ? raw : (typeof raw === 'string' ? Number(raw) : NaN);
  if (!Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return value;
}

/**
 * 解一条 purchaseData：取 jwsSubscriptionStatus → 解 JWS 载荷 → 取
 * lastSubscriptionStatus。任何一步解不动返回 null（不当权益、不抛错——
 * queryPurchases 里混着消耗品等别的形状很正常）。
 */
export function decodePurchaseData(purchaseData: string): DecodedSubscription | null {
  let raw: PurchaseDataRaw;
  try {
    raw = JSON.parse(purchaseData) as PurchaseDataRaw;
  } catch (e) {
    return null;
  }
  if (raw === null || typeof raw !== 'object') {
    return null;
  }
  const jws: string = typeof raw.jwsSubscriptionStatus === 'string' ? raw.jwsSubscriptionStatus : '';
  if (jws.length === 0) {
    return null;
  }
  const parts: string[] = jws.split('.');
  if (parts.length !== 3) {
    return null;
  }
  let payload: JwsPayloadRaw;
  try {
    payload = JSON.parse(decodeBase64Url(parts[1])) as JwsPayloadRaw;
  } catch (e) {
    return null;
  }
  if (payload === null || typeof payload !== 'object') {
    return null;
  }
  const last = payload.lastSubscriptionStatus;
  if (last === undefined || typeof last !== 'object') {
    return null;
  }
  const status: string = typeof last.status === 'string' ? last.status : '';
  const order = last.lastPurchaseOrder;
  const purchaseToken: string = order !== undefined && typeof order.purchaseToken === 'string'
    ? order.purchaseToken : '';
  const purchaseOrderId: string = order !== undefined && typeof order.purchaseOrderId === 'string'
    ? order.purchaseOrderId : '';
  const productId: string = order !== undefined && typeof order.productId === 'string' && order.productId.length > 0
    ? order.productId : (typeof last.appProduct === 'string' ? last.appProduct : '');
  return new DecodedSubscription(status === '1', status, normalizeExpiresAt(last.expirationDate),
    purchaseToken, purchaseOrderId, productId, jws);
}

/**
 * 一组已解码权益里挑「当前生效的那一笔」：取到期最晚的一笔
 * （iOS `StoreKitManager.refreshEntitlements` 的 best 同款取舍）。
 * 到期为 0（解不出）的按「无限远」参与比较——华为漏发 expirationDate
 * 不该把真权益挤掉。
 */
export function bestEntitlement(list: DecodedSubscription[]): DecodedSubscription | null {
  let best: DecodedSubscription | null = null;
  for (const item of list) {
    if (!item.isActive) {
      continue;
    }
    if (best === null) {
      best = item;
      continue;
    }
    const a = item.expiresAtMs > 0 ? item.expiresAtMs : Number.MAX_SAFE_INTEGER;
    const b = best.expiresAtMs > 0 ? best.expiresAtMs : Number.MAX_SAFE_INTEGER;
    if (a > b) {
      best = item;
    }
  }
  return best;
}
