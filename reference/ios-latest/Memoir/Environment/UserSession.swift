import Foundation

/// 登录态容器 —— token + 用户快照，持久化在 Keychain（不进 UserDefaults，手机号是敏感信息）。
///
/// 挂在 `AppEnvironment.session`；View 通过 `@Environment(AppEnvironment.self)` 观察 `isLoggedIn` / `user`。
/// 收到任何接口 401 时调用 `clear()`，UI 自然回到未登录态（AUTH_DESIGN.md §3.2）。
@Observable
final class UserSession {
    private(set) var token: String?
    private(set) var user: UserDTO?

    var isLoggedIn: Bool { token != nil }

    /// 受保护请求的鉴权头。未登录时为空字典。
    var authHeaders: [String: String] {
        guard let token else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }

    private let keychain: KeychainStore
    private static let tokenKey = "jwt"
    private static let userKey = "userSnapshot"

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
        token = keychain.string(forKey: Self.tokenKey)
        if let json = keychain.string(forKey: Self.userKey) {
            user = try? JSONDecoder.iso8601.decode(UserDTO.self, from: Data(json.utf8))
        }
    }

    /// 登录成功：写入内存 + Keychain。
    func establish(token: String, user: UserDTO) {
        self.token = token
        self.user = user
        keychain.set(token, forKey: Self.tokenKey)
        persistUser(user)
    }

    /// 刷新用户快照（如 /me 返回了更新的 penPalName）。
    func updateUser(_ user: UserDTO) {
        self.user = user
        persistUser(user)
    }

    /// 退出登录 / 收到 401：清空内存与 Keychain。
    func clear() {
        token = nil
        user = nil
        keychain.remove(forKey: Self.tokenKey)
        keychain.remove(forKey: Self.userKey)
    }

    private func persistUser(_ user: UserDTO) {
        if let data = try? JSONEncoder.iso8601.encode(user) {
            keychain.set(String(decoding: data, as: UTF8.self), forKey: Self.userKey)
        }
    }
}
