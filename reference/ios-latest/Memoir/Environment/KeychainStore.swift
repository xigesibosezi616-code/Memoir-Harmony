import Foundation
import Security

/// Keychain 薄封装 —— 只服务登录凭证的存取（JWT + 用户快照），不做泛化。
///
/// 访问级别 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`：
/// 设备解锁过一次即可读（兼容后台场景），且**不随备份迁移到新设备**——
/// 登录凭证不应跨设备漂移，新设备重新走短信登录。
struct KeychainStore {
    private let service: String

    init(service: String = "com.sinaratech.memoir.auth") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 写入（存在则覆盖）。失败静默——凭证写失败的后果是下次启动要重登，可接受且无法向用户解释。
    func set(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func remove(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
