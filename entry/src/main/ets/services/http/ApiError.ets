/**
 * 后端统一错误 envelope 解析（10_BUILD_MANUAL.md 4.1；02_BACKEND_API.md types）。
 *
 *   { "error": { "code": "...", "message": "...", "detail?": "..." } }   ← 统一壳
 *   顶层可能还有：retryAfter（验证码冷却剩余秒）/ reason（429 来信节奏）/
 *   nextLetterAt（下一封可寄时刻，ISO8601 字符串，调用方用 ApiDates 再解析）/ tier
 *
 * `message` 服务端只出中文，客户端按 code / reason 自己渲染七种语言——
 * 本类只做忠实解析，不做本地化（那是 4.2+/5.x 调用方的事）。
 */

/** JSON.parse 的原样形状（宽松：全部字段可能缺、可能类型不对，逐字段 typeof 校验） */
interface ApiErrorDetailRaw {
  code?: string;
  message?: string;
  detail?: string;
}

interface ApiErrorRaw {
  error?: ApiErrorDetailRaw;
  reason?: string;
  retryAfter?: number;
  nextLetterAt?: string;
  tier?: string;
}

export class ApiErrorEnvelope {
  /** 统一壳内 error.code（如 rate_limited / ai_failed / invalid_token） */
  readonly code: string;
  /** 服务端中文文案（调试 / 兜底展示用，正式文案按 code 取字符串资源） */
  readonly message: string;

  /** 顶层 extras（出现才有值） */
  detail?: string;
  reason?: string;
  retryAfter?: number;
  nextLetterAt?: string;
  tier?: string;

  constructor(code: string, message: string) {
    this.code = code;
    this.message = message;
  }

  /**
   * 从响应体解析统一错误 envelope；不是统一壳（健康检查、网关 HTML、空体等）返回 null。
   * JSON.parse 一次 cast 到 raw 接口，再 typeof 逐字段校验拷入严格类（彩云三层校验同款范式）。
   */
  static parse(body: string): ApiErrorEnvelope | null {
    if (body.length === 0) {
      return null;
    }
    try {
      const raw = JSON.parse(body) as ApiErrorRaw;
      if (raw === null || typeof raw !== 'object') {
        return null;
      }
      const detail = raw.error;
      if (detail === null || detail === undefined || typeof detail !== 'object' ||
        typeof detail.code !== 'string' || typeof detail.message !== 'string') {
        return null; // 不是 { error: { code, message } } 统一壳
      }
      const envelope = new ApiErrorEnvelope(detail.code, detail.message);
      if (typeof detail.detail === 'string') {
        envelope.detail = detail.detail;
      }
      if (typeof raw.reason === 'string') {
        envelope.reason = raw.reason;
      }
      if (typeof raw.retryAfter === 'number') {
        envelope.retryAfter = raw.retryAfter;
      }
      if (typeof raw.nextLetterAt === 'string') {
        envelope.nextLetterAt = raw.nextLetterAt;
      }
      if (typeof raw.tier === 'string') {
        envelope.tier = raw.tier;
      }
      return envelope;
    } catch (e) {
      return null; // 非 JSON（HTML 错误页等）
    }
  }
}
