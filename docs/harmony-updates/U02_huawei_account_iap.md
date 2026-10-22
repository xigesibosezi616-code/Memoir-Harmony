# U02 · 华为账号与华为支付

> 基于：**v1 + U01**（和 U01 一起交付，按顺序在 U01 之后做；内容本身不依赖世界笔友）｜ 状态：**草稿**
> 后端已写好、测试全过（2026-10-16），**还没部署**；AppGallery Connect 里的应用、商品、密钥由尺素这边建（清单在尺素仓库 `Backend/docs/HUAWEI_SETUP.md`），建好后把 **Client ID** 发给鸿蒙团队。
> 本更新包**自成一体**：鸿蒙团队只看这份 + v1 即可实现，不需要读后端代码。

---

## 一句话

v1 里卡住鸿蒙的三条后端待决 —— **Q1 华为账号登录、Q2 华为支付验证、Q17 注销时撤销华为授权** —— 后端都补上了。
鸿蒙照下面的接口接：华为账号登录、绑定、用华为账号验证注销；用华为应用内支付（IAP Kit）开尺素会员。

## 改了什么、为什么

| # | 改动 | 取代 v1 |
|---|---|---|
| 1 | 新增 `POST /auth/huawei`、`POST /me/bindings/huawei`：客户端交 Account Kit 的 **ID Token**，服务端用华为公钥验签，按 **UnionID** 找账号 | `02_BACKEND_API.md` 的 `/auth/huawei`、`/me/bindings/huawei`（原「⛔ 未实现」）；`09` 的 Q1 |
| 2 | 用 **UnionID**、不用 OpenID：OpenID 按应用区分，换了包名 / 新建应用老用户就认不出来；UnionID 在同一开发者账号的所有应用里都一样 | — |
| 3 | 华为账号登录和 Apple 登录同一个待遇：登录后照样**必须绑手机号**（R-ACCOUNT-03 不变）；只做**普通华为账号登录**，不做「一键登录」（不拿手机号，不用向华为申请权限） | — |
| 4 | `POST /me/delete` 可以用**华为账号**验证本人，同时带上授权码，服务端撤销华为账号授权；撤销失败不阻断注销 | R-ACCOUNT-07；`09` 的 Q17 |
| 5 | `POST /subscription/sync-huawei` 从「只落库、不验证」的占位改成**真实验证**，**请求体换了**（交 `jwsSubscriptionStatus`） | `02_BACKEND_API.md` 的 `/subscription/sync-huawei`（占位）；`10` 手册 7.1 卡；`09` 的 Q2 |
| 6 | 🔴 华为要求**每一期订阅都「确认发货」**，否则下一期自动续费扣不了款。服务端能确认就替你确认（响应 `finished: true`）；`finished: false` 时客户端必须自己调 `iap.finishPurchase` | — |
| 7 | 续费、到期、退款时华为直接通知我们的服务端（关键事件通知 v3）。**鸿蒙不用做任何事**，只要按 R-MEMBER-10 在启动 / 回前台时同步 | — |

数据模型：**本地不新增字段**。备份包：**不变**。

---

## 规则（新增 / 取代）

**取代 R-ACCOUNT-01**：登录方式有两种 ——
① 手机号 + 6 位验证码（未注册自动建号；重发倒计时按服务端 `retryAfter`）；
② **华为账号**（Account Kit 的 `LoginWithHuaweiIDButton`，按华为的按钮规范放在手机号登录下面）。
华为账号登录成功后，账号没绑手机号的，照 R-ACCOUNT-03 显示红色警告并引导绑定。
后端返回 503 `huawei_disabled` 时提示「华为账号登录暂未开放，请先用手机号登录」，手机号登录不受影响。

**R-ACCOUNT-09（新增）华为账号登录**：
- 用 `LoginWithHuaweiIDButton`（`loginType: ID`）或 `authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest()`（`forceLogin = true`），拿到凭据里的 `idToken`，交给 `POST /auth/huawei`
- **不要**把凭据里的 `unionID` / `openID` 直接交给服务端当身份（客户端给的标识服务端不认，只认验过签的 ID Token）
- 用户取消 / 华为账号未登录（错误码 1001502001）：静默回到登录页，不弹错
- 其他失败：提示「华为账号授权失败」，日志打出完整的错误码和信息

