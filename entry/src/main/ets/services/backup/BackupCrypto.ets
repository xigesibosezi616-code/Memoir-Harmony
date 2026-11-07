/**
 * 备份包加密（6.4 / 6.5；iOS `Services/Backup/BackupCrypto.swift`）。
 *
 * **设计**：先打成标准 zip，再把整个 zip 加密成一个文件 —— 不用 zip 自带的加密
 * （算法弱、各平台实现不一致，跨端难对齐）。整体加密则跨端只需实现
 * 「PBKDF2 派生密钥 + AES-GCM 解密」。
 *
 * **文件布局**（加密时，与 iOS 逐字节一致）：
 * ```
 * [8B]  magic "MEMOIRBK"
 * [1B]  版本 = 1
 * [1B]  标志位：0x01 = 已加密
 * [16B] salt（明文，不敏感，派生密钥用）
 * [12B] nonce（明文，AES-GCM 要求每次不同）
 * [..]  密文 + 16B 认证标签
 * ```
 * 不加密时不写任何头，文件就是纯 zip（PK 开头），改名 .zip 就能打开。
 *
 * 参数：PBKDF2-HMAC-SHA256，210000 轮（OWASP 建议量级，与 iOS 同值——
 * 轮数不一致两端互相解不开），AES-256-GCM（认证标签 16B，附在密文尾部）。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

/** 加解密失败类型（iOS `CryptoError` 同名同义；文案由导入 / 导出服务映射） */
export enum BackupCryptoError {
  KeyDerivationFailed = 'keyDerivationFailed',
  NotEncrypted = 'notEncrypted',
  MalformedHeader = 'malformedHeader',
  WrongPassword = 'wrongPassword'
}

/** 带 kind 的失败：调用方按 kind 映射用户文案，不解析 message 字符串 */
export class BackupCryptoFailure extends Error {
  readonly kind: BackupCryptoError;

  constructor(kind: BackupCryptoError) {
    super(kind);
    this.kind = kind;
  }
}

/** 8B 魔数。看它就知道是不是我们加密的包，不必解密 */
const MAGIC: Uint8Array = new util.TextEncoder().encodeInto('MEMOIRBK');

/** GCM 认证标签长度（字节） */
const TAG_LENGTH: number = 16;

/** PBKDF2 迭代次数。🔴 必须与 iOS 同值，否则互相解不开 */
const PBKDF2_ITERATIONS: number = 210000;

/** 派生密钥长度（字节）：AES-256 用 32 字节 */
const KEY_LENGTH_BYTES: number = 32;

