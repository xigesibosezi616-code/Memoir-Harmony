/**
 * 华为账号授权纯逻辑（U02 更新包；09 Q1/Q17 的解法）。与 Account Kit 壳分离保本地可测。
 *
 * 口径（U02 R-ACCOUNT-09/10）：
 * - 客户端只交 Account Kit 的 **idToken**（/auth/huawei、/me/bindings/huawei 服务端验签），
 *   unionID / openID 是客户端自报标识，服务端不认——一个都不上送
 * - 注销验证要 idToken + authorizationCode **一起**交 /me/delete（服务端据此撤销华为授权；
 *   授权码 5 分钟内有效、只能用一次，拿到就用，取消注销时丢掉）
 * - 用户取消 / 华为账号未登录：静默回页面，不弹错；其他失败打完整日志 + 提示
 */

/** 一次华为账号授权拿到的东西（只留服务端要的；unionID / openID 不出这一层） */
export class HuaweiIdProof {
  readonly idToken: string;
  readonly authorizationCode: string;

  constructor(idToken: string, authorizationCode: string) {
    this.idToken = idToken;
    this.authorizationCode = authorizationCode;
  }
}

export class HuaweiAuthLogic {
  /** Account Kit：用户取消授权 */
  static readonly CODE_USER_CANCEL: number = 1001502012;
  /** Account Kit：华为账号未登录 */
  static readonly CODE_NOT_LOGGED_IN: number = 1001502001;

  /** 静默档：取消 / 未登录华为账号，回页面不弹错（U02 R-ACCOUNT-09） */
  static isSilentKitError(code: number): boolean {
    return code === HuaweiAuthLogic.CODE_USER_CANCEL ||
      code === HuaweiAuthLogic.CODE_NOT_LOGGED_IN;
  }

  /** 登录 / 绑定用：idToken 必须有（authorizationCode 可缺，归一 ''）；拿不到回 null */
  static proofFor(idToken: string | undefined,
    authorizationCode: string | undefined): HuaweiIdProof | null {
    if (typeof idToken !== 'string' || idToken.length === 0) {
      return null;
    }
    const code: string = typeof authorizationCode === 'string' ? authorizationCode : '';
    return new HuaweiIdProof(idToken, code);
  }

  /** 注销验证用：idToken 和 authorizationCode 都必须有（缺一个服务端撤销不了授权） */
  static deleteProofFor(idToken: string | undefined,
    authorizationCode: string | undefined): HuaweiIdProof | null {
    if (typeof idToken !== 'string' || idToken.length === 0) {
      return null;
    }
    if (typeof authorizationCode !== 'string' || authorizationCode.length === 0) {
      return null;
    }
    return new HuaweiIdProof(idToken, authorizationCode);
  }
}