**R-ACCOUNT-10（新增）绑定华为账号**：账户页「华为账号」一行 —— 没绑：「绑定华为账号」+ 小字「绑定后可在此设备用华为账号快捷登录同一账号」；
点了走同样的华为账号授权，`idToken` 交 `POST /me/bindings/huawei`。已绑：显示「已绑定」，**v1 不做解绑**（和 iOS 的 Apple ID 一样）。
409（这个华为账号已绑定其他账号 / 当前账号已绑定华为账号）把服务端的 `error.message` 原样显示。

**取代 R-ACCOUNT-07**：注销：设置 → 账户 → 最下面红色「注销账号」（与退出登录分组）→ ① 说明页（会删除 / 不会删除 / 无法恢复）→
② 验证本人：绑了手机号的收验证码；**绑了华为账号的另外显示「或者用华为账号验证」**（只绑了华为账号、没绑手机号的显示「用你绑定的华为账号验证」）→
③ 二次确认「此操作无法撤销」→ 成功后清登录态、回设置首页。**错误提示写在注销页上**，不用全局提示条。
用华为账号验证时，把这次授权拿到的 `idToken` 和 `authorizationCode` **一起**交给 `POST /me/delete`（授权码 5 分钟内有效、只能用一次，拿到就用，取消注销时丢掉）。

**R-MEMBER-09（新增）华为支付：买会员**：
1. 付费页打开时 `iap.queryEnvironmentStatus` → 不可用（如没登录华为账号、地区不支持）就显示「暂时无法连接」并禁用购买（R-MEMBER-04：**不显示写死的价格**）
2. `iap.queryProducts`（`productType: AUTORENEWABLE`，商品 ID 见下）拿价格和推介促销（首年 ¥58）
3. 购买：`iap.createPurchase({ productId, productType: AUTORENEWABLE })` → 结果的 `purchaseData`（JSON 字符串）里取 `jwsSubscriptionStatus`
4. **先在本机给权益**（解码 `jwsSubscriptionStatus`，`lastSubscriptionStatus.status == '1'` 即生效 —— 界面锁按本机判，R-MEMBER-08 不变）
5. 已登录尺素账号：把 `jwsSubscriptionStatus` 交 `POST /subscription/sync-huawei`
6. **确认发货**：同步响应 `finished == false`、没登录、或同步失败时，客户端自己调 `iap.finishPurchase({ productType: AUTORENEWABLE, purchaseToken, purchaseOrderId })`
   （两个值取自解码后的 `lastSubscriptionStatus.lastPurchaseOrder`）。华为报「已确认」当成功
7. 用户取消支付：静默；其余失败按 IAP Kit 错误码提示，日志打完整错误

**R-MEMBER-10（新增）华为支付：什么时候同步**：App 启动、回到前台、登录成功后、点「恢复购买」时：
`iap.queryPurchases({ productType: AUTORENEWABLE, queryType: CURRENT_ENTITLEMENT })` → 每条 `purchaseData` 照 R-MEMBER-09 的第 4–6 步处理（本机权益 → 同步 → 必要时 `finishPurchase`）。
恢复购买一条都没有时提示「这个华为账号下没有找到尺素会员」。
⚠️ **自动续费的每一期都要确认发货**：服务端收到华为的续费通知会替你确认，但这条兜底不能省（服务端没配密钥、或用户买完没登录时就靠它）。

**R-MEMBER-11（新增）付费页与状态页的华为版文案**：续费说明紧贴购买按钮下方（R-MEMBER-04），用下面「新文案」里华为版的三句（把 iOS 的「系统设置的 Apple 账户 → 订阅」换成「华为账号的订阅管理」）；
会员状态页「管理订阅」按钮调 `iap.showManagedSubscriptions`（打开系统的订阅管理页）。

**会员商品 ID**（和 iOS 一样；以 AGC 实际建的为准，尺素这边建好后会确认）：
`com.sinaratech.memoir.plus.yearly`（年付 ¥88，首年 ¥58，默认选中、排第一）、`com.sinaratech.memoir.plus.monthly`（月付 ¥12）。无试用、无家人共享。

