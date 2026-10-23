/**
 * 统一网络错误模型（10_BUILD_MANUAL.md 4.1）。对应 iOS `HTTPClient.swift` 的 `HTTPError`。
 *
 * 七档分类：badURL / offline / timeout / cancelled / status / decoding / transport。
 * 关键裁决口径（02_BACKEND_API.md）：
 * - **断网 / 超时 / 取消 / 传输故障不是服务端错误**：寄信场景不计失败次数，30 秒后接着寄
 *   （R-OUTBOX-04）——调用方用 `isNetworkError()` 判
 * - **status（4xx/5xx）才是服务端错误**，统一错误 envelope 尽力解析挂在 `envelope` 上
 * - **401 → 清本地登录态**（任何接口；UI 自然回未登录）——调用方用 `isUnauthorized()` 判
 * - **429 是正常业务分支**（防刷 / 来信节奏），不是失败——调用方用 `isRateLimited()` 判
 *
 * message 走技术英文（服务层不上屏）；用户可见文案由 4.2+/5.x 调用方按 kind /
 * envelope.code 取七语言字符串资源。
 */
import { ApiErrorEnvelope } from './ApiError';

export enum HttpErrorKind {
  BadURL = 'badURL',
  Offline = 'offline',
  Timeout = 'timeout',
  Cancelled = 'cancelled',
  Status = 'status',
  Decoding = 'decoding',
  Transport = 'transport'
}

export class HttpError extends Error {
  readonly kind: HttpErrorKind;
  /** HTTP 状态码（仅 Status 档非 0） */
  readonly statusCode: number;
  /** 原始响应体（Status 档保留，debug 用） */
  readonly body: string;
  /** 服务端统一错误 envelope（能解析出才有，否则 null） */
  readonly envelope: ApiErrorEnvelope | null;
  /** 底层传输错误码（offline/timeout/transport 档保留定位用，@ohos.net.http 口径） */
  readonly transportCode: number;

  constructor(kind: HttpErrorKind, message: string, statusCode: number = 0,
    body: string = '', envelope: ApiErrorEnvelope | null = null, transportCode: number = 0) {
    super(message);
    this.name = 'HttpError';
    this.kind = kind;
    this.statusCode = statusCode;
    this.body = body;
    this.envelope = envelope;
    this.transportCode = transportCode;
  }

  /** 401：调用方须清本地 token + 用户快照（02_BACKEND_API.md「鉴权」） */
  isUnauthorized(): boolean {
    return this.kind === HttpErrorKind.Status && this.statusCode === 401;
  }

  /** 429：正常业务分支（防刷 / 来信节奏），先补领一次再决定退回（R-OUTBOX-08） */
  isRateLimited(): boolean {
    return this.kind === HttpErrorKind.Status && this.statusCode === 429;
  }

  /** 服务端主动回的错（4xx/5xx，含 429） */
  isServerError(): boolean {
    return this.kind === HttpErrorKind.Status;
  }

  /** 断网 / 超时 / 取消 / 传输故障：不是服务端错误，寄信场景不计失败次数（R-OUTBOX-04） */
  isNetworkError(): boolean {
    return this.kind === HttpErrorKind.Offline || this.kind === HttpErrorKind.Timeout ||
      this.kind === HttpErrorKind.Cancelled || this.kind === HttpErrorKind.Transport;
  }

  static badURL(): HttpError {
    return new HttpError(HttpErrorKind.BadURL, 'invalid request url');
  }

  static offline(transportCode: number = 0): HttpError {
    return new HttpError(HttpErrorKind.Offline, 'network unreachable', 0, '', null, transportCode);
  }

  static timeout(transportCode: number = 0): HttpError {
    return new HttpError(HttpErrorKind.Timeout, 'request timed out', 0, '', null, transportCode);
  }

  /** @ohos.net.http 无显式取消错误码，取消走自建控制路径（5.x 寄信队列取消时用） */
  static cancelled(): HttpError {
    return new HttpError(HttpErrorKind.Cancelled, 'request cancelled');
  }

  static decoding(detail: string): HttpError {
    return new HttpError(HttpErrorKind.Decoding, `decode failed: ${detail}`);
  }

  static transport(transportCode: number, detail: string): HttpError {
    return new HttpError(HttpErrorKind.Transport, detail, 0, '', null, transportCode);
  }
}
