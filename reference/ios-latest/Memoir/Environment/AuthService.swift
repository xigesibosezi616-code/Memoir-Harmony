import Foundation

/// 登录服务抽象边界。背后可切 `LiveAuthService`（真后端）/ `MockAuthService`（离线 UI 开发）。
///
/// 挂在 `AppEnvironment.auth`；登录态本身存 `AppEnvironment.session`（UserSession）。
/// 服务无状态：token 由调用方从 session 取出传入。
protocol AuthService {
    /// 发送短信验证码。返回重发倒计时秒数（驱动 UI 倒计时）。
    func sendCode(phone: String) async throws -> Int

    /// 校验验证码并登录（首次自动注册）。
    func login(phone: String, code: String) async throws -> AuthResponse

    /// 拿登录态查「我是谁」。401 时抛 `AuthError.server(code: "unauthorized", ...)`，调用方应清 session。
    func fetchMe(token: String) async throws -> MeResponse

    /// Apple 登录（首次自动注册）。identityToken 来自 ASAuthorizationAppleIDCredential。
    func loginWithApple(identityToken: String, displayName: String?) async throws -> AuthResponse

    /// 已登录账号绑定 Apple ID。冲突（已绑他人/已有绑定）抛 409 conflict，文案直接可展示。
    func bindApple(identityToken: String, token: String) async throws

    /// 已登录账号（Apple 注册的）绑定手机号。发码复用 sendCode。
    /// 绑定手机号。**返回值必须处理** —— `switchedAccount` 为 true 时要换本地 token，
    /// 详见 `BindPhoneResponse`。
    func bindPhone(phone: String, code: String, token: String) async throws -> BindPhoneResponse

    /// 改昵称。传空串 = 清空昵称（后端存 NULL）。后端限长 64 字符，超了抛 400。
    /// 换绑手机号：旧号验证码 + 新号验证码同时校验
    func changePhone(oldCode: String, newPhone: String, newCode: String, token: String) async throws -> UserDTO

    func updateDisplayName(_ name: String, token: String) async throws

    /// 注销账号：删除服务器上的账号与全部关联数据（来信、绑定、订阅记录）。**不碰本地和 iCloud 里的日记**。
    /// 身份没证明（验证码错 / Apple ID 对不上）时服务端拒绝，文案直接可展示
    func deleteAccount(_ request: DeleteAccountRequest, token: String) async throws -> DeleteAccountResponse

    /// 尺素会员：把 StoreKit 2 的签名交易交给服务器验证并记到当前账号名下。
    /// 笔友来信的额度只认服务器，所以买完、恢复、登录后、回到前台都要交一次（见 `ContentView`）
    func syncAppleSubscription(signedTransaction: String, token: String) async throws -> SubscriptionStatusDTO
}

// MARK: - 后端地址

enum BackendConfig {
    /// 阿里云 FC 系统域名（2026-07-11 部署）。备案下来后换 api.sinaratech.com.cn。
    static let cloudURL = URL(string: "https://memoir-api-cn-ecdrwvhwac.cn-hangzhou.fcapp.run")!

    #if DEBUG
    /// Debug 默认也走云端（真机 4G 可用）。
    /// 需要本地调后端时改用：
    /// - 模拟器: http://127.0.0.1:8788
    /// - 真机:   http://prozotye.local:8788（⚠️ 必须全小写，@hono/node-server 对大写 Host 回 400；
    ///           mDNS 被禁时退回 Mac 局域网 IP：`ipconfig getifaddr en0`）
    static let apiBaseURL = cloudURL
    #else
    static let apiBaseURL = cloudURL
    #endif
}

// MARK: - 错误

/// 登录链路错误。后端返回的 message 是现成的用户可读中文文案，直接透传给 ErrorPresenter。
enum AuthError: LocalizedError {
    case server(code: String, message: String, retryAfter: Int?)

    var errorDescription: String? {
        switch self {
        case .server(_, let message, _):
            return message
        }
    }
}

// MARK: - 真实现

struct LiveAuthService: AuthService {
    let baseURL: URL
    let http: HTTPClient

    /// 登录链路接口都是轻量点查，30s 默认超时对「卡住感」太久，统一收紧
    private static let timeout: TimeInterval = 15

    func sendCode(phone: String) async throws -> Int {
        var request = try HTTPRequest.postJSON(
            baseURL.appending(path: "auth/send-code"),
            body: SendCodeRequest(target: phone)
        )
        request.timeout = Self.timeout
        do {
            let resp: SendCodeResponse = try await http.send(request)
            return resp.retryAfter
        } catch {
            throw Self.mapServerError(error)
        }
    }