---

## 后端接口变化（对照 v1 的 `02_BACKEND_API.md`）

接口根地址、鉴权方式、统一错误格式都不变。新增的错误码：

| code | HTTP | 什么时候 | 客户端怎么办 |
|---|---|---|---|
| `huawei_verify_failed` | 401 | ID Token 验不过（过期、不是这个应用的、被篡改） | 提示「华为账号授权失败」，让用户重试 |
| `huawei_disabled` | 503 | 服务端还没配华为（AGC 还没建好） | 登录页提示「华为账号登录暂未开放，请先用手机号登录」；付费页显示「暂时无法连接」 |

### `POST /auth/huawei`（取代「⛔ 未实现」）

```jsonc
// 请求（不鉴权）
{ "idToken": "eyJraWQi...", "displayName": "小满" }   // displayName 可省
// → 200（AuthResponse，和 /auth/verify-code 一样）
{ "token": "…", "user": { "id": 1, "phone": "13800138000", "displayName": "小满", "penPalName": "青鸟",
                           "bindings": [ { "provider": "phone" }, { "provider": "huawei" } ] } }
```

- 这个华为账号绑过 → 登录到那个账号；没绑过 → 新建账号并绑上。和 `/auth/apple` 完全同构
- `user.phone` 为空 = 还没绑手机号 → R-ACCOUNT-03
- 缺 `idToken` → 400；验不过 → 401 `huawei_verify_failed`；服务端没配 → 503 `huawei_disabled`

### `POST /me/bindings/huawei`（取代「⛔ 未实现」）

```jsonc
{ "idToken": "eyJraWQi..." }
// → 200
{ "ok": true }
```

409：「该华为账号已绑定其他账号」/「当前账号已绑定华为账号」。已经绑的就是自己 → 200（幂等）。

另：已登录的华为账号（空账号）去绑一个**已经属于别的账号**的手机号时，`POST /me/bindings/phone` 照 v1 返回 `switchedAccount: true`，
华为账号的绑定会被转移到那个账号上（v1 R-ACCOUNT-04 的处理不变）。

### `POST /me/delete`（新增两个可选字段）

```jsonc
// 三选一证明是本人：
{ "code": "123456" }                                                    // 手机号验证码（v1 原有）
{ "huaweiIdToken": "eyJ...", "huaweiAuthorizationCode": "DQB6e3..." }   // 🆕 重新走一次华为账号授权
// → 200
{ "ok": true, "appleRevoked": false, "huaweiRevoked": true }            // 🆕 huaweiRevoked
```

- `huaweiIdToken` 必须是账号绑定的那个华为账号，否则 403，一条数据都不删
- `huaweiRevoked: false` = 用验证码验证的 / 服务端没配 / 华为接口失败 —— **账号照样已删**，客户端不用区别对待

### `POST /subscription/sync-huawei`（取代 v1 的「⚠️ 占位」，**请求体换了**）

```jsonc
// 请求（需登录）
{ "jwsSubscriptionStatus": "eyJhbGciOiJFUzI1NiIs..." }   // createPurchase / queryPurchases 返回的 purchaseData 里那一项，原样交
// → 200
{
  "ok": true,
  "subscription": { "isActive": true, "productId": "com.sinaratech.memoir.plus.yearly",
                    "platform": "harmony", "expiresAt": "2027-10-16T08:00:00.000Z" },
  "finished": true      // false → 客户端自己调 iap.finishPurchase（R-MEMBER-09 第 6 步）
}
```

- 服务端验华为签名（证书链到 Huawei CBG Root CA G2）、只认尺素这个应用的订阅、只认会员商品；再向华为查一次最新状态，以查到的为准
- 400 `subscription_invalid`：凭证不对 / 不是会员商品 —— 不重试，提示购买没成功验证、联系客服
- 503：华为那边暂时查不到 / 服务端没配 —— **下次启动或回前台时再交**，本机权益照常
- 订阅归**最后一次同步它的尺素账号**（同一个华为账号换了尺素账号再恢复购买，会员跟着走，和 iOS 一样）
- 会员状态读取仍然一律走 `GET /me` 的 `subscription`（`platform` 会是 `harmony`）

