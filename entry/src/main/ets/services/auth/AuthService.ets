/**
 * 认证接口客户端（10_BUILD_MANUAL.md 4.2/4.3）。对应 iOS `AuthService.swift`（LiveAuthService）。
 *
 * 接口（02_BACKEND_API.md）：send-code / verify-code / me / me-bindings-phone /
 * me-bindings-phone-change / me-delete；超时统一 15s（iOS LiveAuthService 注释：
 * 登录链路轻量点查，30s 太久）。错误不上屏：HttpError 抛给调用方（LoginView 等），
 * 文案本地化在视图层做。华为账号登录（POST /auth/huawei）后端未实现（09 Q1），4.4 再加方法。
 */
import { ApiConfig } from '../http/ApiConfig';
import { HttpRequest } from '../http/HttpRequest';
import { HarmonyHttpClient } from '../http/HarmonyHttpClient';
import { AuthResponse, MeResponse, SendCodeResponse, BindPhoneResponse,
  ChangePhoneResponse, DeleteAccountResponse,
  parseAuthResponse, parseMeResponse, parseSendCodeResponse,
  parseBindPhoneResponse, parseChangePhoneResponse, parseDeleteAccountResponse,
  parseOkResponse } from '../../models/Api';

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

  /** POST /me/bindings/phone：{target, code} → BindPhoneResponse（switchedAccount 时必须换 token） */
  async bindPhone(phone: string, code: string, token: string): Promise<BindPhoneResponse> {
    const body: Record<string, string> = { 'target': phone, 'code': code };
    const request = HttpRequest.postJSON(`${ApiConfig.BASE_URL}/me/bindings/phone`, body,
      HttpRequest.bearer(token), ApiConfig.TIMEOUT_AUTH_S);
    return this.client.send<BindPhoneResponse>(request, parseBindPhoneResponse);
  }

  /** POST /me/bindings/phone/change：{oldCode, newTarget, newCode} → 换绑后快照
   * （旧号码验证本人 + 新号验证归属，两个码都由 sendCode 发） */
  async changePhone(oldCode: string, newPhone: string, newCode: string,
    token: string): Promise<ChangePhoneResponse> {
    const body: Record<string, string> = {
      'oldCode': oldCode, 'newTarget': newPhone, 'newCode': newCode };
    const request = HttpRequest.postJSON(`${ApiConfig.BASE_URL}/me/bindings/phone/change`,
      body, HttpRequest.bearer(token), ApiConfig.TIMEOUT_AUTH_S);
    return this.client.send<ChangePhoneResponse>(request, parseChangePhoneResponse);
  }

  /** PATCH /me：{displayName}（≤64 字，空串 = 清空；响应体 {ok:true} 由 parseOkResponse 校验） */
  async updateDisplayName(displayName: string, token: string): Promise<void> {
    const body: Record<string, string> = { 'displayName': displayName };
    const request = HttpRequest.patchJSON(`${ApiConfig.BASE_URL}/me`, body,
      HttpRequest.bearer(token), ApiConfig.TIMEOUT_AUTH_S);
    await this.client.send<void>(request, parseOkResponse);
  }

  /** POST /me/delete：{code}（验证码发给账号绑定的号；成功后账号在服务端已删除） */
  async deleteAccount(code: string, token: string): Promise<DeleteAccountResponse> {
    const body: Record<string, string> = { 'code': code };
    const request = HttpRequest.postJSON(`${ApiConfig.BASE_URL}/me/delete`, body,
      HttpRequest.bearer(token), ApiConfig.TIMEOUT_AUTH_S);
    return this.client.send<DeleteAccountResponse>(request, parseDeleteAccountResponse);
  }
}
