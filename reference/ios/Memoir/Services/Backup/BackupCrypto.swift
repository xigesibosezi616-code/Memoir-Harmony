import Foundation
import CryptoKit
import CommonCrypto

/// 备份包加密。
///
/// **设计**：先打成标准 zip，再把整个 zip 加密成一个文件 —— 不用 zip 自带的加密，
/// 那套算法弱、各平台实现还不一致，鸿蒙端难以对齐。整体加密则跨端只需实现
/// 「PBKDF2 派生密钥 + AES-GCM 解密」，两行库调用的事。
///
/// **文件布局**（加密时）：
/// ```
/// [8B] magic "MEMOIRBK"
/// [1B] 版本 = 1
/// [1B] 标志位：0x01 = 已加密
/// [16B] salt（明文，不敏感，派生密钥用）
/// [12B] nonce（明文，AES-GCM 要求每次不同）
/// [..]  密文 + 16B 认证标签
/// ```
/// **不加密时不写任何头**，文件就是纯 zip（`PK\x03\x04` 开头），
/// 用户改名 `.zip` 就能打开看自己的东西。
/// `nonisolated`：全是纯函数。PBKDF2 跑 21 万轮要一两百毫秒，导入时必须能在后台线程调用，
/// 所以明确退出工程默认的 MainActor 隔离。
nonisolated enum BackupCrypto {
    static let magic = Data("MEMOIRBK".utf8)
    static let version: UInt8 = 1
    static let saltLength = 16
    static let nonceLength = 12

    /// PBKDF2 迭代次数。OWASP 对 PBKDF2-HMAC-SHA256 的建议量级；
    /// 手机上约 100-200ms，对一次性的导出/导入完全可接受，但能显著抬高暴力破解成本。
    static let iterations: UInt32 = 210_000

    enum CryptoError: LocalizedError {
        case keyDerivationFailed
        case notEncrypted
        case malformedHeader
        case wrongPassword

        var errorDescription: String? {
            switch self {
            // 会显示给用户，`Text(String)` 不查表 —— 必须显式 NSLocalizedString
            case .keyDerivationFailed: return NSLocalizedString("密钥生成失败", bundle: .appLanguage, comment: "备份加解密错误")
            case .notEncrypted:        return NSLocalizedString("这个文件没有加密", bundle: .appLanguage, comment: "备份加解密错误")
            case .malformedHeader:     return NSLocalizedString("文件格式不正确，可能已损坏", bundle: .appLanguage, comment: "备份加解密错误")
            case .wrongPassword:       return NSLocalizedString("密码不对，请重新输入", bundle: .appLanguage, comment: "备份加解密错误")
            }
        }
    }

    /// 文件是否为我们加密过的包（看魔数即可，不必解密）
    static func isEncrypted(_ data: Data) -> Bool {
        data.count > magic.count && data.prefix(magic.count) == magic
    }

    // MARK: - 加密

    static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        var salt = Data(count: saltLength)
        let status = salt.withUnsafeMutableBytes { buf in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, buf.baseAddress!)
        }
        guard status == errSecSuccess else { throw CryptoError.keyDerivationFailed }

        let key = try deriveKey(password: password, salt: salt)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

        var out = Data()
        out.append(magic)
        out.append(version)
        out.append(0x01)                      // 标志位：已加密
        out.append(salt)
        out.append(Data(nonce))
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    // MARK: - 解密

    static func decrypt(_ data: Data, password: String) throws -> Data {
        guard isEncrypted(data) else { throw CryptoError.notEncrypted }

        let headerLength = magic.count + 2 + saltLength + nonceLength
        // 密文至少要有 16 字节认证标签
        guard data.count > headerLength + 16 else { throw CryptoError.malformedHeader }

        var cursor = magic.count
        let fileVersion = data[data.startIndex + cursor]
        guard fileVersion == version else { throw CryptoError.malformedHeader }
        cursor += 2   // 跳过版本 + 标志位

        let salt = data.subdata(in: (data.startIndex + cursor)..<(data.startIndex + cursor + saltLength))
        cursor += saltLength
        let nonceData = data.subdata(in: (data.startIndex + cursor)..<(data.startIndex + cursor + nonceLength))
        cursor += nonceLength

        let body = data.subdata(in: (data.startIndex + cursor)..<data.endIndex)
        let ciphertext = body.dropLast(16)
        let tag = body.suffix(16)

        let key = try deriveKey(password: password, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            return try AES.GCM.open(box, using: key)
        } catch {
            // GCM 的认证标签校验失败 —— 绝大多数情况就是密码错了
            throw CryptoError.wrongPassword
        }
    }

    // MARK: - 密钥派生

    /// PBKDF2-HMAC-SHA256。**不能直接把密码当密钥** ——
    /// 用户密码熵低，不做慢派生的话字典攻击几秒就能跑穿。
    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derived = Data(count: 32)

        let result = derived.withUnsafeMutableBytes { derivedBuf in
            salt.withUnsafeBytes { saltBuf in
                passwordData.withUnsafeBytes { passBuf in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBuf.baseAddress!.assumingMemoryBound(to: CChar.self),
                        passwordData.count,
                        saltBuf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedBuf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        guard result == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }
}
