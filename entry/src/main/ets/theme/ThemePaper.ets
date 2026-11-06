/**
 * 一张主题背后的那张纸 —— 名字、副标题、介绍正文、史料出处（6.2）。
 * 对应 iOS `Theme/ThemePaper.swift`。
 *
 * 主题选择页从「选一个配色」改成「挑一种纸」：点主题不再立刻生效，先弹介绍，
 * 用户每次换主题都会读到一段真实的纸史。**这是产品的文化表达，不是装饰性文案**，
 * 正文按阅读体验排版（行距放宽），不要当成 UI 提示文字处理。
 *
 * - `id` 与 ThemeManager 存偏好的值同一套（R-THEME-01）
 * - 文案全部走翻译词条（iOS 译文七语已导入，不改写）
 * - 列表色块的颜色 = 各主题的 background / accent（iOS ThemeSwatch 同值）
 * - `iconPreviewRes`：对应桌面图标的预览图（U09 R-THEME-13 手写 m.，192×192 方图不带圆角）
 */
export class ThemePaper {
  /** 与 ThemeManager.currentThemeId 同一套值，不随显示名变化 */
  readonly id: string;
  readonly nameRes: Resource;
  /** 列表页副标题。允许两行，不要截断成省略号 */
  readonly subtitleRes: Resource;
  /** 介绍弹窗的正文 */
  readonly storyRes: Resource;
  /** 史料出处，弹窗里默认收起 */
  readonly sourceRes: Resource;
  /** 对应桌面图标的预览图（介绍弹窗里让用户理解「图标也会跟着变」的关键视觉，不能省） */
  readonly iconPreviewRes: Resource;

  constructor(id: string, nameRes: Resource, subtitleRes: Resource,
    storyRes: Resource, sourceRes: Resource, iconPreviewRes: Resource) {
    this.id = id;
    this.nameRes = nameRes;
    this.subtitleRes = subtitleRes;
    this.storyRes = storyRes;
    this.sourceRes = sourceRes;
    this.iconPreviewRes = iconPreviewRes;
  }

  static readonly all: ThemePaper[] = [
    new ThemePaper('bamboo',
      $r('app.string.s_abafd65e30'), $r('app.string.s_3fb4374f11'),
      $r('app.string.s_1b0adeee54'), $r('app.string.s_5720afd3c4'),
      $r('app.media.app_icon_preview_bamboo')),
    new ThemePaper('leather',
      $r('app.string.s_b416882c45'), $r('app.string.s_6b16103d80'),
      $r('app.string.s_ec7e3bcb5d'), $r('app.string.s_55406b4cd3'),
      $r('app.media.app_icon_preview_leather')),
    new ThemePaper('kent',
      $r('app.string.s_7ebd4ae074'), $r('app.string.s_8803176f5e'),
      $r('app.string.s_4c67117f26'), $r('app.string.s_00360964eb'),
      $r('app.media.app_icon_preview_kent')),
    new ThemePaper('polar',
      $r('app.string.s_1bb8716350'), $r('app.string.s_a9c3c6683b'),
      $r('app.string.s_d51054a2b4'), $r('app.string.s_974bfbcc56'),
      $r('app.media.app_icon_preview_polar'))
  ];
}
