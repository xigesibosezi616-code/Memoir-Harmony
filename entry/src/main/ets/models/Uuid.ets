/**
 * UUID 约定（05_DATA_MODEL.md §0）。对应 iOS 各模型里的 `UUID()`。
 *
 * - iOS 写出的是**大写带横线**（`8B1F2C3D-...`），鸿蒙生成的同样写大写
 * - **比较时忽略大小写**：备份包按 id 去重，大小写不一致会把同一篇当两篇
 */
import { util } from '@kit.ArkTS';

/** 生成大写带横线的 UUID 字符串（新记录一律用它） */
export function generateUuid(): string {
  return util.generateRandomUUID(true);
}

/** id 相等判断：忽略大小写（大小写不同视作同一条记录） */
export function uuidEquals(a: string, b: string): boolean {
  return a.toUpperCase() === b.toUpperCase();
}

/** 拷贝 / 去重时用的规范键：统一转大写 */
export function uuidKey(u: string): string {
  return u.toUpperCase();
}
