/**
 * UUID 约定（05_DATA_MODEL.md §0）。对应 iOS 各模型里的 `UUID()`。
 *
 * - iOS 写出的是**大写带横线**（`8B1F2C3D-...`），鸿蒙同样统一写大写
 *   （`util.generateRandomUUID` 原样返回**小写**，这里转大写对齐 iOS）
 * - **比较时忽略大小写**：备份包按 id 去重，大小写不一致会把同一篇当两篇
 * - SDK 在部分运行环境（本地单测执行器）返回空串：兜底手写 v4，
 *   随机性降级为 Math.random，仅极端环境会走到
 */
import { util } from '@kit.ArkTS';

/** 手写 UUID v4（大写带横线）。只有 `util.generateRandomUUID` 不可用时才走这里 */
function fallbackUuid(): string {
  const hex = '0123456789ABCDEF';
  let u = '';
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) {
      u += '-';
    } else if (i === 14) {
      u += '4';
    } else if (i === 19) {
      // 变体位只取 8/9/A/B
      u += hex.charAt(8 + Math.floor(Math.random() * 4));
    } else {
      u += hex.charAt(Math.floor(Math.random() * 16));
    }
  }
  return u;
}

/** 生成大写带横线的 UUID 字符串（新记录一律用它） */
export function generateUuid(): string {
  let raw = '';
  try {
    raw = util.generateRandomUUID(true);
  } catch (err) {
    raw = '';
  }
  if (raw.length !== 36) {
    return fallbackUuid();
  }
  return raw.toUpperCase();
}

/** id 相等判断：忽略大小写（大小写不同视作同一条记录） */
export function uuidEquals(a: string, b: string): boolean {
  return a.toUpperCase() === b.toUpperCase();
}

/** 拷贝 / 去重时用的规范键：统一转大写 */
export function uuidKey(u: string): string {
  return u.toUpperCase();
}

/** 是不是合法 UUID 字符串（8-4-4-4-12 位十六进制，大小写都认）。
 *  回执里的手记改法只认 UUID：id 不是 UUID 的 update / remove 丢掉（R-NOTEBOOK-04，
 *  iOS `UUID(uuidString:)` 同款判断） */
export function isUuidString(u: string): boolean {
  if (u.length !== 36) {
    return false;
  }
  for (let i = 0; i < 36; i++) {
    const c = u.charAt(i);
    if (i === 8 || i === 13 || i === 18 || i === 23) {
      if (c !== '-') {
        return false;
      }
    } else {
      const isHex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
      if (!isHex) {
        return false;
      }
    }
  }
  return true;
}
