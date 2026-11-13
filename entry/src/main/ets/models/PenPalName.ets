/**
 * 用户给自己那位笔友起的名字（对应 iOS `PenPalName.swift`）。
 *
 * 2026-10-24 产品定：**名字只能由用户自己起，不再有默认名**
 * （原来默认「青鸟」，界面上任何地方都不再出现）。
 * - 存在偏好 `penPalName`（AppPrefs.PREF_KEY_PEN_PAL_NAME），默认空串 = 还没起名
 * - 首启必须起名才能进（OnboardingView）；老用户还没起名的，打开 App 时补起一次
 *   （Index 里的 PenPalNamingSheet 层）
 * - 万一哪里还是空的（比如刚从备份恢复），显示和寄信都叫「笔友」——
 *   「笔友」是本地化词条（s_8dcc9a2d73），本模型不碰资源，由调用方传入
 *
 * 纯逻辑、不 import kit，单测覆盖（PenPalName.test.ets）。
 */
export class PenPalName {
  /** 够写一个名字；后端 `pen_pal_name` / `from_character` 是 VARCHAR(32) */
  static readonly MAX_LENGTH: number = 16;

  /** 2026-10-24 之前的默认名。老用户若还是它，当作没起名、请他起一次 —— 代码里只有这里还留着这两个字 */
  private static readonly LEGACY_DEFAULT: string = '青鸟';

  /** 输入中限长（不去空白，只截到上限；iOS onChange 里 `prefix(maxLength)` 同款） */
  static truncated(raw: string): string {
    return raw.length > PenPalName.MAX_LENGTH
      ? raw.slice(0, PenPalName.MAX_LENGTH)
      : raw;
  }

  /** 用户输入整理后的名字（去首尾空白、截到上限）；空串 = 没起 */
  static normalized(raw: string): string {
    return PenPalName.truncated(raw.trim());
  }

  /** 还没起名：空的，或者还是旧的默认名 */
  static needsNaming(stored: string): boolean {
    const name = PenPalName.normalized(stored);
    return name.length === 0 || name === PenPalName.LEGACY_DEFAULT;
  }

  /**
   * 显示、寄信都用这个：没起名时叫「笔友」。
   * `unnamed` = 本地化的「笔友」（s_8dcc9a2d73），调用方用 resourceManager 取好传入
   */
  static display(stored: string, unnamed: string): string {
    return PenPalName.needsNaming(stored)
      ? unnamed
      : PenPalName.normalized(stored);
  }
}
