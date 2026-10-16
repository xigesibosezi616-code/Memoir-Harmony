/**
 * 主题 token 接口（10_BUILD_MANUAL.md 1.1）。
 *
 * 对应 iOS `Theme/AppTheme.swift`。三套主题全部实现这个接口；
 * **所有成员一律必填** —— 新增 token 或新增主题时漏配，编译直接报错
 * （R-THEME-02：邮筒插画、启动封面、桌面图标三样缺一不可）。
 *
 * 页面里不写死任何色值：颜色、字体一律从主题 token 取（CLAUDE.md 架构约定）。
 */
export interface AppTheme {
  /** 主题英文 id：`bamboo` / `leather` / `kent`（R-THEME-01） */
  id: string;

  /** 主题显示名（资源引用：「素笺」「皮革」「肯特」） */
  nameRes: Resource;

  // ---- 背景层（4）----
  /** 主背景 */
  background: ResourceColor;
  /** 卡片背景 */
  cardBackground: ResourceColor;
  /** 次要背景（浮层、输入区） */
  surfaceBackground: ResourceColor;
  /** 侧栏 / 底栏背景 */
  sidebarBackground: ResourceColor;

  // ---- 文字（3）----
  /** 主文字 */
  textPrimary: ResourceColor;
  /** 次文字 */
  textSecondary: ResourceColor;
  /** 辅助文字 */
  textTertiary: ResourceColor;

  // ---- 边框（2）----
  /** 普通边框 */
  border: ResourceColor;
  /** 强调边框 */
  borderAccent: ResourceColor;

  // ---- 玻璃按钮（2）----
  /**
   * 玻璃质感按钮底色（半透明，配合 0.5vp 玻璃边框模拟 iOS 26 `.glass`）。
   * 沉浸光感系统材质按官方限制仅标题栏/底部 TabBar 生效，内容区按钮
   * （写日记页返回/完成）只能用主题化半透明底 + 细边框实现玻璃分量。
   * 每主题单独调：与页面背景拉开一档明度差（2026-10-15 真机反馈「看不清」）。
   */
  glassBackground: ResourceColor;
  /** 玻璃按钮边框（半透明，比普通 border 清晰一档） */
  glassBorder: ResourceColor;

  // ---- 列表卡片（2）----
  /**
   * 记录页列表卡底色：华为备忘录式实色卡（2026-10-16 真机实测规格：
   * 页边距 16vp、卡距 12vp、圆角 ~16vp、卡内边距 12~16vp）。浅色主题
   * 卡比页面底亮一档成型（素笺纯白卡浮米白底、肯特白卡靠投影成型），
   * 深色皮革卡比页面底亮一档（深色下投影不可见，靠明度差成型）
   */
  listCardBackground: ResourceColor;
  /** 列表卡投影（皮革 radius 0 无影——深底上投影不可见） */
  listCardShadow: ShadowOptions;

  // ---- 强调色（2）----
  /** 主色（按钮 / 链接） */
  accent: ResourceColor;
  /** 主色背景 */
  accentBackground: ResourceColor;

  // ---- 心情标签（3）----
  /** 心情标签底色 */
  moodBackground: ResourceColor;
  /** 心情标签边框 */
  moodBorder: ResourceColor;
  /** 心情标签文字 */
  moodText: ResourceColor;

  // ---- 危险色 ----
  /** 删除 / 错误。整个主题仅这一处用红（04_DESIGN_LANGUAGE.md） */
  destructive: ResourceColor;

  // ---- 系统明暗（必填；值表达浅色）----
  /**
   * 这个主题要求 App 整体走哪种系统明暗（R-THEME-03）：
   * - `'dark'`：应用级切系统深色（底栏材质、键盘、状态栏全跟上）
   * - `'unset'`：应用级切系统浅色（浅色主题必须显式浅色——跟随系统时
   *   系统深色模式会让系统玻璃按深色渲染，浅色页面上 tab bar 下方发灰）
   * 深色主题必须显式写 `'dark'`，浅色主题写 `'unset'` —— 漏配编译报错。
   */
  colorMode: 'dark' | 'unset';

  // ---- 插画（必填）----
  /** 邮筒页的邮筒插画。每个主题必须配一个（R-THEME-02） */
  mailboxImage: Resource;

  // ---- 字体（Q6 字体授权未定：衬线先统一用系统 serif 族占位，定了只改这里）----

  /** 页面标题、写日记标题：Georgia 22 */
  titleFont: FontInfo;
  /** 列表标题、按钮：Georgia 18 */
  headingFont: FontInfo;
  /** 列表摘要等正文：Georgia 14 */
  bodyFont: FontInfo;
  /** 日期、小标签：系统 12 */
  captionFont: FontInfo;
  /** 极小说明：系统 10 */
  labelFont: FontInfo;

  /** 正文行距（vp） */
  bodyLineSpacing: number;
  /** 宽字距（fp）。素笺 / 皮革 3，肯特 2 */
  letterSpacingWide: number;
}

/**
 * 字体 token。鸿蒙没有 SwiftUI 的 `Font` 复合类型，
 * 用 size（fp）+ weight + family 三元组表达，页面里交给 `.fontSize()/.fontWeight()/.fontFamily()`。
 */
export class FontInfo {
  readonly size: number;
  readonly weight: FontWeight;
  /** `''` = 系统默认（HarmonyOS Sans）；`'serif'` = 系统衬线占位（Q6 未定） */
  readonly family: string;

  constructor(size: number, weight: FontWeight, family: string) {
    this.size = size;
    this.weight = weight;
    this.family = family;
  }
}
