/**
 * TEXT 列里的 JSON 数组编解码（`tags` / `audio_urls`）。
 * 解码容错：坏 JSON / 非数组 / 元素不是字符串 → 只丢坏的，绝不让整条记录读不出来。
 */

/** 解码字符串数组列；NULL / 坏 JSON / 非数组 → 空数组 */
export function parseStringArray(raw: string | null): string[] {
  if (raw === null) {
    return [];
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    return [];
  }
  if (parsed === null || !Array.isArray(parsed)) {
    return [];
  }
  const result: string[] = [];
  for (const item of parsed as Object[]) {
    if (typeof item === 'string') {
      result.push(item);
    }
  }
  return result;
}

/** 编码字符串数组列为 JSON */
export function encodeStringArray(values: string[]): string {
  return JSON.stringify(values);
}
