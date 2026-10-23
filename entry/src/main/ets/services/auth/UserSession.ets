/**
 * 登录会话容器（10_BUILD_MANUAL.md 4.2）。对应 iOS `UserSession.swift`。
 *
 * 职责：token + 用户快照的内存态与安全存储持久化，两条腿同时走——
 * - establish：登录 / 换绑成功后落内存 + 落安全存储（杀进程仍登录）
 * - clear：登出 / 401 闸门触发，内存与存储一并清
 * - 构造时同步恢复（AssetSessionStore 同步 API），应用启动即知登录态
 *
 * 快照损坏（解析抛错）不丢 token：仍算已登录，user 为 null，
 * 后续 fetchMe 可刷新快照——比一刀切踢回登录页体验好。
 * UI 响应式（登录态变化驱动界面）4.3 账户卡接 AppStorage tick 再做。
 */
import { SessionStore, SESSION_KEY_TOKEN, SESSION_KEY_USER } from './SessionStore';
import { UserDTO, parseUserDto } from '../../models/Api';

/**
 * AppStorage key：登录态变化信号（establish / 401 清理时调用方 +1）。
 * UserSession 本体无观察机制，设置页（4.3 账户卡）@Watch 这个 tick 重读会话
 * ——RDB 无观察机制用 reloadTick 补 iOS @Query 的同款手法。
 * 故意不放 UserSession 方法里：AppStorage 是 UI 运行时能力，本类要保单测可跑。
 */
export const STORAGE_KEY_SESSION_TICK = 'session.tick';

export class UserSession {
  private tokenValue: string | null = null;
  private userValue: UserDTO | null = null;
  private readonly store: SessionStore;

  constructor(store: SessionStore) {
    this.store = store;
    this.tokenValue = store.get(SESSION_KEY_TOKEN);
    if (this.tokenValue !== null) {
      const raw: string | null = store.get(SESSION_KEY_USER);
      if (raw !== null) {
        try {
          this.userValue = parseUserDto(raw);
        } catch (e) {
          this.userValue = null;
        }
      }
    }
  }

  get token(): string | null {
    return this.tokenValue;
  }

  get user(): UserDTO | null {
    return this.userValue;
  }

  isLoggedIn(): boolean {
    return this.tokenValue !== null;
  }

  /** 登录 / 换绑成功：token + 用户快照落内存并持久化 */
  establish(token: string, user: UserDTO): void {
    this.tokenValue = token;
    this.userValue = user;
    this.store.set(SESSION_KEY_TOKEN, token);
    this.store.set(SESSION_KEY_USER, JSON.stringify(user));
  }

  /** 只刷新用户快照（fetchMe / 绑定成功不换 token 的场景） */
  updateUser(user: UserDTO): void {
    if (this.tokenValue === null) {
      return;
    }
    this.userValue = user;
    this.store.set(SESSION_KEY_USER, JSON.stringify(user));
  }

  /** 登出 / 401：内存与安全存储一并清 */
  clear(): void {
    this.tokenValue = null;
    this.userValue = null;
    this.store.remove(SESSION_KEY_TOKEN);
    this.store.remove(SESSION_KEY_USER);
  }
}
