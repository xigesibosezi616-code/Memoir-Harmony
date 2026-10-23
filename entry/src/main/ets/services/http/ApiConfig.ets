/**
 * 后端地址与超时分级（10_BUILD_MANUAL.md 4.1；02_BACKEND_API.md「后端在哪」）。
 *
 * - 只接大陆后端（02_BACKEND_API.md：2026-07-29 起单线，海外推迟），不做区域判定
 * - 基础地址一个常量：当前用阿里云函数计算域名；备案域名 https://api.sinaratech.com.cn
 *   上线后只改 BASE_URL 一处（09_OPEN_QUESTIONS.md Q15）
 * - 超时分级：寄信（DeepSeek 写信，服务端 75s 先放弃，客户端给足 90s）> 补领 / 默认 >
 *   节奏（iOS ProxyAIService 同款 15s）
 */

export class ApiConfig {
  /** 大陆后端基础地址（Q15：备案后切 https://api.sinaratech.com.cn） */
  static readonly BASE_URL: string = 'https://memoir-api-cn-ecdrwvhwac.cn-hangzhou.fcapp.run';

  /** POST /letter 寄信：LLM 出字慢，服务端 75s 先放弃 */
  static readonly TIMEOUT_SEND_LETTER_S: number = 90;

  /** GET /letters 补领（R-OUTBOX-07/09：响应丢了信其实已写好，靠它捞回） */
  static readonly TIMEOUT_FETCH_S: number = 30;

  /** GET /me/rhythm 来信节奏（判定权在服务端，只是提前问一声） */
  static readonly TIMEOUT_RHYTHM_S: number = 15;

  /** 其余请求默认超时（与 iOS HTTPRequest.timeout 30s 一致） */
  static readonly TIMEOUT_DEFAULT_S: number = 30;
}
