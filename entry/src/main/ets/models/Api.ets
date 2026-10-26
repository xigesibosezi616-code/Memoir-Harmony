/**
 * 后端 DTO 与纯解析（10_BUILD_MANUAL.md 4.2；02_BACKEND_API.md types.ts 逐字段对齐）。
 * 对应 iOS `Models/Api.swift` 的 Decodable 层；类型同步规则：后端改 types.ts
 * → 鸿蒙这里的字段与解析当天跟着改（02「类型同步规则」）。
 *
 * 约定（与 iOS Codable 语义对齐，坏数据宁可折成 decoding 错也不静默上屏）：
 * - `JSON.parse` 一次 cast 到 raw 接口，再逐字段 typeof 校验——缺必填字段抛错，
 *   由 HttpMapping.decode 统一折成 HttpError.decoding
 * - 可选字段缺省统一归一为 ''（'' = 未绑定 / 无），UI 不再判 undefined
 * - `id` 后端 number | string 两种都发过，统一归一为 string
 * - `bindings` 只留 provider 名单（'phone' / 'apple' / …），账号页显示绑定项够用
 */

/** 单个第三方绑定的原样形状 */
interface BindingRaw {
  provider?: string;
}

/** GET /auth/* 响应里 user 对象的原样形状（types.ts UserDTO）。
 *  bindings 元素额外容忍 string：会话持久化（UserSession → JSON.stringify(UserDTO)）
 *  落盘的是 provider 字符串数组，恢复时与线格式同路解析（2026-10-24 真机：
 *  恢复丢绑定态 → 华为行重启后翻转未绑）。 */
interface UserRaw {
  id?: number | string;
  phone?: string;
  email?: string;
  displayName?: string;
  penPalName?: string;
  bindings?: (BindingRaw | string)[];
}

interface AuthResponseRaw {
  token?: string;
  user?: UserRaw;
}

interface SendCodeResponseRaw {
  retryAfter?: number;
}

interface SubscriptionRaw {
  isActive?: boolean;
  productId?: string;
  platform?: string;
  expiresAt?: string;
}

interface MeResponseRaw {
  user?: UserRaw;
  subscription?: SubscriptionRaw;
}

interface BindPhoneResponseRaw {
  switchedAccount?: boolean;
  token?: string;
  user?: UserRaw;
}

interface ChangePhoneResponseRaw {
  ok?: boolean;
  user?: UserRaw;
}

interface DeleteAccountResponseRaw {
  ok?: boolean;
  /** 后端历史字段（iOS 用）；鸿蒙恒 false，留着不拒收老形状 */
  appleRevoked?: boolean;
}

/** GET /me/rhythm 响应的原样形状（types.ts RhythmResponse） */
interface RhythmResponseRaw {
  tier?: string;
  canRequestNow?: boolean;
  reason?: string;
  nextLetterAt?: string | null;
}

/** 只回 {ok:true} 的轻响应（PATCH /me 等）的原始形状 */
interface OkResponseRaw {
  ok?: boolean;
}

/** 校验过的用户快照（id 统一 string；可选字段归一 ''；bindings 只留 provider 名单） */
export class UserDTO {
  readonly id: string;
  /** '' = 未绑定手机号 */
  readonly phone: string;
  readonly displayName: string;
  readonly penPalName: string;
  readonly bindings: string[];

  constructor(id: string, phone: string, displayName: string,
    penPalName: string, bindings: string[]) {
    this.id = id;
    this.phone = phone;
    this.displayName = displayName;
    this.penPalName = penPalName;
    this.bindings = bindings;
  }
}

/** POST /auth/verify-code 成功响应 */
export class AuthResponse {
  readonly token: string;
  readonly user: UserDTO;

  constructor(token: string, user: UserDTO) {
    this.token = token;
    this.user = user;
  }
}

/** POST /auth/send-code 成功响应（retryAfter 驱动重发倒计时） */
export class SendCodeResponse {
  readonly retryAfter: number;

