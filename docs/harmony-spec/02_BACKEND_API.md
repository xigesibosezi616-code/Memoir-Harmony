# 02 · 后端 API 契约

> 鸿蒙端跟 iOS 端**共用同一后端**。权威永远是代码：`Backend/shared/src/types.ts`（类型）+ `handlers/`（路由）+ `rhythm.ts`（来信节奏）。
> 本文与代码不一致时**以代码为准**，并请回头修本文。
>
> **最后核对：2026-10-12**（逐个路由对着 `handlers/*.ts` 过了一遍；修正了 token 有效期、换绑同号、429 响应体、区域判定等旧描述）

---

## 后端在哪

- **只接大陆后端**（2026-07-29 起大陆版单线，海外版推迟）。**不做区域判定**
- 基础地址写成**一个常量**。当前 iOS 用的是阿里云函数计算系统域名：
  `https://memoir-api-cn-ecdrwvhwac.cn-hangzhou.fcapp.run`
  备案域名 `https://api.sinaratech.com.cn` 上线后切换（`09_OPEN_QUESTIONS.md` Q15）
- 技术栈：Hono + TypeScript，跑在阿里云 FC；MySQL（RDS）；DeepSeek 写信；阿里云短信发验证码

## 鉴权

除 `/health`、`/auth/*`、`/apple/notifications` 外，所有接口要带：

```
Authorization: Bearer <jwt>
```

- token 在登录 / 验证码验证后返回，**有效期 90 天**（`utils/jwt.ts` 默认 `90d`）
- token 存**安全存储**（iOS 是 Keychain），不放明文偏好
- **任何接口返回 401 → 清掉本地 token 与用户快照，界面回到未登录**

## 日期

服务端返回的日期一律 `toISOString()`，**带毫秒**：`2026-09-17T10:20:30.123Z`。解析时**带不带毫秒都要认**。
（⚠️ 反过来，**备份包**里的日期不带毫秒，见 `05_DATA_MODEL.md` §0。）

---

## 接口一览

| 方法 | 路径 | 鉴权 | 用途 | 鸿蒙要不要接 |
|---|---|---|---|---|
| GET | `/health` | — | 健康检查 | 调试用 |
| POST | `/auth/send-code` | — | 发短信验证码 | ✅ |
| POST | `/auth/verify-code` | — | 验证码登录（未注册自动建号） | ✅ |
| POST | `/auth/apple` | — | Apple 登录 | ❌ iOS 专用 |
| POST | `/auth/third-party` | — | 微信登录（v1 不做） | ❌ |
| POST | `/auth/huawei` | — | 华为账号登录 | ⛔ **未实现**（Q1） |
| GET | `/me` | ✅ | 当前用户 + 订阅状态 | ✅ |
| PATCH | `/me` | ✅ | 改昵称 / 笔友名 | ✅（只改昵称） |
| GET | `/me/rhythm` | ✅ | 现在能不能寄信 | ✅ |
| POST | `/me/bindings/phone` | ✅ | 绑手机号（可能换账号） | ✅ |
| POST | `/me/bindings/phone/change` | ✅ | 换绑手机号 | ✅ |
| POST | `/me/bindings/apple` | ✅ | 绑 Apple ID | ❌ iOS 专用 |
| POST | `/me/bindings/huawei` | ✅ | 绑华为账号 | ⛔ **未实现**（Q1） |
| POST | `/me/delete` | ✅ | 注销账号 | ✅ |
| POST | `/letter` | ✅ | 寄信（服务端写回信） | ✅ |
| GET | `/letters` | ✅ | 服务端已写好的信（补领用） | ✅ |
| POST | `/letters/:id/read` | ✅ | 标记已读 | ❌ iOS 不调（已读只记本地） |
| POST | `/subscription/sync-apple` | ✅ | 交 Apple 签名交易 | ❌ iOS 专用 |
| POST | `/subscription/sync-huawei` | ✅ | 交华为购买凭据 | ⚠️ **占位，不验证**（Q2） |
| POST | `/apple/notifications` | — | App Store 服务器通知 | ❌ |

---

## 🟢 不鉴权

### `GET /health`

```jsonc
// → 200
{ "ok": true, "time": "2026-06-28T03:00:00.000Z" }
```

### `POST /auth/send-code`

```jsonc
// 请求
{ "target": "13800138000" }
// → 200
{ "ok": true, "retryAfter": 60 }          // 客户端重发倒计时秒数，以它为准
```

三层防刷（服务端）：同号 60 秒冷却 / 同号 24 小时 8 次 / 同 IP 每小时 20 次。