### `POST /huawei/iap/notifications`（服务端对服务端，**鸿蒙不调**）

华为的关键事件通知（v3）推到这里：续费、到期、退款、撤销。服务端据此更新会员状态、替续费的那一期确认发货。鸿蒙这边不用做任何事。

---

## 七种语言的新文案

iOS 没有这些句子（iOS 是 Apple 版），**直接用下面的译文，不要机翻**。英文、日文、韩文、法文、西文里华为账号统一写 **HUAWEI ID**（华为官方写法）。

| 中文（简） | 繁中 | English | 日本語 | 한국어 | Français | Español |
|---|---|---|---|---|---|---|
| 华为账号 | 華為帳號 | HUAWEI ID | HUAWEI ID | HUAWEI ID | HUAWEI ID | HUAWEI ID |
| 绑定华为账号 | 綁定華為帳號 | Link HUAWEI ID | HUAWEI IDを連携 | HUAWEI ID 연결 | Associer le HUAWEI ID | Vincular HUAWEI ID |
| 绑定后可在此设备用华为账号快捷登录同一账号 | 綁定後可在此裝置用華為帳號快速登入同一帳號 | Once linked, you can sign in to the same account with your HUAWEI ID on this device | 連携すると、この端末でHUAWEI IDを使って同じアカウントにサインインできます | 연결하면 이 기기에서 HUAWEI ID로 같은 계정에 간편하게 로그인할 수 있습니다 | Une fois associé, vous pourrez vous connecter au même compte avec votre HUAWEI ID sur cet appareil | Al vincularlo podrás iniciar sesión en la misma cuenta con tu HUAWEI ID en este dispositivo |
| 华为账号授权失败 | 華為帳號授權失敗 | HUAWEI ID authorization failed | HUAWEI ID の認証に失敗しました | HUAWEI ID 인증에 실패했습니다 | Échec de l'autorisation HUAWEI ID | Error en la autorización de HUAWEI ID |
| 华为账号授权失败：未获取到凭证 | 華為帳號授權失敗：未取得憑證 | HUAWEI ID authorization failed: no credential received | HUAWEI ID の認証に失敗しました：資格情報を取得できませんでした | HUAWEI ID 인증 실패: 자격 증명을 받지 못했습니다 | Échec de l'autorisation HUAWEI ID : aucun identifiant reçu | Error en la autorización de HUAWEI ID: no se recibió ninguna credencial |
| 华为账号登录暂未开放，请先用手机号登录 | 華為帳號登入暫未開放，請先用手機號登入 | Signing in with HUAWEI ID isn't available yet. Please use your phone number for now. | HUAWEI ID でのサインインはまだご利用いただけません。電話番号でサインインしてください。 | HUAWEI ID 로그인은 아직 지원되지 않아요. 우선 휴대폰 번호로 로그인해 주세요. | La connexion avec un HUAWEI ID n'est pas encore disponible. Utilisez votre numéro de téléphone pour l'instant. | Todavía no se puede iniciar sesión con HUAWEI ID. Por ahora, usa tu número de teléfono. |
| 或者用华为账号验证 | 或者用華為帳號驗證 | Or verify with HUAWEI ID | または HUAWEI ID で確認 | 또는 HUAWEI ID로 인증 | Ou vérifiez avec votre HUAWEI ID | O verifica con tu HUAWEI ID |
| 用你绑定的华为账号验证 | 用你綁定的華為帳號驗證 | Verify with your linked HUAWEI ID | 登録済みの HUAWEI ID で確認 | 연결된 HUAWEI ID로 인증 | Vérifiez avec le HUAWEI ID associé | Verifica con tu HUAWEI ID vinculado |
| 我们服务器上关于你的全部数据：尺素账号、绑定的手机号和华为账号、昵称、笔友称呼，以及来信记录。 | 我們伺服器上關於你的全部資料：尺素帳號、綁定的手機號和華為帳號、暱稱、筆友稱呼，以及來信紀錄。 | Everything about you on our servers: your Memoir account, the linked phone number and HUAWEI ID, your nickname, your pen pal's name, and your letter records. | 当社サーバー上のあなたに関するすべてのデータ：Memoir のアカウント、登録済みの電話番号と HUAWEI ID、ニックネーム、ペンフレンドの呼び名、手紙の記録。 | 저희 서버에 있는 회원님의 모든 데이터: Memoir 계정, 연결된 휴대폰 번호와 HUAWEI ID, 닉네임, 펜팔 호칭, 편지 기록. | Toutes vos données sur nos serveurs : votre compte Memoir, le numéro de téléphone et le HUAWEI ID associés, votre surnom, le nom de votre correspondant et l'historique des lettres. | Todos tus datos en nuestros servidores: tu cuenta de Memoir, el número de teléfono y el HUAWEI ID vinculados, tu apodo, el nombre de tu amigo por correspondencia y el registro de cartas. |
| 手机号是账号的唯一凭据。不绑定的话，换手机或华为账号不可用时将无法找回账号。 | 手機號是帳號的唯一憑據。不綁定的話，換手機或華為帳號無法使用時將無法找回帳號。 | Your phone number is the only way to recover this account. Without it, you'll lose access if you switch phones or your HUAWEI ID becomes unavailable. | 電話番号はアカウントを取り戻す唯一の手段です。未登録のままだと、機種変更やHUAWEI IDが使えなくなった際にアカウントを復元できません。 | 휴대폰 번호는 계정을 되찾을 수 있는 유일한 수단입니다. 연결하지 않으면 기기를 바꾸거나 HUAWEI ID를 쓸 수 없게 될 때 계정을 복구할 수 없습니다. | Votre numéro est le seul moyen de récupérer ce compte. Sans lui, vous perdrez l'accès en changeant de téléphone ou si votre HUAWEI ID devient inutilisable. | Tu número es la única forma de recuperar esta cuenta. Sin él, perderás el acceso si cambias de teléfono o tu HUAWEI ID deja de estar disponible. |
| 未绑定手机号。手机号是账号的唯一凭据，不绑定的话，换手机或华为账号不可用时将无法找回账号。 | 未綁定手機號碼。手機號碼是帳戶的唯一憑證，不綁定的話，換手機或華為帳號無法使用時將無法找回帳戶。 | No phone number linked. Your phone number is the only way to recover your account — without it, you'll lose access if you change phones or your HUAWEI ID becomes unavailable. | 電話番号が未登録です。電話番号はアカウントを取り戻す唯一の手段です。登録しないと、機種変更時や HUAWEI ID が使えなくなったときにアカウントを復旧できません。 | 전화번호가 연결되지 않았습니다. 전화번호는 계정을 복구할 수 있는 유일한 수단입니다. 연결하지 않으면 기기를 바꾸거나 HUAWEI ID를 사용할 수 없게 될 때 계정을 찾을 수 없습니다. | Aucun numéro de téléphone associé. Votre numéro est le seul moyen de récupérer votre compte : sans lui, vous perdrez l'accès en cas de changement de téléphone ou d'indisponibilité de votre HUAWEI ID. | No hay número de teléfono vinculado. Tu número es la única forma de recuperar la cuenta: sin él, perderás el acceso si cambias de teléfono o tu HUAWEI ID deja de estar disponible. |
| 每年 %@。到期前 24 小时内自动续费，可随时在华为账号的订阅管理中取消。 | 每年 %@。到期前 24 小時內自動續費，可隨時在華為帳號的訂閱管理中取消。 | %@ per year. Renews automatically within 24 hours before it ends. Cancel anytime in your HUAWEI ID subscription settings. | 年額 %@。期間終了前の 24 時間以内に自動更新されます。HUAWEI ID のサブスクリプション管理でいつでも解約できます。 | 연 %@. 만료 전 24시간 이내에 자동 갱신되며, HUAWEI ID 구독 관리에서 언제든지 해지할 수 있어요. | %@ par an. Renouvellement automatique dans les 24 heures précédant l'échéance. Résiliable à tout moment dans la gestion des abonnements de votre HUAWEI ID. | %@ al año. Se renueva automáticamente en las 24 horas previas al vencimiento. Cancela cuando quieras en la gestión de suscripciones de tu HUAWEI ID. |
| 每月 %@。到期前 24 小时内自动续费，可随时在华为账号的订阅管理中取消。 | 每月 %@。到期前 24 小時內自動續費，可隨時在華為帳號的訂閱管理中取消。 | %@ per month. Renews automatically within 24 hours before it ends. Cancel anytime in your HUAWEI ID subscription settings. | 月額 %@。期間終了前の 24 時間以内に自動更新されます。HUAWEI ID のサブスクリプション管理でいつでも解約できます。 | 월 %@. 만료 전 24시간 이내에 자동 갱신되며, HUAWEI ID 구독 관리에서 언제든지 해지할 수 있어요. | %@ par mois. Renouvellement automatique dans les 24 heures précédant l'échéance. Résiliable à tout moment dans la gestion des abonnements de votre HUAWEI ID. | %@ al mes. Se renueva automáticamente en las 24 horas previas al vencimiento. Cancela cuando quieras en la gestión de suscripciones de tu HUAWEI ID. |
| 首年 %1$@，之后每年 %2$@。到期前 24 小时内自动续费，可随时在华为账号的订阅管理中取消。 | 首年 %1$@，之後每年 %2$@。到期前 24 小時內自動續費，可隨時在華為帳號的訂閱管理中取消。 | %1$@ for the first year, then %2$@ per year. Renews automatically within 24 hours before it ends. Cancel anytime in your HUAWEI ID subscription settings. | 初年度 %1$@、以降は年額 %2$@。期間終了前の 24 時間以内に自動更新されます。HUAWEI ID のサブスクリプション管理でいつでも解約できます。 | 첫해 %1$@, 이후 연 %2$@. 만료 전 24시간 이내에 자동 갱신되며, HUAWEI ID 구독 관리에서 언제든지 해지할 수 있어요. | %1$@ la première année, puis %2$@ par an. Renouvellement automatique dans les 24 heures précédant l'échéance. Résiliable à tout moment dans la gestion des abonnements de votre HUAWEI ID. | %1$@ el primer año y después %2$@ al año. Se renueva automáticamente en las 24 horas previas al vencimiento. Cancela cuando quieras en la gestión de suscripciones de tu HUAWEI ID. |
| 这个华为账号下没有找到尺素会员 | 這個華為帳號下沒有找到尺素會員 | No Memoir Plus membership found for this HUAWEI ID. | この HUAWEI ID には Memoir Plus の購入がありません。 | 이 HUAWEI ID에서 Memoir Plus 멤버십을 찾지 못했어요. | Aucun abonnement Memoir Plus trouvé pour ce HUAWEI ID. | No se encontró ninguna membresía de Memoir Plus en este HUAWEI ID. |