function concatBytes(chunks: Uint8Array[]): Uint8Array {
  let total = 0;
  for (const chunk of chunks) {
    total += chunk.length;
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

export class BackupCrypto {
  static readonly saltLength: number = 16;
  static readonly nonceLength: number = 12;

  /** 文件是否为加密过的包（看魔数即可）。空文件 / 纯 zip 返回 false */
  static isEncrypted(data: Uint8Array): boolean {
    if (data.length <= MAGIC.length) {
      return false;
    }
    for (let i = 0; i < MAGIC.length; i++) {
      if (data[i] !== MAGIC[i]) {
        return false;
      }
    }
    return true;
  }

  /** PBKDF2-HMAC-SHA256 派生 AES-256 密钥。不能直接把密码当密钥（熵低，字典攻击几秒跑穿） */
  private static async deriveKey(password: string, salt: Uint8Array): Promise<cryptoFramework.SymKey> {
    try {
      const passwordBytes = new util.TextEncoder().encodeInto(password);
      const kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
      const spec: cryptoFramework.PBKDF2Spec = {
        algName: 'PBKDF2',
        password: passwordBytes,
        salt: salt,
        iterations: PBKDF2_ITERATIONS,
        keySize: KEY_LENGTH_BYTES
      };
      const keyBlob = await kdf.generateSecret(spec);
      const keyGen = cryptoFramework.createSymKeyGenerator('AES256');
      return await keyGen.convertKey(keyBlob);
    } catch (err) {
      throw new BackupCryptoFailure(BackupCryptoError.KeyDerivationFailed);
    }
  }

  /** 加密：明文（zip 字节）→ 带头部的密文文件字节 */
  static async encrypt(plaintext: Uint8Array, password: string): Promise<Uint8Array> {
    const random = cryptoFramework.createRandom();
    let salt: Uint8Array;
    let nonce: Uint8Array;
    try {
      salt = random.generateRandomSync(BackupCrypto.saltLength).data;
      nonce = random.generateRandomSync(BackupCrypto.nonceLength).data;
    } catch (err) {
      throw new BackupCryptoFailure(BackupCryptoError.KeyDerivationFailed);
    }
    if (salt.length !== BackupCrypto.saltLength || nonce.length !== BackupCrypto.nonceLength) {
      throw new BackupCryptoFailure(BackupCryptoError.KeyDerivationFailed);
    }
    const key = await BackupCrypto.deriveKey(password, salt);
    try {
      const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
      const params: cryptoFramework.GcmParamsSpec = {
        iv: { data: nonce },
        aad: { data: new Uint8Array(0) },
        authTag: { data: new Uint8Array(0) },
        algName: 'GcmParamsSpec'
      };
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, params);
      // GCM 模式 doFinal 输出 = 密文 + 16B 认证标签（附在尾部，与 iOS sealed.ciphertext+tag 一致）
      const sealed = await cipher.doFinal({ data: plaintext });
      const header = new Uint8Array(MAGIC.length + 2 + BackupCrypto.saltLength + BackupCrypto.nonceLength);
      header.set(MAGIC, 0);
      header[MAGIC.length] = 1; // 版本
      header[MAGIC.length + 1] = 0x01; // 标志位：已加密
      header.set(salt, MAGIC.length + 2);
      header.set(nonce, MAGIC.length + 2 + BackupCrypto.saltLength);
      return concatBytes([header, sealed.data]);
    } catch (err) {
      throw new BackupCryptoFailure(BackupCryptoError.KeyDerivationFailed);
    }
  }

  /** 解密：带头部的密文文件字节 → 明文（zip 字节） */
  static async decrypt(data: Uint8Array, password: string): Promise<Uint8Array> {
    if (!BackupCrypto.isEncrypted(data)) {
      throw new BackupCryptoFailure(BackupCryptoError.NotEncrypted);
    }
    const headerLength = MAGIC.length + 2 + BackupCrypto.saltLength + BackupCrypto.nonceLength;
    // 密文至少要有 16 字节认证标签
    if (data.length <= headerLength + TAG_LENGTH) {
      throw new BackupCryptoFailure(BackupCryptoError.MalformedHeader);
    }
    const fileVersion = data[MAGIC.length];
    if (fileVersion !== 1) {
      throw new BackupCryptoFailure(BackupCryptoError.MalformedHeader);
    }
    const salt = data.subarray(MAGIC.length + 2, MAGIC.length + 2 + BackupCrypto.saltLength);
    const nonce = data.subarray(MAGIC.length + 2 + BackupCrypto.saltLength, headerLength);
    const body = data.subarray(headerLength);
    const tag = body.subarray(body.length - TAG_LENGTH);
    const ciphertext = body.subarray(0, body.length - TAG_LENGTH);
    const key = await BackupCrypto.deriveKey(password, salt);
    try {
      const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
      const params: cryptoFramework.GcmParamsSpec = {
        iv: { data: nonce },
        aad: { data: new Uint8Array(0) },
        authTag: { data: tag },
        algName: 'GcmParamsSpec'
      };
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, params);
      const plain = await cipher.doFinal({ data: ciphertext });
      return plain.data;
    } catch (err) {
      // GCM 认证标签校验失败 —— 绝大多数情况就是密码错了
      throw new BackupCryptoFailure(BackupCryptoError.WrongPassword);
    }
  }
}
