/**
 * 会员链路纯逻辑单测（10_BUILD_MANUAL.md 7.1/7.2；U02 R-MEMBER-09）。
 * - decodeBase64Url：RFC 4648 §5 无 padding、宽容 '+' '/' '='、非法字符按 0
 * - decodePurchaseData：JWS 三段 → lastSubscriptionStatus；坏 JSON / 缺字段 /
 *   两段 JWS / 空载荷 → null 不抛；expirationDate 数字与数字串都收
 * - bestEntitlement：到期最晚者胜；status != '1' 不算权益；到期 0 按「无限远」
 * - parseSubscriptionSyncResponse：ok / subscription / isActive 必检；
 *   finished 缺省 false；坏形状抛错（调用方当同步失败 → 客户端兜底 finishPurchase）
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  decodeBase64Url,
  decodePurchaseData,
  bestEntitlement,
  DecodedSubscription
} from '../../main/ets/services/membership/JwsDecode';
import { parseSubscriptionSyncResponse } from '../../main/ets/models/Api';

/** 测试侧 base64url 编码（无 padding；标准字母表）——构造 JWS 载荷用 */
function encodeBase64Url(input: string): string {
  const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  let out = '';
  let bits = 0;
  let buffer = 0;
  for (let i = 0; i < input.length; i++) {
    const c = input.charCodeAt(i) & 0xFF;
    buffer = (buffer << 8) | c;
    bits += 8;
    while (bits >= 6) {
      bits -= 6;
      out += ALPHABET.charAt((buffer >> bits) & 0x3F);
    }
  }
  if (bits > 0) {
    out += ALPHABET.charAt((buffer << (6 - bits)) & 0x3F);
  }
  return out;
}

/** 手写 UTF-8 编码（BMP；测试文本无代理对）：返回字节序列 */
function utf8BytesOf(input: string): number[] {
  const bytes: number[] = [];
  for (let i = 0; i < input.length; i++) {
    const code = input.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
    } else {
      bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
    }
  }
  return bytes;
}

/** 造一条三段 JWS 的 purchaseData：header / signature 随便，载荷是给定 JSON */
function purchaseDataWithPayload(payloadJson: string): string {
  const jws = `unused-header.${encodeBase64Url(payloadJson)}.unused-signature`;
  return JSON.stringify({ jwsSubscriptionStatus: jws });
}

/** JSON.parse 的具名原始形状（as 只允许这一处：解析后立刻拷贝/校验） */
interface PurchaseDataEcho {
  jwsSubscriptionStatus?: string;
}

/** 构造 JWS 载荷用的具名 JSON 形状（对象字面量必须挂显式类型） */
interface LastPurchaseOrderJson {
  purchaseToken: string;
  purchaseOrderId: string;
  productId: string;
}

interface LastSubscriptionStatusJson {
  status: string;
  expirationDate: number | string;
  appProduct?: string;
  lastPurchaseOrder?: LastPurchaseOrderJson;
}

interface SubscriptionPayloadJson {
  lastSubscriptionStatus: LastSubscriptionStatusJson;
}

interface SubscriptionEchoJson {
  isActive?: boolean;
  productId?: string;
  platform?: string;
  expiresAt?: string;
}

interface SyncResponseJson {
  ok?: boolean;
  finished?: boolean;
  subscription?: SubscriptionEchoJson;
}