| 失败 | 状态 | `code` | 说明 |
|---|---|---|---|
| 号码格式不对 | 400 | `bad_request` | |
| 冷却中 | 429 | `rate_limited` | 顶层带 `retryAfter`（剩余秒数） |
| 今日上限 / IP 上限 | 429 | `rate_limited` | |
| 短信通道失败 | 502 | `verify_code_failed` | |

### `POST /auth/verify-code`

```jsonc
// 请求
{ "target": "13800138000", "code": "123456" }
// → 200（AuthResponse）
{
  "token": "eyJhbGc...",
  "user": {                         // UserDTO
    "id": 1,
    "phone": "13800138000",         // 从绑定派生
    "displayName": "Amethyst",      // 可能没有
    "penPalName": "青鸟",
    "bindings": [ { "provider": "phone" } ]
  }
}
```

验证码错：400 `verify_code_invalid`（「验证码错误」「请先获取验证码」「验证码错误次数过多，请重新获取」）；过期：400 `verify_code_expired`。

---

## 🔐 鉴权后

### `GET /me`

```jsonc
// → 200（MeResponse）
{
  "user": { /* UserDTO */ },
  "subscription": {
    "isActive": true,
    "productId": "com.sinaratech.memoir.plus.yearly",
    "platform": "ios",              // ios | harmony | google
    "expiresAt": "2027-10-09T08:00:00.000Z"
  }
}
// 没订阅：{ "subscription": { "isActive": false } }
```

### `PATCH /me`

```jsonc
{ "displayName": "Amethyst" }       // 和 / 或 "penPalName"
// → 200
{ "ok": true }
```

- 两个字段都可选，**都不传 → 400**；语义是「没传 = 不改」
- `displayName`：去首尾空白后 ≤ 64；**空串 = 清空**（存 NULL）。这就是信件抬头「致 XXX」里的昵称
- `penPalName`：1–32。⚠️ iOS **从不写它**，笔友名以客户端本地为准、寄信时随请求发（Q9）

### `GET /me/rhythm`（来信节奏，🔴 判定权只在服务端）

```jsonc
// → 200（RhythmResponse）
{
  "tier": "free",                   // free | subscribed
  "canRequestNow": false,
  "reason": "weekly_pending",       // ok | weekly_pending | daily_cap | monthly_cap | welcome_pending
  "nextLetterAt": "2026-10-13T00:00:00.000Z"   // 现在就能寄时为 null
}
```

服务端规则（`rhythm.ts`，**客户端不要自己算**）：

| | 免费 | 会员 |
|---|---|---|
| 每周 | 1 封（周一 00:00 起算，服务器时区） | 不限 |
| 每天 | — | 1 封 |
| 每月 | 最多 4 封 | 不限 |
| 判定顺序 | 月上限 → 周 | 日上限 |

客户端用它在邮筒页**提前说明**（文案按 `reason` 本地渲染，见 `06_RULES.md` R-POST-12），问不到就照常让寄。
⚠️ 测试期服务端开了 `LETTER_RHYTHM_OFF=1`，永远返回可以寄 —— 这是预期（Q14）。

### `POST /me/bindings/phone`（绑手机号）

```jsonc
// 请求（发码复用 /auth/send-code）
{ "target": "13800138000", "code": "123456" }
// → 200（BindPhoneResponse）
{ "ok": true, "switchedAccount": false, "user": { /* UserDTO */ } }
// 或：发生了账号转移
{ "ok": true, "switchedAccount": true, "token": "<原账号的新 JWT>", "user": { /* 原账号的 UserDTO */ } }
```

- 号已属于别人且当前账号**有数据** → 409 `conflict`，`message` 是现成的可展示文案
- 🔴 **`switchedAccount == true`**：用户先第三方登录建了空账号、又绑了自己老账号的手机号 → 服务端把空账号删掉、让他回到老账号。
  **必须用返回的 `token` 和 `user` 覆盖本地**（旧 token 指向的账号已删，继续用会 401），并提示「已找回你的账号」。
  「空账号」的判据是**服务端**没有来信 / 订阅 / 权益 / 昵称 —— 本地日记不算
- 🔴 **手机号是账号的必需项**：没绑时设置一级页账户卡上要有红色警告（R-ACCOUNT-03）

### `POST /me/bindings/phone/change`（换绑手机号）

```jsonc
// 旧号验证码证明「是本人」，新号验证码证明「号是你的」
{ "oldCode": "123456", "newTarget": "13900139000", "newCode": "654321" }
// → 200
{ "ok": true, "user": { /* UserDTO */ } }
```

两个验证码都用 `/auth/send-code` 发（`oldCode` 发给当前已绑的号）。

