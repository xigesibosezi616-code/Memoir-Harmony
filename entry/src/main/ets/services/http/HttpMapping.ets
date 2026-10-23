/**
 * 纯函数错误映射（10_BUILD_MANUAL.md 4.1）。对应 iOS `URLSessionHTTPClient.map(_:)`。
 *
 * 与执行壳 `HarmonyHttpClient` 分离：本文件不 import 任何 kit，
 * 本地单测可直接 import（HMS kit 类型本地跑不了，2.10 范式）。
 *
 * 传输错误码口径（@ohos.net.http = 2300000 + curl 错误码）：
 * - 2300028（curl 28）→ 超时
 * - 2300006 / 2300007（curl 6/7 解析主机失败 / 连接失败）→ 断网
 * - 其余 → 传输故障兜底
 * 取消无显式错误码，走 HttpError.cancelled 自建控制路径（5.x 寄信队列）。
 */
import { HttpError, HttpErrorKind } from './HttpError';
import { ApiErrorEnvelope } from './ApiError';

export class HttpMapping {
  /** HTTP 状态码 + 响应体 → Status 档 HttpError（统一 envelope 尽力解析挂上） */
  static fromStatus(statusCode: number, body: string): HttpError {
    const envelope = ApiErrorEnvelope.parse(body);
    const message = envelope !== null ? envelope.message : `http ${statusCode}`;
    return new HttpError(HttpErrorKind.Status, message, statusCode, body, envelope);
  }

  /** @ohos.net.http 传输错误码 → Offline / Timeout / Transport 档 */
  static fromTransportCode(code: number, message: string): HttpError {
    if (code === 2300028) {
      return HttpError.timeout(code);
    }
    if (code === 2300006 || code === 2300007) {
      return HttpError.offline(code);
    }
    return HttpError.transport(code, message);
  }

  /**
   * 注入 parse 闭包解码响应体（ArkTS 无反射，泛型解码靠函数注入）；
   * parse 抛错统一折成 Decoding 档，不让底层解码异常裸穿网络边界。
   */
  static decode<T>(raw: string, parse: (raw: string) => T): T {
    try {
      return parse(raw);
    } catch (e) {
      throw HttpError.decoding(e instanceof Error ? e.message : String(e));
    }
  }
}

/**
 * 401 闸门：任何接口 401 → 清本地登录态（token + 用户快照），UI 自然回未登录
 * （02_BACKEND_API.md「鉴权」；iOS `UserSession.clear()` 同款时机）。
 * 会话本体 4.2 才有，这里只持清理回调；执行壳收到 Status 档错误时过一遍闸门。
 */
export class UnauthorizedGate {
  private readonly clear: () => void;

  constructor(clear: () => void) {
    this.clear = clear;
  }

  /** 401 触发清理并返回 true；其余错误不动作 */
  handleError(error: HttpError): boolean {
    if (error.isUnauthorized()) {
      this.clear();
      return true;
    }
    return false;
  }
}
