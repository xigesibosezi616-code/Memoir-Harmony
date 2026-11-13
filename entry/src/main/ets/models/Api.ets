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
import { ApiDates } from '../services/http/ApiDates';
import { isUuidString } from './Uuid';

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

/** GET /me/stamps、POST /me/stamps/claim 响应的原样形状（U01 `StampsResponse`） */
interface StampsResponseRaw {
  balance?: number;
  cap?: number;
  /** 下一包什么时候到（ISO 串） */
  nextPackAt?: string;
  packReady?: boolean;
  isMember?: boolean;
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
 * 邮票夹（`GET /me/stamps`，U01 2026-10-16 起取代来信节奏；iOS `StampWallet`）。
 * **余额只认服务端**，客户端拿它提前告诉用户「邮票用完了、下一包几时到」，
 * 最终由服务端扣、由服务端拦。
 */
export class StampWallet {
  readonly balance: number;
  /** 邮票夹最多放几张（不清空、一直攒；服务端固定给 999，只是防呆） */
  readonly cap: number;
  /** 下一包什么时候到（毫秒） */
  readonly nextPackAtMs: number;
  /** 现在就能领一包 */
  readonly packReady: boolean;
  readonly isMember: boolean;

  constructor(balance: number, cap: number, nextPackAtMs: number,
    packReady: boolean, isMember: boolean) {
    this.balance = balance;
    this.cap = cap;
    this.nextPackAtMs = nextPackAtMs;
    this.packReady = packReady;
    this.isMember = isMember;
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

export function parseStampsResponse(raw: string): StampWallet {
  const r = requireObject<StampsResponseRaw>(raw);
  if (typeof r.balance !== 'number') {
    throw new Error('stamps.balance missing');
  }
  if (typeof r.cap !== 'number') {
    throw new Error('stamps.cap missing');
  }
  const nextPackAt = ApiDates.parse(requireString(r.nextPackAt, 'stamps.nextPackAt'));
  if (nextPackAt === null) {
    throw new Error('stamps.nextPackAt is not ISO8601');
  }
  return new StampWallet(r.balance, r.cap, nextPackAt.getTime(),
    r.packReady === true, r.isMember === true);
}

// ---- 7.1 华为支付（U02 `POST /subscription/sync-huawei`）----

interface SubscriptionSyncResponseRaw {
  ok?: boolean;
  subscription?: SubscriptionRaw;
  finished?: boolean;
}

/**
 * POST /subscription/sync-huawei 成功响应（U02 R-MEMBER-09 第 5–6 步）：
 * 服务端验华为签名后回写会员状态。`finished == false` → 客户端自己调
 * `iap.finishPurchase` 确认发货（缺省按 false，宁多确认一次）。
 */
export class SubscriptionSyncResponse {
  readonly subscription: SubscriptionStatusDTO;
  readonly finished: boolean;

  constructor(subscription: SubscriptionStatusDTO, finished: boolean) {
    this.subscription = subscription;
    this.finished = finished;
  }
}

export function parseSubscriptionSyncResponse(raw: string): SubscriptionSyncResponse {
  const r = requireObject<SubscriptionSyncResponseRaw>(raw);
  if (r.ok !== true) {
    throw new Error('subscriptionSync.ok missing');
  }
  if (r.subscription === undefined) {
    throw new Error('subscriptionSync.subscription missing');
  }
  if (typeof r.subscription.isActive !== 'boolean') {
    throw new Error('subscriptionSync.subscription.isActive missing');
  }
  const sub = new SubscriptionStatusDTO(r.subscription.isActive,
    optionalString(r.subscription.productId), optionalString(r.subscription.platform),
    optionalString(r.subscription.expiresAt));
  return new SubscriptionSyncResponse(sub, r.finished === true);
}

// ---- U01 B3 笔友手记（寄信随带 notebook、回执 NotebookEdits；R-NOTEBOOK-03/04）----

/** 寄信时带的一条手记（线格式 NotebookItem）。date = updatedAt ?? notedAt（ISO 串） */
export class NotebookItem {
  readonly id: string;
  readonly kind: string;
  readonly text: string;
  readonly dateMs: number;

  constructor(id: string, kind: string, text: string, dateMs: number) {
    this.id = id;
    this.kind = kind;
    this.text = text;
    this.dateMs = dateMs;
  }
}

/** 回执里「这条大事改写成什么」（只认最近 30 条大事的 id） */
export class NotebookRewrite {
  readonly id: string;
  readonly text: string;

  constructor(id: string, text: string) {
    this.id = id;
    this.text = text;
  }
}

/** 回执里这本手记怎么改（R-NOTEBOOK-04）。字段全可选 = 不改；
 *  profile 为 undefined = 画像不动；apply 的顺序 remove → update → add 由模型层保证 */
export class NotebookEdits {
  /** 画像改写后的整份文本；undefined = 不动 */
  readonly profile?: string;
  readonly add: string[];
  readonly update: NotebookRewrite[];
  readonly remove: string[];

  constructor(profile: string | undefined, add: string[], update: NotebookRewrite[],
    remove: string[]) {
    this.profile = profile;
    this.add = add;
    this.update = update;
    this.remove = remove;
  }

  isEmpty(): boolean {
    return this.profile === undefined && this.add.length === 0 &&
      this.update.length === 0 && this.remove.length === 0;
  }
}

interface NotebookRewriteRaw {
  id?: string;
  text?: string;
}

interface NotebookEditsRaw {
  profile?: string;
  add?: string[];
  update?: NotebookRewriteRaw[];
  remove?: string[];
}

/**
 * 回执 notebook → NotebookEdits。容错从宽（iOS compactMap 同款）：
 * profile 空串 → undefined；update / remove 里 id 非 UUID 的丢掉；
 * 字段缺 / 类型不对当空改法。响应里没有 notebook 字段 → null（老回执）。
 */
export function parseNotebookEdits(raw: NotebookEditsRaw | undefined): NotebookEdits | null {
  if (raw === null || typeof raw !== 'object') {
    return null;
  }
  let profile: string | undefined = undefined;
  if (typeof raw.profile === 'string' && raw.profile.length > 0) {
    profile = raw.profile;
  }
  const add: string[] = [];
  if (Array.isArray(raw.add)) {
    for (const text of raw.add) {
      if (typeof text === 'string' && text.length > 0) {
        add.push(text);
      }
    }
  }
  const update: NotebookRewrite[] = [];
  if (Array.isArray(raw.update)) {
    for (const item of raw.update) {
      if (item === null || typeof item !== 'object') {
        continue;
      }
      if (typeof item.id === 'string' && isUuidString(item.id) && typeof item.text === 'string') {
        update.push(new NotebookRewrite(item.id, item.text));
      }
    }
  }
  const remove: string[] = [];
  if (Array.isArray(raw.remove)) {
    for (const id of raw.remove) {
      if (typeof id === 'string' && isUuidString(id)) {
        remove.push(id);
      }
    }
  }
  return new NotebookEdits(profile, add, update, remove);
}

/** NotebookItem[] → 请求体里的 notebook 数组（date 毫秒 → ISO8601） */
function notebookBody(items: NotebookItem[]): Record<string, Object>[] {
  const out: Record<string, Object>[] = [];
  for (const n of items) {
    out.push({
      'id': n.id,
      'kind': n.kind,
      'text': n.text,
      'date': new Date(n.dateMs).toISOString()
    });
  }
  return out;
}

// ---- 5.3 寄信 / 补领（02_BACKEND_API.md POST /letter、GET /letters）----

/** POST /letter 请求里的一篇日记（02 LetterRequest.entries 元素）。
 *  只有用户勾上的那几篇进来（R-POST-04）；textContent = 已去掉划掉字的 content，
 *  照片 / 录音 / 地点 / 天气一律不发；**不发 userName**（昵称服务端从库里取） */
export class LetterRequestEntry {
  readonly title: string;
  readonly textContent: string;
  /** 日记属于哪一天（毫秒），序列化成 ISO 串 */
  readonly dateMs: number;
  /** 心情 key；'' = 没记心情（序列化时省略） */
  readonly mood: string;

  constructor(title: string, textContent: string, dateMs: number, mood: string) {
    this.title = title;
    this.textContent = textContent;
    this.dateMs = dateMs;
    this.mood = mood;
  }
}

/** POST /letter 请求（R-OUTBOX-10：entries 由调用方按 date 倒序排好；triggerKind 一律 weekly） */
export class LetterRequest {
  readonly entries: LetterRequestEntry[];
  readonly triggerKind: string;
  /** 这几篇里出现最多的 mood；'' = 都没记心情，不发（U03 版 R-OUTBOX-10） */
  readonly dominantMood: string;
  /** 投信那一刻的笔友名 */
  readonly penPalName: string;
  /** 回信语言跟日记写的语言走（R-LETTERLANG）：LetterOutboxService 用 LetterLanguage 识别填入，认不出退 App 语言 */
  readonly language: string;
  /** = Letter.id（大写 UUID）。**同一个 id 服务端只写一封、只扣一次票**（重发不重复扣；
   *  U01 2026-10-27 起 POST /letter 可带；'' = 不发（老后端兼容）） */
  readonly clientLetterId: string;
  /** 这位笔友的手记随信带上（R-NOTEBOOK-03）：画像在前大事在后；
   *  **没有手记也要带空数组**（不带字段 = 老客户端，服务端就不改手记） */
  readonly notebook: NotebookItem[];

  constructor(entries: LetterRequestEntry[], triggerKind: string, dominantMood: string,
    penPalName: string, language: string, clientLetterId: string, notebook: NotebookItem[]) {
    this.entries = entries;
    this.triggerKind = triggerKind;
    this.dominantMood = dominantMood;
    this.penPalName = penPalName;
    this.language = language;
    this.clientLetterId = clientLetterId;
    this.notebook = notebook;
  }
}

/** POST /letter 成功响应（回信草稿）。id / generatedAt 本端落库用不上，不收。
 *  notebook = 回执里手记的改法（R-NOTEBOOK-04）；null = 回执没带（老回执） */
export class LetterResponse {
  readonly body: string;
  readonly fromCharacter: string;
  readonly notebook: NotebookEdits | null;

  constructor(body: string, fromCharacter: string, notebook: NotebookEdits | null) {
    this.body = body;
    this.fromCharacter = fromCharacter;
    this.notebook = notebook;
  }
}

/** GET /letters 的一条（补领用；generatedAt 归一成毫秒，±5 分钟匹配用）。
 *  U01 起每封多 clientLetterId / penPalId / translation / danger（老信为 null / false）：
 *  - clientLetterId 等于本机某封「写信中」的信的 id 就是它的回信（补领先按它对上）
 *  - penPalId '' = 自己起名的那位
 *  - translation '' = 没有译文；danger 只对世界笔友的信有意义 */
export class LetterSummaryDTO {
  readonly body: string;
  readonly fromCharacter: string;
  readonly generatedAtMs: number;
  readonly clientLetterId: string;
  readonly penPalId: string;
  readonly translation: string;
  readonly danger: boolean;

  constructor(body: string, fromCharacter: string, generatedAtMs: number,
    clientLetterId: string, penPalId: string, translation: string, danger: boolean) {
    this.body = body;
    this.fromCharacter = fromCharacter;
    this.generatedAtMs = generatedAtMs;
    this.clientLetterId = clientLetterId;
    this.penPalId = penPalId;
    this.translation = translation;
    this.danger = danger;
  }
}

interface LetterResponseRaw {
  body?: string;
  fromCharacter?: string;
  notebook?: NotebookEditsRaw;
}

interface LetterSummaryRaw {
  body?: string;
  fromCharacter?: string;
  generatedAt?: string;
  clientLetterId?: string;
  penPalId?: string;
  translation?: string;
  danger?: boolean;
}

interface LetterListResponseRaw {
  letters?: LetterSummaryRaw[];
}

export function parseLetterResponse(raw: string): LetterResponse {
  const r = requireObject<LetterResponseRaw>(raw);
  return new LetterResponse(requireString(r.body, 'letter.body'),
    requireString(r.fromCharacter, 'letter.fromCharacter'), parseNotebookEdits(r.notebook));
}

export function parseLetterListResponse(raw: string): LetterSummaryDTO[] {
  const r = requireObject<LetterListResponseRaw>(raw);
  if (!Array.isArray(r.letters)) {
    throw new Error('letters missing or not an array');
  }
  const out: LetterSummaryDTO[] = [];
  for (const item of r.letters) {
    if (item === null || typeof item !== 'object') {
      throw new Error('letters item is not an object');
    }
    const generatedAt = ApiDates.parse(requireString(item.generatedAt, 'letters.generatedAt'));
    if (generatedAt === null) {
      throw new Error('letters.generatedAt is not ISO8601');
    }
    out.push(new LetterSummaryDTO(requireString(item.body, 'letters.body'),
      requireString(item.fromCharacter, 'letters.fromCharacter'), generatedAt.getTime(),
      optionalString(item.clientLetterId), optionalString(item.penPalId),
      optionalString(item.translation), item.danger === true));
  }
  return out;
}

/**
 * LetterRequest → POST /letter 请求体（纯序列化，单测覆盖）：
 * mood / dominantMood / language / clientLetterId 为空串时省略不发；
 * date 毫秒 → ISO8601（服务端 toISOString 同款）。
 */
export function letterRequestBody(request: LetterRequest): Record<string, Object> {
  const entries: Record<string, Object>[] = [];
  for (const e of request.entries) {
    const item: Record<string, Object> = {
      'title': e.title,
      'textContent': e.textContent,
      'date': new Date(e.dateMs).toISOString()
    };
    if (e.mood.length > 0) {
      item['mood'] = e.mood;
    }
    entries.push(item);
  }
  const body: Record<string, Object> = {
    'entries': entries,
    'triggerKind': request.triggerKind,
    'penPalName': request.penPalName
  };
  if (request.dominantMood.length > 0) {
    body['dominantMood'] = request.dominantMood;
  }
  if (request.language.length > 0) {
    body['language'] = request.language;
  }
  if (request.clientLetterId.length > 0) {
    body['clientLetterId'] = request.clientLetterId;
  }
  // R-NOTEBOOK-03：没有手记也带空数组（不带 = 老客户端，服务端不改手记）
  body['notebook'] = notebookBody(request.notebook);
  return body;
}

/** 校验 {ok:true} 轻响应（PATCH /me；非 ok 折 Decoding 档，防 200 空/坏体静默通过） */
export function parseOkResponse(raw: string): void {
  const r = requireObject<OkResponseRaw>(raw);
  if (r.ok !== true) {
    throw new Error('ok missing');
  }
}

// ---- U01 世界笔友（GET /penpals、POST /penpal-letter）----

interface AvailablePenPalsRaw {
  available?: string[];
}

/** GET /penpals → 现在能寄的世界笔友 id 列表（服务端已经备好人设） */
export function parsePenPalsResponse(raw: string): string[] {
  const r = requireObject<AvailablePenPalsRaw>(raw);
  if (!Array.isArray(r.available)) {
    throw new Error('penpals.available missing or not an array');
  }
  const out: string[] = [];
  for (const id of r.available) {
    if (typeof id === 'string' && id.length > 0) {
      out.push(id);
    }
  }
  return out;
}

/**
 * POST /penpal-letter 请求（iOS PenPalLetterRequestDTO 对齐）：
 * - entries 与 POST /letter 同款（勾上的日记，date 毫秒 → ISO8601，mood 空省略）
 * - readerLanguage：译文语言跟日记写的语言走（R-LETTERLANG；认不出退 App 语言）
 * - notebook：这位笔友的手记随信带上（B3 接真手记；没有也带空数组）
 * - clientLetterId：同一个 id 再请求服务端原样返回、不再写、不再扣票（重发安全）
 */
export class PenPalLetterRequest {
  readonly clientLetterId: string;
  readonly penPalId: string;
  readonly entries: LetterRequestEntry[];
  readonly dominantMood: string;
  readonly readerLanguage: string;
  readonly notebook: NotebookItem[];

  constructor(clientLetterId: string, penPalId: string, entries: LetterRequestEntry[],
    dominantMood: string, readerLanguage: string, notebook: NotebookItem[]) {
    this.clientLetterId = clientLetterId;
    this.penPalId = penPalId;
    this.entries = entries;
    this.dominantMood = dominantMood;
    this.readerLanguage = readerLanguage;
    this.notebook = notebook;
  }
}

interface PenPalLetterResponseRaw {
  letter?: string;
  translation?: string;
  danger?: boolean;
  postage?: number;
  generatedAt?: string;
  balance?: number;
  notebook?: NotebookEditsRaw;
}

/** POST /penpal-letter 成功响应（世界笔友的回信草稿）。
 *  notebook = 回执里手记的改法（R-NOTEBOOK-04）；null = 回执没带（老回执）。
 *  remember 只给老客户端兜底，鸿蒙不读 */
export class PenPalLetterResponse {
  /** 笔友母语写的原文（进 letter.body） */
  readonly letter: string;
  /** 译文（进 letter.translatedBody） */
  readonly translation: string;
  /** 危险的那封：读信页正面放译文 */
  readonly danger: boolean;
  /** 实际扣的邮资 */
  readonly postage: number;
  readonly generatedAtMs: number;
  /** 寄完的邮票余额（刷新邮票夹用；老后端可能没有） */
  readonly balance: number;
  readonly notebook: NotebookEdits | null;

  constructor(letter: string, translation: string, danger: boolean, postage: number,
    generatedAtMs: number, balance: number, notebook: NotebookEdits | null) {
    this.letter = letter;
    this.translation = translation;
    this.danger = danger;
    this.postage = postage;
    this.generatedAtMs = generatedAtMs;
    this.balance = balance;
    this.notebook = notebook;
  }
}

/** PenPalLetterRequest → POST /penpal-letter 请求体（纯序列化，单测覆盖）：
 *  dominantMood 空串省略；notebook 恒带（没有手记带空数组，R-NOTEBOOK-03）；
 *  date 毫秒 → ISO8601 */
export function penPalLetterRequestBody(request: PenPalLetterRequest): Record<string, Object> {
  const entries: Record<string, Object>[] = [];
  for (const e of request.entries) {
    const item: Record<string, Object> = {
      'title': e.title,
      'textContent': e.textContent,
      'date': new Date(e.dateMs).toISOString()
    };
    if (e.mood.length > 0) {
      item['mood'] = e.mood;
    }
    entries.push(item);
  }
  const body: Record<string, Object> = {
    'clientLetterId': request.clientLetterId,
    'penPalId': request.penPalId,
    'entries': entries,
    'readerLanguage': request.readerLanguage,
    'notebook': notebookBody(request.notebook)
  };
  if (request.dominantMood.length > 0) {
    body['dominantMood'] = request.dominantMood;
  }
  return body;
}

export function parsePenPalLetterResponse(raw: string): PenPalLetterResponse {
  const r = requireObject<PenPalLetterResponseRaw>(raw);
  const generatedAt = ApiDates.parse(requireString(r.generatedAt, 'penpalLetter.generatedAt'));
  if (generatedAt === null) {
    throw new Error('penpalLetter.generatedAt is not ISO8601');
  }
  if (typeof r.postage !== 'number') {
    throw new Error('penpalLetter.postage missing');
  }
  if (typeof r.balance !== 'number') {
    throw new Error('penpalLetter.balance missing');
  }
  return new PenPalLetterResponse(requireString(r.letter, 'penpalLetter.letter'),
    requireString(r.translation, 'penpalLetter.translation'), r.danger === true,
    r.postage, generatedAt.getTime(), r.balance, parseNotebookEdits(r.notebook));
}
