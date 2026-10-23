/**
 * 会话安全存储（Asset Store Kit 实现，10_BUILD_MANUAL.md 4.2）。
 * 对应 iOS `KeychainStore.swift`（AfterFirstUnlockThisDeviceOnly）。
 *
 * - `querySync / addSync / updateSync / removeSync` 全同步（API 12+），
 *   UserSession 构造时同步恢复登录态
 * - ACCESSIBILITY = DEVICE_FIRST_UNLOCKED：首次解锁后可读，
 *   对应 iOS kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
 * - 查询未找到抛 24000002（不是返回空数组），统一在 catch 里归一为 null
 * - add 重复别名抛 24000003：写入先 remove 再 add（快照更新高频，逻辑最简）
 * - 失败哲学与 iOS KeychainStore 一致：安全存储打不开不炸启动，归一为
 *   「读不到」（未登录），用户重登一次即恢复
 *
 * 本文件 import kit，本地单测不直接 import（2.10 范式；逻辑测试用内存 fake）。
 */
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SessionStore } from './SessionStore';

const DOMAIN = 0x0000;
const TAG = 'AssetSessionStore';

export class AssetSessionStore implements SessionStore {
  get(key: string): string | null {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.encode(key));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows: Array<asset.AssetMap> = asset.querySync(query);
      if (rows.length === 0) {
        return null;
      }
      const secret = rows[0].get(asset.Tag.SECRET);
      if (secret === undefined || !(secret instanceof Uint8Array)) {
        return null;
      }
      return this.decode(secret);
    } catch (e) {
      // 24000002 未找到属正常路径，不打 error；其余（安全存储不可用等）记一笔
      const be = e as BusinessError;
      if (be.code !== 24000002) {
        hilog.warn(DOMAIN, TAG, 'querySync failed, key=%{public}s code=%{public}d', key, be.code);
      }
      return null;
    }
  }

  set(key: string, value: string): void {
    // 先删后加：add 重复别名抛 24000003，remove 未找到的异常静默
    try {
      asset.removeSync(this.aliasQuery(key));
    } catch (e) {
      // 未找到（24000002）属正常，其余也吞掉——下面 add 失败会统一记日志
    }
    const attrs: asset.AssetMap = new Map();
    attrs.set(asset.Tag.ALIAS, this.encode(key));
    attrs.set(asset.Tag.SECRET, this.encode(value));
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      asset.addSync(attrs);
    } catch (e) {
      const be = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'addSync failed, key=%{public}s code=%{public}d', key, be.code);
    }
  }

  remove(key: string): void {
    try {
      asset.removeSync(this.aliasQuery(key));
    } catch (e) {
      const be = e as BusinessError;
      if (be.code !== 24000002) {
        hilog.warn(DOMAIN, TAG, 'removeSync failed, key=%{public}s code=%{public}d', key, be.code);
      }
    }
  }

  private aliasQuery(key: string): asset.AssetMap {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.encode(key));
    return query;
  }

  private encode(s: string): Uint8Array {
    return new util.TextEncoder().encodeInto(s);
  }

  private decode(bytes: Uint8Array): string {
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }
}
