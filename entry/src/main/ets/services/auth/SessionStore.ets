/**
 * 会话键值存储接口（10_BUILD_MANUAL.md 4.2）。对应 iOS `KeychainStore.swift` 的角色。
 *
 * 真机实现 AssetSessionStore（Asset Store Kit，同步 API）；单测用内存 fake。
 * 同步接口是有意为之：Asset Store Kit query/add/remove 均有 *Sync 版本，
 * UserSession 构造时同步恢复，UI 不用等异步回调（贴 iOS Keychain 模式）。
 */

/** Asset Store 别名（应用内命名空间，一手机一 App 隔离） */
export const SESSION_KEY_TOKEN = 'auth.token';
export const SESSION_KEY_USER = 'auth.userSnapshot';

export interface SessionStore {
  get(key: string): string | null;
  set(key: string, value: string): void;
  remove(key: string): void;
}
