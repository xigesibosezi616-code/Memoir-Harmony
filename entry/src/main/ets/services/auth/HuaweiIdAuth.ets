/**
 * 华为账号授权 Account Kit 壳（U02 更新包）。
 *
 * 自己触发授权的入口都走本壳（请求式授权，forceLogin = true，与官方按钮同一套
 * 华为账号授权界面）：登录页自绘华为按钮（2026-11-07 起登录不再用官方
 * LoginWithHuaweiIDButton——设备上无 AGC 配置时官方按钮不渲染华为 logo，用户
 * 要求换成自绘按钮带华为图标）、账户页「绑定华为账号」行点行触发。
 * 注销页仍用官方 LoginWithHuaweiIDButton 组件（回调直接给 HuaweiIDCredential）。
 *
 * import Account Kit，本地单测跑不了；纯逻辑在 HuaweiAuthLogic（有单测）。
 * 取消 / 未登录的静默判断在调用方（HuaweiAuthLogic.isSilentKitError）。
 */
import { authentication } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HuaweiIdProof, HuaweiAuthLogic } from './HuaweiAuthLogic';

const DOMAIN = 0x0000;
const TAG = 'HuaweiIdAuth';

/** Account Kit 错误归一（code 供 HuaweiAuthLogic.isSilentKitError 分类静默档） */
export class HuaweiIdAuthError extends Error {
  readonly code: number;

  constructor(code: number, message: string) {
    super(message);
    this.name = 'HuaweiIdAuthError';
    this.code = code;
  }
}

export class HuaweiIdAuth {
  /** 请求式授权（forceLogin）→ idToken（+ authorizationCode）。
   *  拿不到 idToken（如响应形状不对）抛 code 0 的 HuaweiIdAuthError。 */
  static async authorize(context: common.Context): Promise<HuaweiIdProof> {
    try {
      const provider = new authentication.HuaweiIDProvider();
      const request = provider.createLoginWithHuaweiIDRequest();
      request.forceLogin = true;
      const controller = new authentication.AuthenticationController(context);
      // 响应解析按官方范例用 as 断言，不用 instanceof：响应对象由 native 侧
      // 构造，运行时原型不指向 SDK 导出类，instanceof 恒 false（2026-10-24
      // 真机实测：授权 result 0 却抛 no huawei id credential）。
      const response = await controller.executeRequest(request) as
        authentication.LoginWithHuaweiIDResponse;
      hilog.info(DOMAIN, TAG, 'authorize: dataPresent=%{public}d',
        response.data !== undefined ? 1 : 0);
      if (response.data !== undefined) {
        const credential = response.data;
        const proof: HuaweiIdProof | null = HuaweiAuthLogic.proofFor(
          credential.idToken, credential.authorizationCode);
        if (proof !== null) {
          return proof;
        }
      }
      throw new HuaweiIdAuthError(0, 'no huawei id credential');
    } catch (e) {
      if (e instanceof HuaweiIdAuthError) {
        throw e;
      }
      const err = e as BusinessError;
      throw new HuaweiIdAuthError(err.code, err.message);
    }
  }
}