    func login(phone: String, code: String) async throws -> AuthResponse {
        var request = try HTTPRequest.postJSON(
            baseURL.appending(path: "auth/verify-code"),
            body: VerifyCodeRequest(target: phone, code: code)
        )
        request.timeout = Self.timeout
        do {
            return try await http.send(request)
        } catch {
            throw Self.mapServerError(error)
        }
    }

    func fetchMe(token: String) async throws -> MeResponse {
        var request = HTTPRequest.get(
            baseURL.appending(path: "me"),
            headers: ["Authorization": "Bearer \(token)"]
        )
        request.timeout = Self.timeout
        do {
            return try await http.send(request)
        } catch {
            throw Self.mapServerError(error)
        }
    }

    func loginWithApple(identityToken: String, displayName: String?) async throws -> AuthResponse {
        var request = try HTTPRequest.postJSON(
            baseURL.appending(path: "auth/apple"),
            body: AppleLoginRequest(identityToken: identityToken, displayName: displayName)
        )
        request.timeout = Self.timeout
        do {
            return try await http.send(request)
        } catch {
            throw Self.mapServerError(error)
        }
    }

    func bindApple(identityToken: String, token: String) async throws {
        var request = try HTTPRequest.postJSON(
            baseURL.appending(path: "me/bindings/apple"),
            body: BindAppleRequest(identityToken: identityToken),
            headers: ["Authorization": "Bearer \(token)"]
        )
        request.timeout = Self.timeout
        do {
            let _: OKResponse = try await http.send(request)
        } catch {
            throw Self.mapServerError(error)
        }
    }

    func bindPhone(phone: String, code: String, token: String) async throws -> BindPhoneResponse {
        var request = try HTTPRequest.postJSON(
            baseURL.appending(path: "me/bindings/phone"),
            body: BindPhoneRequest(target: phone, code: code),
            headers: ["Authorization": "Bearer \(token)"]
        )
        request.timeout = Self.timeout
        do {
            return try await http.send(request)
        } catch {
            throw Self.mapServerError(error)
        }
    }

    func changePhone(oldCode: String, newPhone: String, newCode: String, token: String) async throws -> UserDTO {
        var request = try HTTPRequest.postJSON(
            baseURL.appending(path: "me/bindings/phone/change"),
            body: ChangePhoneRequest(oldCode: oldCode, newTarget: newPhone, newCode: newCode),
            headers: ["Authorization": "Bearer \(token)"]
        )
        request.timeout = Self.timeout
        do {
            let resp: MeUserResponse = try await http.send(request)
            return resp.user
        } catch {
            throw Self.mapServerError(error)
        }
    }

    func updateDisplayName(_ name: String, token: String) async throws {
        var request = try HTTPRequest.patchJSON(
            baseURL.appending(path: "me"),
            body: PatchMeRequest(displayName: name),
            headers: ["Authorization": "Bearer \(token)"]
        )
        request.timeout = Self.timeout
        do {
            let _: OKResponse = try await http.send(request)
        } catch {
            throw Self.mapServerError(error)
        }
    }

    func deleteAccount(_ body: DeleteAccountRequest, token: String) async throws -> DeleteAccountResponse {
        var request = try HTTPRequest.postJSON(
            baseURL.appending(path: "me/delete"),
            body: body,
            headers: ["Authorization": "Bearer \(token)"]
        )
        request.timeout = Self.timeout
        do {
            return try await http.send(request)
        } catch {
            throw Self.mapServerError(error)
        }
    }

    func syncAppleSubscription(signedTransaction: String, token: String) async throws -> SubscriptionStatusDTO {
        var request = try HTTPRequest.postJSON(
            baseURL.appending(path: "subscription/sync-apple"),
            body: SyncAppleSubscriptionRequest(signedTransaction: signedTransaction),
            headers: ["Authorization": "Bearer \(token)"]
        )
        request.timeout = Self.timeout
        do {
            let resp: SyncAppleSubscriptionResponse = try await http.send(request)
            return resp.subscription
        } catch {
            throw Self.mapServerError(error)
        }
    }

    /// 4xx/5xx 且 body 是后端标准错误格式时，转成带服务端文案的 AuthError；否则原样抛（HTTPError 已可展示）。
    private static func mapServerError(_ error: Error) -> Error {
        if case HTTPError.status(_, let body) = error,
           let body,
           let envelope = try? JSONDecoder.iso8601.decode(APIErrorEnvelope.self, from: body) {
            return AuthError.server(
                code: envelope.error.code,
                message: envelope.error.message,
                retryAfter: envelope.retryAfter
            )
        }
        return error
    }
}