export default function membershipLogicTest() {
  describe('MembershipLogicTest', () => {
    // ---- base64url ----

    it('decodeBase64UrlHandlesNoPadding', 0, () => {
      // "Hello" → base64 "SGVsbG8="，url 无 padding "SGVsbG8"
      expect(decodeBase64Url('SGVsbG8')).assertEqual('Hello');
      expect(decodeBase64Url('')).assertEqual('');
      // 宽容：标准 base64 的 '+' '/' '=' 也收
      expect(decodeBase64Url('SGVsbG8=')).assertEqual('Hello');
      expect(decodeBase64Url('c3VwZXI=')).assertEqual('super');
    })

    it('decodeBase64UrlRoundTripsUtf8Bytes', 0, () => {
      // 解码产物是字节串（每字符一字节）：中文文本按 UTF-8 字节 round-trip
      const bytes = utf8BytesOf('尺素会员');
      let byteStr = '';
      for (const b of bytes) {
        byteStr += String.fromCharCode(b);
      }
      const decoded = decodeBase64Url(encodeBase64Url(byteStr));
      let byteSame = decoded.length === byteStr.length;
      for (let i = 0; i < byteStr.length && byteSame; i++) {
        byteSame = decoded.charCodeAt(i) === byteStr.charCodeAt(i);
      }
      expect(byteSame).assertTrue();
    })

    // ---- decodePurchaseData ----

    it('decodePurchaseDataReadsActiveSubscription', 0, () => {
      const payloadObj: SubscriptionPayloadJson = {
        lastSubscriptionStatus: {
          status: '1',
          expirationDate: 1_800_000_000_000,
          appProduct: 'com.sinaratech.memoir.plus.yearly',
          lastPurchaseOrder: {
            purchaseToken: 'token-1',
            purchaseOrderId: 'order-1',
            productId: 'com.sinaratech.memoir.plus.yearly'
          }
        }
      };
      const payload = JSON.stringify(payloadObj);
      const raw = purchaseDataWithPayload(payload);
      const decoded = decodePurchaseData(raw);
      expect(decoded !== null).assertTrue();
      expect(decoded!.isActive).assertTrue();
      expect(decoded!.status).assertEqual('1');
      expect(decoded!.expiresAtMs).assertEqual(1_800_000_000_000);
      expect(decoded!.purchaseToken).assertEqual('token-1');
      expect(decoded!.purchaseOrderId).assertEqual('order-1');
      expect(decoded!.productId).assertEqual('com.sinaratech.memoir.plus.yearly');
      // JWS 原样保留（交 /subscription/sync-huawei）
      const echo = JSON.parse(raw) as PurchaseDataEcho;
      expect(decoded!.jwsSubscriptionStatus).assertEqual(echo.jwsSubscriptionStatus);
    })

    it('decodePurchaseDataInactiveStatus', 0, () => {
      const payloadObj: SubscriptionPayloadJson = {
        lastSubscriptionStatus: { status: '0', expirationDate: 123 }
      };
      const decoded = decodePurchaseData(purchaseDataWithPayload(JSON.stringify(payloadObj)));
      expect(decoded !== null).assertTrue();
      expect(decoded!.isActive).assertFalse();
      expect(decoded!.status).assertEqual('0');
    })

    it('decodePurchaseDataAcceptsNumericStringExpiration', 0, () => {
      const payloadObj: SubscriptionPayloadJson = {
        lastSubscriptionStatus: { status: '1', expirationDate: '1800000000000' }
      };
      expect(decodePurchaseData(purchaseDataWithPayload(JSON.stringify(payloadObj)))!.expiresAtMs)
        .assertEqual(1_800_000_000_000);
    })

    it('decodePurchaseDataBadShapesReturnNull', 0, () => {
      // 坏 JSON
      expect(decodePurchaseData('not json')).assertNull();
      // 缺 jwsSubscriptionStatus
      expect(decodePurchaseData(JSON.stringify({ foo: 1 }))).assertNull();
      // JWS 不是三段
      const twoParts = JSON.stringify({ jwsSubscriptionStatus: 'a.b' });
      expect(decodePurchaseData(twoParts)).assertNull();
      // 载荷缺 lastSubscriptionStatus
      expect(decodePurchaseData(purchaseDataWithPayload('{}'))).assertNull();
      // 载荷不是 JSON
      expect(decodePurchaseData(
        JSON.stringify({ jwsSubscriptionStatus: 'x.####.y' }))).assertNull();
    })

    // ---- bestEntitlement ----

    it('bestEntitlementPicksLatestExpiry', 0, () => {
      const early = new DecodedSubscription(true, '1', 100, 't1', 'o1', 'p1', 'jws1');
      const late = new DecodedSubscription(true, '1', 200, 't2', 'o2', 'p2', 'jws2');
      expect(bestEntitlement([early, late])!.purchaseToken).assertEqual('t2');
      expect(bestEntitlement([late, early])!.purchaseToken).assertEqual('t2');
    })

    it('bestEntitlementSkipsInactiveAndTreatsZeroAsFar', 0, () => {
      // 0: inactive 不算权益 → 只剩到期 0 的那笔（按「无限远」仍当选）
      const inactive = new DecodedSubscription(false, '0', 999, 't-inactive', 'o', 'p', 'jws');
      const zero = new DecodedSubscription(true, '1', 0, 't-zero', 'o', 'p', 'jws');
      expect(bestEntitlement([inactive, zero])!.purchaseToken).assertEqual('t-zero');
      // 到期 0 与正常到期比：0 视作更远 → 但有真实到期的一笔同样是权益，
      // 取到期最晚的语义（0 → MAX_SAFE_INTEGER）
      const real = new DecodedSubscription(true, '1', 500, 't-real', 'o', 'p', 'jws');
      expect(bestEntitlement([zero, real])!.purchaseToken).assertEqual('t-zero');
    })

    it('bestEntitlementEmptyListReturnsNull', 0, () => {
      expect(bestEntitlement([])).assertNull();
      const inactiveOnly = new DecodedSubscription(false, '0', 100, 't', 'o', 'p', 'jws');
      expect(bestEntitlement([inactiveOnly])).assertNull();
    })

    // ---- parseSubscriptionSyncResponse（POST /subscription/sync-huawei 响应）----

    it('parseSubscriptionSyncResponseFullShape', 0, () => {
      const response: SyncResponseJson = {
        ok: true,
        finished: true,
        subscription: {
          isActive: true,
          productId: 'com.sinaratech.memoir.plus.yearly',
          platform: 'huawei',
          expiresAt: '2027-11-10T00:00:00Z'
        }
      };
      const parsed = parseSubscriptionSyncResponse(JSON.stringify(response));
      expect(parsed.finished).assertTrue();
      expect(parsed.subscription.isActive).assertTrue();
      expect(parsed.subscription.productId).assertEqual('com.sinaratech.memoir.plus.yearly');
      expect(parsed.subscription.platform).assertEqual('huawei');
      expect(parsed.subscription.expiresAt).assertEqual('2027-11-10T00:00:00Z');
    })

    it('parseSubscriptionSyncResponseFinishedDefaultsFalse', 0, () => {
      const response: SyncResponseJson = {
        ok: true,
        subscription: { isActive: false }
      };
      const parsed = parseSubscriptionSyncResponse(JSON.stringify(response));
      expect(parsed.finished).assertFalse();
      expect(parsed.subscription.isActive).assertFalse();
      expect(parsed.subscription.productId).assertEqual('');
    })

    it('parseSubscriptionSyncResponseThrowsOnBadShape', 0, () => {
      let threw = false;
      try {
        const missingOk: SyncResponseJson = { subscription: { isActive: true } };
        parseSubscriptionSyncResponse(JSON.stringify(missingOk));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();

      threw = false;
      try {
        const missingSub: SyncResponseJson = { ok: true };
        parseSubscriptionSyncResponse(JSON.stringify(missingSub));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();

      threw = false;
      try {
        // isActive 缺失 → 拒收
        const missingActive: SyncResponseJson = {
          ok: true, subscription: { productId: 'x' } };
        parseSubscriptionSyncResponse(JSON.stringify(missingActive));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    })
  })
}
