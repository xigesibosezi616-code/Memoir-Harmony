/**
 * 认证接口客户端（10_BUILD_MANUAL.md 4.2）。对应 iOS `AuthService.swift`（LiveAuthService）。
 *
 * 三接口（02_BACKEND_API.md「auth」）：send-code / verify-code / me；
 * 超时统一 15s（iOS LiveAuthService 注释：登录链路轻量点查，30s 太久）。
 * 错误不上屏：HttpError 抛给调用方（LoginView），文案本地化在那里做。
 * 华为账号登录（POST /auth/huawei）后端未实现（09 Q1），4.4 再加方法。
 */
import { ApiConfig } from '../http/ApiConfig';
import { HttpRequest } from '../http/HttpRequest';
import { HarmonyHttpClient } from '../http/HarmonyHttpClient';
import { AuthResponse, MeResponse, SendCodeResponse,
  parseAuthResponse, parseMeResponse, parseSendCodeResponse } from '../../models/Api';

export class AuthService {
  private readonly client: HarmonyHttpClient;

  constructor(client: HarmonyHttpClient) {
    this.client = client;
  }

  /** POST /auth/send-code：{target} → {ok, retryAfter}（retryAfter 驱动重发倒计时） */
  async sendCode(phone: string): Promise<SendCodeResponse> {
    const body: Record<string, string> = { 'target': phone };
    const request = HttpRequest.postJSON(`${ApiConfig.BASE_URL}/auth/send-code`, body,
      undefined, ApiConfig.TIMEOUT_AUTH_S);
    return this.client.send<SendCodeResponse>(request, parseSendCodeResponse);
  }

  /** POST /auth/verify-code：{target, code} → AuthResponse（未注册自动建号） */
  async login(phone: string, code: string): Promise<AuthResponse> {
    const body: Record<string, string> = { 'target': phone, 'code': code };
    const request = HttpRequest.postJSON(`${ApiConfig.BASE_URL}/auth/verify-code`, body,
      undefined, ApiConfig.TIMEOUT_AUTH_S);
    return this.client.send<AuthResponse>(request, parseAuthResponse);
  }

  /** GET /me：{user, subscription}（启动刷新快照 / 订阅判定 4.x 用） */
  async fetchMe(token: string): Promise<MeResponse> {
    const request = HttpRequest.get(`${ApiConfig.BASE_URL}/me`, HttpRequest.bearer(token),
      ApiConfig.TIMEOUT_AUTH_S);
    return this.client.send<MeResponse>(request, parseMeResponse);
  }
}
