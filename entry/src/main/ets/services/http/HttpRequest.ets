/**
 * 请求模型与常用构造器（10_BUILD_MANUAL.md 4.1）。对应 iOS `HTTPClient.swift` 的 `HTTPRequest`。
 *
 * 鉴权头由调用方传 `bearer(token)`（4.2 起 token 出安全存储）；本层不持有会话。
 * body 是已序列化的 JSON 字符串——DTO 序列化在构造器里做（ArkTS 无反射，
 * 调用方传显式类型的 DTO 类实例 / Record，不收裸字面量）。
 */
import { ApiConfig } from './ApiConfig';

export enum HttpMethod {
  GET = 'GET',
  POST = 'POST',
  PATCH = 'PATCH'
}

/** 复制 header（浅拷贝；undefined → 空 Record），构造器内改不污染调用方传入的表 */
function copyHeaders(src: Record<string, string> | undefined): Record<string, string> {
  const dst: Record<string, string> = {};
  if (src !== undefined) {
    const keys = Object.keys(src);
    for (const k of keys) {
      dst[k] = src[k];
    }
  }
  return dst;
}

export class HttpRequest {
  readonly url: string;
  readonly method: HttpMethod;
  readonly headers: Record<string, string>;
  /** 已序列化请求体（'' = 无 body） */
  readonly body: string;
  /** 单次请求超时（秒） */
  readonly timeoutSeconds: number;

  constructor(url: string, method: HttpMethod, headers: Record<string, string>,
    body: string, timeoutSeconds: number) {
    this.url = url;
    this.method = method;
    this.headers = headers;
    this.body = body;
    this.timeoutSeconds = timeoutSeconds;
  }

  /** GET（默认超时 ApiConfig.TIMEOUT_DEFAULT_S） */
  static get(url: string, headers?: Record<string, string>,
    timeoutSeconds?: number): HttpRequest {
    return new HttpRequest(url, HttpMethod.GET, copyHeaders(headers), '',
      timeoutSeconds ?? ApiConfig.TIMEOUT_DEFAULT_S);
  }

  /** POST + JSON body：自动加 Content-Type: application/json */
  static postJSON(url: string, body: Object, headers?: Record<string, string>,
    timeoutSeconds?: number): HttpRequest {
    const merged = copyHeaders(headers);
    merged['Content-Type'] = 'application/json';
    return new HttpRequest(url, HttpMethod.POST, merged, JSON.stringify(body),
      timeoutSeconds ?? ApiConfig.TIMEOUT_DEFAULT_S);
  }

  /** PATCH + JSON body（局部更新，如 PATCH /me 只改昵称） */
  static patchJSON(url: string, body: Object, headers?: Record<string, string>,
    timeoutSeconds?: number): HttpRequest {
    const merged = copyHeaders(headers);
    merged['Content-Type'] = 'application/json';
    return new HttpRequest(url, HttpMethod.PATCH, merged, JSON.stringify(body),
      timeoutSeconds ?? ApiConfig.TIMEOUT_DEFAULT_S);
  }

  /** Bearer 鉴权头（Authorization: Bearer <jwt>；除 /health、/auth/* 外所有接口要带） */
  static bearer(token: string): Record<string, string> {
    const h: Record<string, string> = {};
    h['Authorization'] = `Bearer ${token}`;
    return h;
  }
}