iOS 里对应的 Apple 版句子（`或者用 Apple 验证`、`绑定 Apple ID`、`每年 %@。…Apple 账户 → 订阅中取消。` 等）**鸿蒙一句都不要用**。
「管理订阅」「恢复购买」等不含 Apple 字样的句子照 v1 取自 iOS 的 xcstrings。

---

## 任务卡

> 格式同 v1 手册（`10_BUILD_MANUAL.md`）。前置：v1 的 4.2（手机号登录）、4.3（账户页）做完；AGC 里的应用建好、拿到 Client ID。
> 后端没部署之前，接口会 404 或 503 —— 先把客户端写好、按 503 的分支自测，部署后再真机联调。

### U02-1 华为账号登录（取代 v1 的 4.4 卡）

- **先读**：本文件「取代 R-ACCOUNT-01」、R-ACCOUNT-09，`POST /auth/huawei`；华为文档「华为账号登录（获取 UnionID/OpenID）· Button 登录」「配置 Client ID」「配置签名和指纹」；iOS `Views/Auth/LoginView.swift`（Apple 登录按钮那一段，只看交互，不照搬）
- **要做**：`module.json5` 配 `client_id`；登录页加 `LoginWithHuaweiIDButton`；拿 `idToken` → `POST /auth/huawei` → 存 token 和 user（同 4.2）；
  未绑手机号的走 R-ACCOUNT-03；`huawei_disabled` / 用户取消 / 其他失败三种分支；把调试、发布证书的 SHA-256 指纹发给尺素，让他们加到 AGC