// MARK: - Mock 实现（离线 UI 开发用，固定验证码 123456）

struct MockAuthService: AuthService {
    func sendCode(phone: String) async throws -> Int {
        try await Task.sleep(for: .milliseconds(400))
        return 60
    }

    func login(phone: String, code: String) async throws -> AuthResponse {
        try await Task.sleep(for: .milliseconds(400))
        guard code == "123456" else {
            throw AuthError.server(code: "verify_code_invalid", message: "验证码错误", retryAfter: nil)
        }
        let json = """
        {"token":"mock-token","user":{"id":1,"phone":"\(phone)","email":null,"displayName":null,"penPalName":"阿远","bindings":[{"provider":"phone"}]}}
        """
        return try JSONDecoder.iso8601.decode(AuthResponse.self, from: Data(json.utf8))
    }

    func fetchMe(token: String) async throws -> MeResponse {
        let json = """
        {"user":{"id":1,"phone":"13800138000","email":null,"displayName":null,"penPalName":"阿远","bindings":[{"provider":"phone"}]},"subscription":{"isActive":false,"productId":null,"platform":null,"expiresAt":null}}
        """
        return try JSONDecoder.iso8601.decode(MeResponse.self, from: Data(json.utf8))
    }

    func loginWithApple(identityToken: String, displayName: String?) async throws -> AuthResponse {
        try await Task.sleep(for: .milliseconds(400))
        let json = """
        {"token":"mock-token","user":{"id":2,"phone":null,"email":null,"displayName":"Mock 用户","penPalName":"阿远","bindings":[{"provider":"apple"}]}}
        """
        return try JSONDecoder.iso8601.decode(AuthResponse.self, from: Data(json.utf8))
    }

    func bindApple(identityToken: String, token: String) async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    func bindPhone(phone: String, code: String, token: String) async throws -> BindPhoneResponse {
        try await Task.sleep(for: .milliseconds(400))
        guard code == "123456" else {
            throw AuthError.server(code: "verify_code_invalid", message: "验证码错误", retryAfter: nil)
        }
        // 用尾号 9 的手机号模拟「该号已属于另一个账号 → 触发账号转移」这条分支
        let switched = phone.hasSuffix("9")
        let json = """
        {"ok":true,"switchedAccount":\(switched),"token":"mock-token-switched","user":{"id":\(switched ? 1 : 2),"phone":"\(phone)","email":null,"displayName":\(switched ? "\"原账号昵称\"" : "null"),"penPalName":"阿远","bindings":[{"provider":"phone"},{"provider":"apple"}]}}
        """
        return try JSONDecoder.iso8601.decode(BindPhoneResponse.self, from: Data(json.utf8))
    }

    func changePhone(oldCode: String, newPhone: String, newCode: String, token: String) async throws -> UserDTO {
        try await Task.sleep(for: .milliseconds(400))
        guard oldCode == "123456", newCode == "123456" else {
            throw AuthError.server(code: "verify_code_invalid", message: "验证码错误", retryAfter: nil)
        }
        let json = """
        {"user":{"id":1,"phone":"\(newPhone)","email":null,"displayName":null,"penPalName":"阿远","bindings":[{"provider":"phone"}]}}
        """
        return try JSONDecoder.iso8601.decode(MeUserResponse.self, from: Data(json.utf8)).user
    }

    func updateDisplayName(_ name: String, token: String) async throws {
        try await Task.sleep(for: .milliseconds(300))
        guard name.count <= 64 else {
            throw AuthError.server(code: "bad_request", message: "昵称最长 64 字符", retryAfter: nil)
        }
    }

    func deleteAccount(_ request: DeleteAccountRequest, token: String) async throws -> DeleteAccountResponse {
        try await Task.sleep(for: .milliseconds(500))
        if let code = request.code, code != "123456" {
            throw AuthError.server(code: "verify_code_invalid", message: "验证码错误", retryAfter: nil)
        }
        guard request.code != nil || request.appleIdentityToken != nil else {
            throw AuthError.server(code: "bad_request", message: "注销账号前需要先验证身份", retryAfter: nil)
        }
        return DeleteAccountResponse(ok: true, appleRevoked: request.appleAuthorizationCode != nil)
    }

    func syncAppleSubscription(signedTransaction: String, token: String) async throws -> SubscriptionStatusDTO {
        try await Task.sleep(for: .milliseconds(200))
        return SubscriptionStatusDTO(isActive: true, productId: StoreKitManager.yearlyID, platform: "ios", expiresAt: nil)
    }
}