  constructor(retryAfter: number) {
    this.retryAfter = retryAfter;
  }
}

/** GET /me 里的订阅状态（可选字段归一 ''；expiresAt 原样 ISO 串，日期由调用方 ApiDates 解析） */
export class SubscriptionStatusDTO {
  readonly isActive: boolean;
  readonly productId: string;
  readonly platform: string;
  readonly expiresAt: string;

  constructor(isActive: boolean, productId: string, platform: string, expiresAt: string) {
    this.isActive = isActive;
    this.productId = productId;
    this.platform = platform;
    this.expiresAt = expiresAt;
  }
}

export class MeResponse {
  readonly user: UserDTO;
  readonly subscription: SubscriptionStatusDTO;

  constructor(user: UserDTO, subscription: SubscriptionStatusDTO) {
    this.user = user;
    this.subscription = subscription;
  }
}

/**
 * POST /me/bindings/phone 成功响应（4.3 绑定流用；先随 DTO 层一次对齐）。
 * switchedAccount = 该手机号本就属于老账号，服务端已转移绑定并删空壳——
 * 此时 token 必换（旧 token 指向的身份已不存在，不换下一个请求就是 401）。
 */
export class BindPhoneResponse {
  readonly switchedAccount: boolean;
  /** switchedAccount 为 true 时必有新 token；false 时为 '' */
  readonly token: string;
  readonly user: UserDTO;

  constructor(switchedAccount: boolean, token: string, user: UserDTO) {
    this.switchedAccount = switchedAccount;
    this.token = token;
    this.user = user;
  }
}

/** POST /me/bindings/phone/change 成功响应（4.3 换绑；user 为换绑后的快照） */
export class ChangePhoneResponse {
  readonly user: UserDTO;

  constructor(user: UserDTO) {
    this.user = user;
  }
}

/** POST /me/delete 成功响应（账号已在服务端删除，本地只剩清登录态） */
export class DeleteAccountResponse {
  readonly ok: boolean;

  constructor(ok: boolean) {
    this.ok = ok;
  }
}

/**
 * GET /me/rhythm 成功响应（5.2 邮筒页进页面就问，提前说明「这周已经寄过了」）。
 * 判定权只在服务端，客户端不算额度（02_BACKEND_API.md；R-POST-05）。
 */
export class RhythmResponse {
  /** 服务端认的档位：'free' / 'subscribed' */
  readonly tier: string;
  /** 现在能不能寄 */
  readonly canRequestNow: boolean;
  /** 'ok' / 'weekly_pending' / 'daily_cap' / 'monthly_cap' / 'welcome_pending'（R-POST-12 文案键） */
  readonly reason: string;
  /** 下一封最早什么时候能寄（ISO 串）；现在就能寄时为 '' */
  readonly nextLetterAt: string;

  constructor(tier: string, canRequestNow: boolean, reason: string, nextLetterAt: string) {
    this.tier = tier;
    this.canRequestNow = canRequestNow;
    this.reason = reason;
    this.nextLetterAt = nextLetterAt;
  }
}

/** 必填 string 字段校验（缺省 / 非 string 抛错） */
function requireString(value: string | undefined, field: string): string {
  if (typeof value !== 'string') {
    throw new Error(`${field} missing or not a string`);
  }
  return value;
}

/** 可选 string 字段归一（缺省 / 非 string → ''） */
function optionalString(value: string | undefined): string {
  return typeof value === 'string' ? value : '';
}

/** raw user → UserDTO（id number|string 归一 string；bindings 抽 provider 名单） */
function userFromRaw(r: UserRaw): UserDTO {
  if (r.id === undefined) {
    throw new Error('user.id missing');
  }
  const id: string = typeof r.id === 'number' ? String(r.id) : r.id;
  if (typeof id !== 'string' || id.length === 0) {
    throw new Error('user.id invalid');
  }
  const providers: string[] = [];
  if (r.bindings !== undefined) {
    for (const b of r.bindings) {
      // 线格式 {provider} 或会话持久化的裸字符串（见 UserRaw 注释）都收
      const provider: string = typeof b === 'string' ? b : (b.provider ?? '');
      if (provider.length > 0) {
        providers.push(provider);
      }
    }
  }
  return new UserDTO(id, optionalString(r.phone), optionalString(r.displayName),
    requireString(r.penPalName, 'user.penPalName'), providers);
}