- **不要**：把 `unionID` / `openID` 当身份交给服务端；做「一键登录」；把 Client ID 以外的任何密钥放进客户端
- **验收**：真机华为账号登录 → 新建账号 → 强制绑手机号 → 退出 → 再用华为账号登录回到同一个账号（`user.id` 不变）；服务端 503 时提示文案正确、手机号登录照常

### U02-2 绑定华为账号

- **先读**：R-ACCOUNT-10，`POST /me/bindings/huawei`；v1 R-ACCOUNT-04
- **要做**：账户页「华为账号」一行（没绑 / 已绑两态）；绑定走华为账号授权 → `idToken` → 绑定接口；409 显示服务端文案
- **不要**：做解绑
- **验收**：手机号登录的账号绑上华为账号后，退出、用华为账号登录回到同一账号；同一个华为账号去绑第二个尺素账号 → 409 文案；
  华为账号登录的空账号绑一个已有账号的手机号 → `switchedAccount` → 切到原账号，之后用华为账号登录也进原账号

### U02-3 注销：用华为账号验证（补 v1 4.3 的注销流程）

- **先读**：「取代 R-ACCOUNT-07」，`POST /me/delete`；iOS `Views/Auth/DeleteAccountView.swift`（「或者用 Apple 验证」那一段）
- **要做**：第 ② 步按绑定情况显示验证码 / 「或者用华为账号验证」/「用你绑定的华为账号验证」；华为账号授权拿 `idToken` + `authorizationCode` 一起交；
  删除说明页里「绑定的手机号和 Apple ID」那句换成华为版（见新文案）
