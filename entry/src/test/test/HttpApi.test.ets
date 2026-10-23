/**
 * 4.1 网络层单测（10_BUILD_MANUAL.md 4.1）。验收：单测覆盖错误映射——
 * 401 → 清登录态；429 → 节奏原因；5xx → 服务端错误；断网/超时/取消 → 网络错误。
 * 只测 kit-free 纯函数（ApiConfig / ApiDates / ApiError / HttpError / HttpRequest /
 * HttpMapping）；执行壳 HarmonyHttpClient import kit，本地跑不了，真机联调 4.2 验。
 */
import { describe, it, expect } from '@ohos/hypium';
import { ApiConfig } from '../../main/ets/services/http/ApiConfig';
import { ApiDates } from '../../main/ets/services/http/ApiDates';
import { ApiErrorEnvelope } from '../../main/ets/services/http/ApiError';
import { HttpError, HttpErrorKind } from '../../main/ets/services/http/HttpError';
import { HttpRequest, HttpMethod } from '../../main/ets/services/http/HttpRequest';
import { HttpMapping, UnauthorizedGate } from '../../main/ets/services/http/HttpMapping';

/** PATCH /me 的昵称 DTO（测 postJSON/patchJSON 序列化用） */
class NicknamePatchDTO {
  readonly displayName: string;

  constructor(displayName: string) {
    this.displayName = displayName;
  }
}

/** 02_BACKEND_API.md「寄信 429」原文响应体（reason/nextLetterAt/tier 在顶层） */
const BODY_429_RATE: string =
  '{"error":{"code":"rate_limited","message":"本周的信已经到了。青鸟习惯每周回一次——你写的它都在读，下周日再来。"},'
  + '"reason":"weekly_pending","nextLetterAt":"2026-10-13T00:00:00.000Z","tier":"free"}';

/** 02_BACKEND_API.md「发验证码 429」：顶层带 retryAfter（剩余秒数） */
const BODY_429_RETRY_AFTER: string =
  '{"error":{"code":"rate_limited","message":"发送太频繁，请稍后再试"},"retryAfter":42}';

const BODY_401: string =
  '{"error":{"code":"invalid_token","message":"登录已过期","detail":"jwt expired"}}';

const BODY_502: string =
  '{"error":{"code":"ai_failed","message":"青鸟暂时写不动，稍后再试"}}';