| 情况 | 结果 |
|---|---|
| 新号已属于别人 | 409 `conflict`，一个字都不写库 |
| 新号就是当前这个号 | **400**「新手机号与当前一致」（旧文档写的「幂等放过」与代码不符，以代码为准） |
| 当前账号没绑过手机号 | 400（该走绑定） |
| 旧号码不对 | 400，且**不消费**新号的码 |

### `POST /me/delete`（注销账号，🔴 上架硬性要求）

```jsonc
// 鸿蒙用验证码方式（发码复用 /auth/send-code，target 填账号绑定的号）
{ "code": "123456" }
// → 200
{ "ok": true, "appleRevoked": false }
```

- 删除**服务器上**这个用户的全部数据：账号、登录绑定、来信、订阅记录、权益。本地日记、已收到的信不受影响 —— 文案必须讲清楚
- 没带凭证 / 验证码错 → 400，**一条数据都不删**
- 成功后清本地登录态
- 接了华为账号后，注销要撤销华为授权，服务端需加分支（Q17）

### `POST /letter`（寄信：服务端写一封回信）

```jsonc
// 请求（LetterRequest）
{
  "entries": [                       // 🔴 只放用户勾上的那几篇（R-POST-04），按日期倒序
    { "title": "搬进新公寓的第一天", "textContent": "今天终于...", "date": "2026-06-04T20:00:00.000Z", "mood": "calm" }
  ],
  "triggerKind": "weekly",           // iOS 一律发 weekly
  "dominantMood": "calm",            // 这几篇里出现最多的 mood，可省
  "penPalName": "青鸟",              // 投信那一刻的笔友名
  "language": "zh-Hant"              // zh-Hans | zh-Hant | en | ja | ko | fr | es
                                     // 🔴 跟着日记写的语言（R-LETTERLANG），不是界面 / 系统语言
                                     // 老值 'zh' = 简体；不认识的按简体
}
// → 200（LetterResponse）
{
  "id": 42,
  "body": "见字如面。\n\n...\n\n   —— 青鸟",   // 署名已在正文里
  "fromCharacter": "青鸟",
  "generatedAt": "2026-06-28T03:00:00.123Z"
}
```

- `textContent` = 日记的 `content`（**已去掉划掉的字**）。照片、录音、地点、天气**一律不发**
- 不要发 `userName`：昵称由服务端从库里取
- 超频 → **429**，响应体（注意 `reason` 在**顶层**）：

```jsonc
{
  "error": { "code": "rate_limited", "message": "本周的信已经到了。青鸟习惯每周回一次——你写的它都在读，下周日再来。" },
  "reason": "weekly_pending",
  "nextLetterAt": "2026-10-13T00:00:00.000Z",
  "tier": "free"
}
```

  `message` **只有中文**，客户端按 `reason` 自己渲染七种语言。429 是正常业务分支，**先补领一次**再决定退回（R-OUTBOX-08）

- 模型失败：502 `ai_failed` / `empty_response`（服务端 75 秒先放弃，客户端超时设 90 秒）
- 🔴 **服务端是「写好 → 入库 → 返回」**：响应丢了（超时、断网、切后台）信其实已经写好、额度也扣了。所以客户端必须能**补领**（下一条接口）
- 🔴 **拿到正文不能马上给用户看**：回信在寄出后 6 小时 ~ 3 天的随机时刻才「到达」，到达时刻由客户端算好存本地（`03_USER_FLOWS.md` 流程 4）

### `GET /letters?limit=20&before=<id>`（补领）

```jsonc
// → 200
{
  "letters": [                       // LetterListItem[]，按 generatedAt 倒序
    {
      "id": 42, "body": "...", "fromCharacter": "青鸟",
      "triggerKind": "weekly", "dominantMood": "calm", "entryCount": 3,
      "status": "delivered", "generatedAt": "2026-06-28T03:00:00.123Z", "readAt": null
    }
  ]
}
```

- `limit` 默认 20、最大 100；`before` 是信的 id（翻页用）
- ⚠️ **这里会返回还在路上的信**（后端没有到达时刻这一列，Q4）。客户端只拿它**补领**：按正文去重，到达时刻按 `generatedAt` 重算（R-OUTBOX-07/09），**不要直接把列表显示给用户**

### `POST /letters/:id/read`

```jsonc
// → 200
{ "updated": true }
```

iOS **不调**这个接口，已读只记本地。鸿蒙照做。

### `POST /subscription/sync-huawei`（⚠️ 占位）

```jsonc
{ "purchaseToken": "...", "productId": "com.sinaratech.memoir.plus.yearly" }
// → 200（现在）
{ "ok": true, "warning": "MVP 占位：未真实验证华为 purchaseToken" }
```

**现在不验证**，接华为 IAP 之前后端要按 Apple 那套补（Q2）：验证凭据、只认会员产品、换 App 账号恢复归当前账号、接订阅状态通知。
订阅状态的读取一律走 `GET /me` 的 `subscription`。

