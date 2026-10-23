/**
 * 基于 @ohos.net.http 的执行壳（10_BUILD_MANUAL.md 4.1）。
 * 对应 iOS `URLSessionHTTPClient`：把 HttpRequest 翻译执行，各种失败统一映射为 HttpError。
 *
 * 职责边界（iOS 同款）：不做 retry / 缓存 / 日志 / 自动展示错误——调用方决定。
 * 本文件 import kit，本地单测不直接 import（映射逻辑全在 kit-free 的 HttpMapping）。
 *
 * 取消路径：@ohos.net.http 无显式取消错误码，`destroy()` 掐断在途请求会以传输错误
 * 回来；寄信队列（5.x）的主动取消走 HttpError.cancelled 自建控制路径，不经本类。
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HttpRequest, HttpMethod } from './HttpRequest';
import { HttpMapping, UnauthorizedGate } from './HttpMapping';
import { HttpError } from './HttpError';

export class HarmonyHttpClient {
  /** 401 → 清登录态闸门（清理回调由 4.2 接 UserSession 时注入） */
  private readonly gate: UnauthorizedGate;

  constructor(onUnauthorized?: () => void) {
    this.gate = new UnauthorizedGate(onUnauthorized ?? (() => {
    }));
  }

  /** 请求并返回原始响应体字符串（200~299；其余状态抛 Status 档 HttpError） */
  async sendRaw(request: HttpRequest): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: this.kitMethod(request.method),
        header: request.headers,
        connectTimeout: request.timeoutSeconds * 1000,
        readTimeout: request.timeoutSeconds * 1000,
        expectDataType: http.HttpDataType.STRING
      };
      if (request.body.length > 0) {
        options.extraData = request.body;
      }
      const response: http.HttpResponse = await client.request(request.url, options);
      const code: number = response.responseCode;
      const body: string = typeof response.result === 'string' ? response.result : '';
      if (code >= 200 && code <= 299) {
        return body;
      }
      const error: HttpError = HttpMapping.fromStatus(code, body);
      this.gate.handleError(error);
      throw error;
    } catch (e) {
      if (e instanceof HttpError) {
        throw e;
      }
      const be = e as BusinessError;
      throw HttpMapping.fromTransportCode(be.code, be.message ?? '');
    } finally {
      client.destroy();
    }
  }

  /** 请求 + 注入 parse 解码为 T（泛型解码无反射，靠闭包注入；解码失败折成 Decoding 档） */
  async send<T>(request: HttpRequest, parse: (raw: string) => T): Promise<T> {
    const raw: string = await this.sendRaw(request);
    return HttpMapping.decode<T>(raw, parse);
  }

  private kitMethod(m: HttpMethod): http.RequestMethod {
    if (m === HttpMethod.POST) {
      return http.RequestMethod.POST;
    }
    if (m === HttpMethod.PATCH) {
      return http.RequestMethod.PATCH;
    }
    return http.RequestMethod.GET;
  }
}
