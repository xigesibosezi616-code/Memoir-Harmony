/**
 * 认证接口客户端（10_BUILD_MANUAL.md 4.2/4.3）。对应 iOS `AuthService.swift`（LiveAuthService）。
 *
 * 接口（02_BACKEND_API.md）：send-code / verify-code / me / me-bindings-phone /
 * me-bindings-phone-change / me-delete；超时统一 15s（iOS LiveAuthService 注释：
 * 登录链路轻量点查，30s 太久）。错误不上屏：HttpError 抛给调用方（LoginView 等），
 * 文案本地化在视图层做。
 * U02 更新包（2026-10-22）新增：/auth/huawei、/me/bindings/huawei、
 * /me/delete 的华为账号验证字段（Q1/Q17 的解法）。
 */
import { ApiConfig } from '../http/ApiConfig';
import { HttpRequest } from '../http/HttpRequest';
import { HarmonyHttpClient } from '../http/HarmonyHttpClient';
import { AuthResponse, MeResponse, SendCodeResponse, BindPhoneResponse,
  ChangePhoneResponse, DeleteAccountResponse, RhythmResponse,
  parseAuthResponse, parseMeResponse, parseSendCodeResponse,
  parseBindPhoneResponse, parseChangePhoneResponse, parseDeleteAccountResponse,
  parseRhythmResponse, parseOkResponse } from '../../models/Api';

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

  /** POST /auth/huawei：{idToken} → AuthResponse（U02 华为账号登录，和 verify-code 同构；
   *  这个华为账号没绑过就新建账号并绑上；服务端没配华为时 503 huawei_disabled，调用方按分支提示） */
  async loginWithHuawei(idToken: string): Promise<AuthResponse> {
    const body: Record<string, string> = { 'idToken': idToken };
    const request = HttpRequest.postJSON(`${ApiConfig.BASE_URL}/auth/huawei`, body,
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

  /** POST /me/bindings/huawei：{idToken} → {ok:true}（U02 绑定华为账号；
   *  响应不带 user，绑定结果经 GET /me 刷快照；409 服务端文案透传由调用方做） */
  async bindHuawei(idToken: string, token: string): Promise<void> {
    const body: Record<string, string> = { 'idToken': idToken };
    const request = HttpRequest.postJSON(`${ApiConfig.BASE_URL}/me/bindings/huawei`, body,
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

  /** POST /me/delete 用华为账号验证本人（U02）：{huaweiIdToken, huaweiAuthorizationCode}
   *  一起交——服务端验 idToken 并用授权码撤销华为账号授权；撤销失败不阻断注销（ok 照判） */
  async deleteAccountWithHuawei(huaweiIdToken: string, huaweiAuthorizationCode: string,
    token: string): Promise<DeleteAccountResponse> {
    const body: Record<string, string> = {
      'huaweiIdToken': huaweiIdToken, 'huaweiAuthorizationCode': huaweiAuthorizationCode };
    const request = HttpRequest.postJSON(`${ApiConfig.BASE_URL}/me/delete`, body,
      HttpRequest.bearer(token), ApiConfig.TIMEOUT_AUTH_S);
    return this.client.send<DeleteAccountResponse>(request, parseDeleteAccountResponse);
  }

  /** GET /me/rhythm（5.2 邮筒页进页面就问）：现在能不能寄信。判定权只在服务端，
   *  客户端只拿它提前说明（R-POST-05/12）；问不到由调用方当能寄，最终由服务端拦 */
  async fetchRhythm(token: string): Promise<RhythmResponse> {
    const request = HttpRequest.get(`${ApiConfig.BASE_URL}/me/rhythm`,
      HttpRequest.bearer(token), ApiConfig.TIMEOUT_RHYTHM_S);
    return this.client.send<RhythmResponse>(request, parseRhythmResponse);
  }
}