- **不要**：缓存授权码（取消注销时丢掉，下次重新授权）
- **验收**：用华为账号验证注销成功、本地日记一篇不少；用别的华为账号验证 → 403 文案写在注销页上、账号还在；只绑华为账号没绑手机号的账号也能注销

### U02-4 华为支付：买会员（取代 v1 的 7.1 卡；和 v1 7.2 付费页一起做）

- **先读**：R-MEMBER-09、R-MEMBER-11、v1 R-MEMBER 全部，`POST /subscription/sync-huawei`；华为文档「IAP Kit · 自动续期订阅商品购买」「确保权益发放」；iOS `Services/StoreKitManager.swift`（只看什么时候同步、怎么给本机权益）
- **要做**：`queryEnvironmentStatus` → `queryProducts` → 付费页价格与首年优惠；`createPurchase` → 解码 `jwsSubscriptionStatus` 给本机权益 → 同步 → 按 `finished` 决定要不要 `finishPurchase`；
  续费说明用华为版三句；状态页「管理订阅」调 `showManagedSubscriptions`
- **不要**：自己算会员有没有到期去锁服务端的功能（来信、邮票只认服务端，R-MEMBER-08）；在客户端验证 JWS 签名（服务端验）；把商品价格写死
- **验收**：沙盒账号买年付 → 付费页消失、相纸 / 封面解锁 → `GET /me` 的 `subscription.platform == "harmony"`；断网买 → 本机先解锁，联网后同步成功；
  沙盒里过一期续费后仍是会员（说明每期都确认了发货）

### U02-5 华为支付：启动、回前台、恢复购买时同步

- **先读**：R-MEMBER-10
- **要做**：启动 / 回前台 / 登录成功 / 「恢复购买」时 `queryPurchases(CURRENT_ENTITLEMENT)`，每条照 U02-4 处理；恢复购买为空时的提示；同步失败（503）不打扰用户，下次再交
- **不要**：在后台轮询；没登录时调同步接口
- **验收**：换一台鸿蒙设备、同一华为账号登录 → 「恢复购买」→ 会员回来；注销尺素账号后用新账号恢复 → 会员归新账号

---

## 鸿蒙已经做了的部分怎么改

截至 2026-10-16，鸿蒙仓库 4.4（Q1）、6.6（Q3）、7.1（Q2）都是 ⛔，按理还没写。如果已经按 v1 的占位接过 `sync-huawei`（交 `purchaseToken` + `productId`）：
请求体改成 `{ jwsSubscriptionStatus }`，并补上 R-MEMBER-09 第 6 步的 `finishPurchase`。`09_OPEN_QUESTIONS.md` 里 Q1、Q2、Q17 的「结论」栏填：「U02 已解决（2026-10-16）」。
