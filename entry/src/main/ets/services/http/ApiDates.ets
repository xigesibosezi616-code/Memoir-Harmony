/**
 * 服务端日期解析（10_BUILD_MANUAL.md 4.1；02_BACKEND_API.md「日期」）。
 *
 * 服务端日期一律 `toISOString()`（带毫秒，如 2026-09-17T10:20:30.123Z）；
 * 但手写的 / 别的服务发来的可能不带毫秒——两种都要认（iOS ISO8601DateFormatter.memoirDate 同款语义）。
 * 只认 ISO8601 + Z 结尾：`Date.parse` 对非 ISO 串过于宽容（'2026' 也能解析），先做形状校验。
 */

/** ISO8601 带或不带毫秒：YYYY-MM-DDTHH:mm:ss(.fff)?Z */
const ISO8601_Z_RE: RegExp = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;

export class ApiDates {
  /** 解析 ISO8601 日期（带/不带毫秒都认）；形状不对或非法日期返回 null */
  static parse(raw: string): Date | null {
    if (raw.length === 0 || !ISO8601_Z_RE.test(raw)) {
      return null;
    }
    const t = Date.parse(raw);
    if (Number.isNaN(t)) {
      return null;
    }
    return new Date(t);
  }
}