export default function httpApiTest() {
  describe('HttpApiTest', () => {
    // ---- ApiConfig：基础地址 + 超时分级（寄信 90 / 补领 30 / 节奏 15 / 其他 30） ----

    it('baseUrlIsSingleConstant', 0, () => {
      expect(ApiConfig.BASE_URL).assertEqual('https://memoir-api-cn-ecdrwvhwac.cn-hangzhou.fcapp.run');
    })

    it('timeoutTiersMatchSpec', 0, () => {
      expect(ApiConfig.TIMEOUT_SEND_LETTER_S).assertEqual(90);
      expect(ApiConfig.TIMEOUT_FETCH_S).assertEqual(30);
      expect(ApiConfig.TIMEOUT_RHYTHM_S).assertEqual(15);
      expect(ApiConfig.TIMEOUT_DEFAULT_S).assertEqual(30);
    })

    // ---- 错误映射验收①：401 → 清登录态 ----

    it('map401ToUnauthorized', 0, () => {
      const e = HttpMapping.fromStatus(401, BODY_401);
      expect(e.isUnauthorized()).assertTrue();
      expect(e.statusCode).assertEqual(401);
      expect(e.kind).assertEqual(HttpErrorKind.Status);
      expect(e.envelope === null).assertFalse();
      expect(e.envelope !== null && e.envelope.code).assertEqual('invalid_token');
      expect(e.envelope !== null && e.envelope.message).assertEqual('登录已过期');
      expect(e.envelope !== null && e.envelope.detail).assertEqual('jwt expired');
    })

    it('gateClearsSessionOn401', 0, () => {
      let cleared = 0;
      const gate = new UnauthorizedGate(() => {
        cleared += 1;
      });
      expect(gate.handleError(HttpMapping.fromStatus(401, BODY_401))).assertTrue();
      expect(cleared).assertEqual(1);
    })

    it('gateIgnoresNon401', 0, () => {
      let cleared = 0;
      const gate = new UnauthorizedGate(() => {
        cleared += 1;
      });
      expect(gate.handleError(HttpMapping.fromStatus(429, BODY_429_RATE))).assertFalse();
      expect(gate.handleError(HttpMapping.fromStatus(500, 'http 500'))).assertFalse();
      expect(gate.handleError(HttpError.timeout(2300028))).assertFalse();
      expect(cleared).assertEqual(0);
    })

    // ---- 错误映射验收②：429 → 节奏原因（reason / nextLetterAt / retryAfter 在顶层） ----

    it('map429ToRateLimitReason', 0, () => {
      const e = HttpMapping.fromStatus(429, BODY_429_RATE);
      expect(e.isRateLimited()).assertTrue();
      expect(e.envelope !== null && e.envelope.reason).assertEqual('weekly_pending');
      expect(e.envelope !== null && e.envelope.nextLetterAt).assertEqual('2026-10-13T00:00:00.000Z');
      expect(e.envelope !== null && e.envelope.tier).assertEqual('free');
      expect(e.envelope !== null && e.envelope.code).assertEqual('rate_limited');
    })

    it('map429SendCodeRetryAfter', 0, () => {
      const e = HttpMapping.fromStatus(429, BODY_429_RETRY_AFTER);
      expect(e.isRateLimited()).assertTrue();
      expect(e.envelope !== null && e.envelope.retryAfter).assertEqual(42);
    })

    // ---- 错误映射验收③：5xx → 服务端错误（isServerError / 非 network） ----

    it('map5xxToServerError', 0, () => {
      const e = HttpMapping.fromStatus(502, BODY_502);
      expect(e.isServerError()).assertTrue();
      expect(e.isNetworkError()).assertFalse();
      expect(e.isUnauthorized()).assertFalse();
      expect(e.statusCode).assertEqual(502);
      expect(e.envelope !== null && e.envelope.code).assertEqual('ai_failed');
    })

    it('statusWithoutEnvelopeFallsBack', 0, () => {
      const e = HttpMapping.fromStatus(500, '<html>Bad Gateway</html>');
      expect(e.kind).assertEqual(HttpErrorKind.Status);
      expect(e.statusCode).assertEqual(500);
      expect(e.envelope === null).assertTrue();
      expect(e.message).assertEqual('http 500');
      expect(e.isServerError()).assertTrue();
    })

    // ---- 错误映射验收④：断网 / 超时 / 取消 → 网络错误（非服务端错误） ----

    it('mapTransportTimeoutCode', 0, () => {
      const e = HttpMapping.fromTransportCode(2300028, 'Timeout was reached');
      expect(e.kind).assertEqual(HttpErrorKind.Timeout);
      expect(e.isNetworkError()).assertTrue();
      expect(e.isServerError()).assertFalse();
      expect(e.transportCode).assertEqual(2300028);
    })

    it('mapTransportOfflineCodes', 0, () => {
      const dns = HttpMapping.fromTransportCode(2300006, 'Couldn\'t resolve host name');
      const conn = HttpMapping.fromTransportCode(2300007, 'Couldn\'t connect to server');
      expect(dns.kind).assertEqual(HttpErrorKind.Offline);
      expect(conn.kind).assertEqual(HttpErrorKind.Offline);
      expect(dns.isNetworkError() && conn.isNetworkError()).assertTrue();
    })

    it('mapOtherTransportCodeFallsBackToTransport', 0, () => {
      const e = HttpMapping.fromTransportCode(2300025, 'unknown socket error');
      expect(e.kind).assertEqual(HttpErrorKind.Transport);
      expect(e.isNetworkError()).assertTrue();
      expect(e.transportCode).assertEqual(2300025);
      expect(e.message).assertEqual('unknown socket error');
    })

    it('cancelledIsNetworkError', 0, () => {
      const e = HttpError.cancelled();
      expect(e.kind).assertEqual(HttpErrorKind.Cancelled);
      expect(e.isNetworkError()).assertTrue();
      expect(e.isServerError()).assertFalse();
    })

    // ---- ApiErrorEnvelope.parse：统一壳 / 顶层 extras / 非壳拒绝 ----

    it('envelopeParsesMinimalErrorShell', 0, () => {
      const env = ApiErrorEnvelope.parse('{"error":{"code":"not_found","message":"没找到"}}');
      expect(env === null).assertFalse();
      expect(env !== null && env.code).assertEqual('not_found');
      expect(env !== null && env.message).assertEqual('没找到');
      expect(env !== null && env.reason === undefined).assertTrue();
      expect(env !== null && env.retryAfter === undefined).assertTrue();
    })

    it('envelopeRejectsNonEnvelopeBodies', 0, () => {
      expect(ApiErrorEnvelope.parse('{"ok":true}')).assertNull();
      expect(ApiErrorEnvelope.parse('null')).assertNull();
      expect(ApiErrorEnvelope.parse('')).assertNull();
      expect(ApiErrorEnvelope.parse('not json at all')).assertNull();
      expect(ApiErrorEnvelope.parse('<html>502 Bad Gateway</html>')).assertNull();
    })

    it('envelopeRequiresCodeAndMessage', 0, () => {
      // 缺 message / error 不是对象 → 不是统一壳
      expect(ApiErrorEnvelope.parse('{"error":{"code":"x"}}')).assertNull();
      expect(ApiErrorEnvelope.parse('{"error":"boom"}')).assertNull();
    })

    // ---- ApiDates：带/不带毫秒两种都认，只认 ISO8601 + Z ----

    it('parseDateWithMilliseconds', 0, () => {
      const d = ApiDates.parse('2026-09-17T10:20:30.123Z');
      const expected = Date.UTC(2026, 8, 17, 10, 20, 30, 123);
      expect(d === null ? 0 : d.getTime()).assertEqual(expected);
    })

    it('parseDateWithoutMilliseconds', 0, () => {
      const d = ApiDates.parse('2026-10-13T00:00:00Z');
      const expected = Date.UTC(2026, 9, 13, 0, 0, 0);
      expect(d === null ? 0 : d.getTime()).assertEqual(expected);
    })

    it('parseDateRejectsNonIso8601', 0, () => {
      expect(ApiDates.parse('not-a-date')).assertNull();
      expect(ApiDates.parse('')).assertNull();
      expect(ApiDates.parse('2026-09-17')).assertNull(); // 只有日期不认（服务端一定带时间）
      expect(ApiDates.parse('2026-13-45T99:99:99Z')).assertNull(); // 形状对但非法日期
    })

    // ---- HttpRequest：构造器 / Bearer / 超时默认与覆盖 ----

    it('getDefaultsToDefaultTimeout', 0, () => {
      const r = HttpRequest.get(`${ApiConfig.BASE_URL}/me/rhythm`);
      expect(r.method).assertEqual(HttpMethod.GET);
      expect(r.timeoutSeconds).assertEqual(ApiConfig.TIMEOUT_DEFAULT_S);
      expect(r.body).assertEqual('');
    })

    it('customTimeoutOverridesDefault', 0, () => {
      const r = HttpRequest.get(`${ApiConfig.BASE_URL}/me/rhythm`, undefined,
        ApiConfig.TIMEOUT_RHYTHM_S);
      expect(r.timeoutSeconds).assertEqual(15);
    })

    it('bearerHeaderFormat', 0, () => {
      const h = HttpRequest.bearer('jwt-token-123');
      expect(h['Authorization']).assertEqual('Bearer jwt-token-123');
    })

    it('postJSONSetsContentTypeAndSerializesBody', 0, () => {
      const dto = new NicknamePatchDTO('青鸟');
      const r = HttpRequest.postJSON(`${ApiConfig.BASE_URL}/me`, dto);
      expect(r.method).assertEqual(HttpMethod.POST);
      expect(r.headers['Content-Type']).assertEqual('application/json');
      const back = JSON.parse(r.body) as NicknamePatchDTO;
      expect(back.displayName).assertEqual('青鸟');
    })

    it('patchJSONUsesPatchMethod', 0, () => {
      const r = HttpRequest.patchJSON(`${ApiConfig.BASE_URL}/me`, new NicknamePatchDTO('小明'));
      expect(r.method).assertEqual(HttpMethod.PATCH);
      expect(r.headers['Content-Type']).assertEqual('application/json');
    })

    it('bearerMergesIntoPostHeaders', 0, () => {
      const r = HttpRequest.postJSON(`${ApiConfig.BASE_URL}/letter`,
        new NicknamePatchDTO('青鸟'), HttpRequest.bearer('tok'));
      expect(r.headers['Authorization']).assertEqual('Bearer tok');
      expect(r.headers['Content-Type']).assertEqual('application/json');
    })

    // ---- HttpMapping.decode：注入 parse 泛型解码，解码失败折成 Decoding 档 ----

    it('decodeInjectsParseClosure', 0, () => {
      const len = HttpMapping.decode<string>('hello', (raw: string) => raw);
      expect(len).assertEqual('hello');
      const parsed = HttpMapping.decode<NicknamePatchDTO>('{"displayName":"青鸟"}',
        (raw: string) => JSON.parse(raw) as NicknamePatchDTO);
      expect(parsed.displayName).assertEqual('青鸟');
    })

    it('decodeFailureBecomesDecodingError', 0, () => {
      let caught: HttpError | null = null;
      try {
        HttpMapping.decode<NicknamePatchDTO>('not json',
          (raw: string) => JSON.parse(raw) as NicknamePatchDTO);
      } catch (e) {
        caught = e instanceof HttpError ? e : null;
      }
      expect(caught === null).assertFalse();
      expect(caught !== null && caught.kind).assertEqual(HttpErrorKind.Decoding);
      expect(caught !== null && caught.isServerError()).assertFalse();
      expect(caught !== null && caught.isNetworkError()).assertFalse();
    })

    // ---- HttpError 七档分类口径 ----

    it('badURLAndOfflineFactories', 0, () => {
      expect(HttpError.badURL().kind).assertEqual(HttpErrorKind.BadURL);
      const off = HttpError.offline(2300006);
      expect(off.kind).assertEqual(HttpErrorKind.Offline);
      expect(off.transportCode).assertEqual(2300006);
      expect(off.isNetworkError()).assertTrue();
    })

    it('statusErrorCarriesRawBodyForDebug', 0, () => {
      const e = HttpMapping.fromStatus(429, BODY_429_RATE);
      expect(e.body).assertEqual(BODY_429_RATE);
      expect(e.statusCode).assertEqual(429);
    })
  })
}
