import Foundation

/// 登录相关 API 协议类型 —— 与 `Backend/shared/src/types.ts` 逐字段对齐。
/// 字段变更要同时改两边（后端 types.ts 顶部有相同注释）。

// MARK: - 请求

struct SendCodeRequest: Encodable {
    let target: String
}

struct VerifyCodeRequest: Encodable {
    let target: String
    let code: String
}

struct AppleLoginRequest: Encodable {
    let identityToken: String
    /// 仅首次注册时后端会用（Apple 只在第一次授权给全名）
    let displayName: String?
}

struct BindAppleRequest: Encodable {
    let identityToken: String
}

/// 绑定手机号（需登录态），与登录共用发码接口和防刷
struct BindPhoneRequest: Encodable {
    let target: String
    let code: String
}

/// `PATCH /me` 局部更新。**nil 的字段不会编码进 JSON**（Swift 对 Optional 用 encodeIfPresent），
/// 正好对上后端「`undefined` = 不改，空串 = 清空」的语义。
struct PatchMeRequest: Encodable {
    var penPalName: String?
    var displayName: String?
}

/// `POST /me/delete` 注销账号。**二选一带身份证明**：`code`（当前绑定手机号的验证码），
/// 或 `appleIdentityToken`（重新走一次 Apple 登录，必须是账号绑定的那个 Apple ID）。
/// 用 Apple 时同时带上 `appleAuthorizationCode`，服务端拿它吊销 Apple 授权。
/// nil 的字段不编码进 JSON。
struct DeleteAccountRequest: Encodable {
    var code: String?
    var appleIdentityToken: String?
    var appleAuthorizationCode: String?
}

/// `POST /subscription/sync-apple`：把 StoreKit 2 的签名交易交给服务器验证（尺素会员）
struct SyncAppleSubscriptionRequest: Encodable {
    let signedTransaction: String
}

// MARK: - 响应

struct SyncAppleSubscriptionResponse: Decodable {
    let ok: Bool
    let subscription: SubscriptionStatusDTO
}

/// 注销结果。`appleRevoked` 只用来记日志：没绑 Apple / 服务端没配私钥 / Apple 接口失败时为 false，账号照样已删
struct DeleteAccountResponse: Decodable {
    let ok: Bool
    let appleRevoked: Bool
}

struct SendCodeResponse: Decodable {
    let ok: Bool
    /// 客户端重发倒计时秒数
    let retryAfter: Int
}

/// 绑定类接口的通用成功响应 `{ "ok": true }`
struct OKResponse: Decodable {
    let ok: Bool
}

/// 换绑手机号：旧号证明「是本人」，新号证明「号是你的」，缺一不可。
struct ChangePhoneRequest: Encodable {
    let oldCode: String
    let newTarget: String
    let newCode: String
}

/// 绑定手机号的响应。
///
/// 🔴 **`switchedAccount == true` 时必须用返回的 `token` 换掉本地那个**。
///
/// 那意味着：用户此前用这个手机号注册过账号，而这次是先用 Apple 登录
/// （建了个新空账号）再来绑号的。服务端已把新账号的 Apple 绑定转移到原账号、
/// 删掉了那个空壳 —— 本地旧 token 指向的身份**已经不存在了**，继续用会 401。
struct BindPhoneResponse: Decodable {
    let ok: Bool
    let switchedAccount: Bool
    let token: String?
    let user: UserDTO
}

struct AuthResponse: Decodable {
    let token: String
    let user: UserDTO
}

struct UserDTO: Codable, Equatable, Sendable {
    struct AuthBinding: Codable, Equatable, Sendable {
        /// phone | apple | huawei | wechat | email | google
        let provider: String
    }

    let id: APIID
    let phone: String?
    let email: String?
    /// 用户昵称。`var` 是为了改完昵称能就地更新本地快照，不必为一个字段再跑一趟 `GET /me`
    var displayName: String?
    let penPalName: String
    let bindings: [AuthBinding]

    /// 设置页展示用：138****1234
    var maskedPhone: String? {
        guard let phone, phone.count == 11 else { return phone }
        return phone.prefix(3) + "****" + phone.suffix(4)
    }
}

struct SubscriptionStatusDTO: Codable, Equatable, Sendable {
    let isActive: Bool
    let productId: String?
    let platform: String?
    let expiresAt: String?
}

struct MeResponse: Decodable {
    let user: UserDTO
    let subscription: SubscriptionStatusDTO
}

// MARK: - 错误

/// 后端统一错误格式 `{ "error": { "code", "message" }, "retryAfter"?, "reason"? }`
struct APIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
    }
    let error: Payload
    /// rate_limited 时后端附带的重试秒数
    let retryAfter: Int?
    /// 被拦下的原因：`no_stamps`（邮票用完了，2026-10-16 起）、`member_required`、`unknown_pen_pal`；
    /// 老服务端还会给 `weekly_pending` / `daily_cap` / `monthly_cap` / `welcome_pending`。
    ///
    /// **文案由客户端按 reason 自己渲染，不直接显示后端那句** ——
    /// 后端的 `rhythmMessage` 只有中文，直接透传会让日/英/韩/法/西用户看到中文。
    let reason: String?
    /// `no_stamps` 时：下一包什么时候到
    let nextPackAt: Date?
}

// MARK: - 工具类型

/// 后端 user.id 是 `number | string`（MySQL 数字 / 未来可能字符串），客户端统一收成 String。
struct APIID: Codable, Equatable, Sendable {
    let raw: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int64.self) {
            raw = String(i)
        } else {
            raw = try c.decode(String.self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

/// `POST /me/bindings/phone/change` 的响应（只回更新后的用户档案）
struct MeUserResponse: Decodable {
    let user: UserDTO
}
