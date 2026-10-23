/**
 * 手机号登录纯逻辑（10_BUILD_MANUAL.md 4.2）。对应 iOS `LoginView.swift` 里的
 * `isValidPhone` / onChange 过滤 / `maskedPhone`——抽成纯函数供视图与单测共用。
 *
 * 口径：大陆手机号 11 位、1 开头、全数字（02_BACKEND_API.md /auth/send-code）。
 */

export class AuthLogic {
  /** 只留数字，超 max 位截断（输入框 onChange 过滤，iOS 同款） */
  static digitsOnly(raw: string, max: number): string {
    let out = '';
    for (let i = 0; i < raw.length; i++) {
      const ch = raw.charAt(i);
      if (ch >= '0' && ch <= '9') {
        out += ch;
        if (out.length >= max) {
          break;
        }
      }
    }
    return out;
  }

  /** 大陆手机号口径：11 位 && 1 开头 && 全数字 */
  static isValidMainlandPhone(phone: string): boolean {
    if (phone.length !== 11 || !phone.startsWith('1')) {
      return false;
    }
    for (let i = 0; i < phone.length; i++) {
      const ch = phone.charAt(i);
      if (ch < '0' || ch > '9') {
        return false;
      }
    }
    return true;
  }

  /** 掩码展示：138****8000；非 11 位原样返回（iOS `maskedPhone` 同款） */
  static maskedPhone(phone: string): string {
    if (phone.length !== 11) {
      return phone;
    }
    return `${phone.substring(0, 3)}****${phone.substring(7)}`;
  }
}