---

## 统一错误响应

```jsonc
{
  "error": {
    "code": "rate_limited",
    "message": "请求过于频繁，请稍后再试",   // 中文，可直接展示（但节奏类按 reason 本地渲染）
    "detail": "..."                         // 仅开发模式
  },
  "retryAfter": 42                          // 某些错误在顶层带额外字段（retryAfter / reason / nextLetterAt / tier）
}
```

| code | 状态 | 含义 | 客户端怎么做 |
|---|---|---|---|
| `bad_request` | 400 | 参数错 | 展示 message |
| `unauthorized` | 401 | 未登录 / token 过期 | **清登录态**，回到未登录 |
| `forbidden` | 403 | 无权限 | 展示 |
| `not_found` | 404 | 不存在 | 展示 |
| `conflict` | 409 | 绑定冲突 | 展示 message（现成文案） |
| `rate_limited` | 429 | 防刷 / 来信节奏 | 验证码：按 `retryAfter` 倒计时；寄信：按 `reason` |
| `verify_code_invalid` | 400 | 验证码错 | 展示，输入框标红 |
| `verify_code_expired` | 400 | 验证码过期 | 提示重新获取 |
| `verify_code_failed` | 502 | 短信发送失败 | 展示 |
| `ai_failed` / `empty_response` | 502 | 写信失败 | **寄信队列重试**（1 分钟、5 分钟，3 次退回），不当场报错 |
| `subscription_invalid` | 400 / 503 | 订阅凭据无效 / 订阅服务未开 | 付费页上提示 |
| `apple_verify_failed` / `thirdparty_*` | — | iOS / 微信专用 | — |
| `internal` | 500 | 服务端异常 | 「服务异常，请稍后再试」；寄信场景走重试 |

> 断网 / 超时 / 连接失败**不是**服务端错误：寄信场景下不计失败次数，30 秒后接着寄（R-OUTBOX-04）。

---

## 鸿蒙端的类型（`models/Api.ets`，与 `types.ts` 逐字段对应）

```typescript
export interface EntryDTO {
  title: string
  textContent: string
  date: string            // ISO8601
  mood?: string
}

export type TriggerKind = 'welcome' | 'weekly' | 'perEntry' | 'daily' | 'monthly'
export type LetterLanguage = 'zh-Hans' | 'zh-Hant' | 'en' | 'ja' | 'ko' | 'fr' | 'es'

export interface LetterRequest {
  entries: EntryDTO[]
  triggerKind: TriggerKind
  dominantMood?: string
  penPalName: string
  language?: LetterLanguage
}

export interface LetterResponse {
  id: number | string
  body: string
  fromCharacter: string
  generatedAt: string
}

export interface LetterListItem {
  id: number | string
  body: string
  fromCharacter: string
  triggerKind: string
  dominantMood: string | null
  entryCount: number
  status: 'pending' | 'generating' | 'delivered' | 'read' | 'failed'
  generatedAt: string
  readAt: string | null
}

export interface RhythmResponse {
  tier: 'free' | 'subscribed'
  nextLetterAt: string | null
  canRequestNow: boolean
  reason: 'ok' | 'weekly_pending' | 'daily_cap' | 'monthly_cap' | 'welcome_pending'
}

export interface UserDTO {
  id: number | string
  phone?: string
  email?: string
  displayName?: string
  penPalName: string
  bindings: Array<{ provider: 'phone' | 'email' | 'apple' | 'huawei' | 'wechat' | 'google' }>
}

export interface AuthResponse { token: string; user: UserDTO }
export interface SendCodeResponse { ok: true; retryAfter: number }
export interface BindPhoneResponse { ok: true; switchedAccount: boolean; token?: string; user: UserDTO }

export interface SubscriptionStatusResponse {
  isActive: boolean
  productId?: string
  platform?: 'ios' | 'harmony' | 'google'
  expiresAt?: string
}
export interface MeResponse { user: UserDTO; subscription: SubscriptionStatusResponse }

export interface ErrorResponse {
  error: { code: string; message: string; detail?: string }
  // 顶层可能还有 retryAfter / reason / nextLetterAt / tier
}
```

**类型同步规则**：后端改了 `types.ts` → 同一天通知 iOS 与鸿蒙；鸿蒙的 `Api.ets` 跟着改，逐字段对齐。

---

## 测试

```bash
curl https://memoir-api-cn-ecdrwvhwac.cn-hangzhou.fcapp.run/health
# → { "ok": true, "time": "..." }
```

本地联调：找后端开发者临时开放局域网地址（形如 `http://<Mac 主机名>.local:8788`，**主机名必须全小写**，大写 Host 会被回 400）。
