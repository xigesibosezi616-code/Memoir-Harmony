/**
 * 华为账号授权 Account Kit 壳（U02 更新包）。
 *
 * 登录页 / 注销页用官方 LoginWithHuaweiIDButton 组件（回调直接给 HuaweiIDCredential）；
 * 本壳服务没有官方按钮的入口——账户页「绑定华为账号」行点行触发：
 * authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest()（forceLogin = true）
 * 走同样的华为账号授权界面。
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