/** 顶层必须是 JSON 对象（'null' / '[]' / 数字都拒） */
function requireObject<T>(raw: string): T {
  const parsed = JSON.parse(raw) as T;
  if (parsed === null || typeof parsed !== 'object') {
    throw new Error('response body is not a json object');
  }
  return parsed;
}

export function parseUserDto(raw: string): UserDTO {
  return userFromRaw(requireObject<UserRaw>(raw));
}

export function parseAuthResponse(raw: string): AuthResponse {
  const r = requireObject<AuthResponseRaw>(raw);
  if (r.user === undefined) {
    throw new Error('auth.user missing');
  }
  return new AuthResponse(requireString(r.token, 'auth.token'), userFromRaw(r.user));
}

export function parseSendCodeResponse(raw: string): SendCodeResponse {
  const r = requireObject<SendCodeResponseRaw>(raw);
  if (typeof r.retryAfter !== 'number') {
    throw new Error('sendCode.retryAfter missing');
  }
  return new SendCodeResponse(r.retryAfter);
}

export function parseMeResponse(raw: string): MeResponse {
  const r = requireObject<MeResponseRaw>(raw);
  if (r.user === undefined) {
    throw new Error('me.user missing');
  }
  if (r.subscription === undefined) {
    throw new Error('me.subscription missing');
  }
  if (typeof r.subscription.isActive !== 'boolean') {
    throw new Error('me.subscription.isActive missing');
  }
  const sub = new SubscriptionStatusDTO(r.subscription.isActive,
    optionalString(r.subscription.productId), optionalString(r.subscription.platform),
    optionalString(r.subscription.expiresAt));
  return new MeResponse(userFromRaw(r.user), sub);
}

export function parseBindPhoneResponse(raw: string): BindPhoneResponse {
  const r = requireObject<BindPhoneResponseRaw>(raw);
  if (r.user === undefined) {
    throw new Error('bindPhone.user missing');
  }
  if (typeof r.switchedAccount !== 'boolean') {
    throw new Error('bindPhone.switchedAccount missing');
  }
  return new BindPhoneResponse(r.switchedAccount, optionalString(r.token), userFromRaw(r.user));
}

export function parseChangePhoneResponse(raw: string): ChangePhoneResponse {
  const r = requireObject<ChangePhoneResponseRaw>(raw);
  if (r.ok !== true) {
    throw new Error('changePhone.ok missing');
  }
  if (r.user === undefined) {
    throw new Error('changePhone.user missing');
  }
  return new ChangePhoneResponse(userFromRaw(r.user));
}

export function parseDeleteAccountResponse(raw: string): DeleteAccountResponse {
  const r = requireObject<DeleteAccountResponseRaw>(raw);
  if (r.ok !== true) {
    throw new Error('deleteAccount.ok missing');
  }
  return new DeleteAccountResponse(true);
}

export function parseRhythmResponse(raw: string): RhythmResponse {
  const r = requireObject<RhythmResponseRaw>(raw);
  if (typeof r.canRequestNow !== 'boolean') {
    throw new Error('rhythm.canRequestNow missing');
  }
  return new RhythmResponse(optionalString(r.tier), r.canRequestNow,
    optionalString(r.reason), optionalString(r.nextLetterAt ?? undefined));
}

/** 校验 {ok:true} 轻响应（PATCH /me；非 ok 折 Decoding 档，防 200 空/坏体静默通过） */
export function parseOkResponse(raw: string): void {
  const r = requireObject<OkResponseRaw>(raw);
  if (r.ok !== true) {
    throw new Error('ok missing');
  }
}
