/**
 * 导航栏 / 浮层上的圆形图标按钮（10_BUILD_MANUAL.md 2.1）。
 * 对应 iOS `Views/Components/CircleIconButton.swift` 的 glass 分量
 * （写日记页的返回与完成、详情页的编辑与删除、编辑页的 ✕ 与 ✓ 都用它：
 * 次级操作，半透明不抢视线）。
 *
 * 鸿蒙对应物 = **沉浸光感系统材质**（官方《组件适配沉浸光感》Button 白名单：
 * 组件级 systemMaterial）。官方文档研究结论（API 26）：
 * - 材质配置：THIN（悬浮钮建议薄材质）+ interactive 交互形变
 *   + lightEffect 点光源（开启后按压/悬浮态由光感反馈替代，官方说明）。
 * - **必须设置 backgroundColor 透明底**：《组件适配沉浸光感》明确——
 *   「配置沉浸光感但未设置 buttonStyle、backgroundColor 等颜色相关属性
 *   且未设置材质颜色时，默认生效 Button 主题色的材质样式」（真机实测
 *   为系统蓝）。设置透明底即破除该默认，得到中性玻璃材质。
 * - 生效范围（官方三处文档一致）：Button 属其他组件，仅在
 *   Navigation/NavDestination 标题栏或底部 TabBar 生效——因此宿主页面
 *   顶栏一律经 Navigation().title() 自定义标题栏渲染（本组件全部使用方
 *   均已迁移）；范围内 THIN 玻璃材质真实渲染，日志无 Material inactive。
 *
 * 🔴 与 iOS 同款教训：**不要给主行动画实心圆底** —— 写日记页的主行动是「写」，
 * 不是「完成」，✓ 与返回同一种分量，能不能点由 disabled 表达（iOS 注释原话）。
 */
import { uiMaterial } from '@kit.ArkUI';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

@Component
export struct CircleIconButton {
  /** sys.symbol 图标资源 */
  iconRes: Resource = $r('sys.symbol.chevron_left');
  /** 图标字号（fp） */
  iconSize: number = 15;
  /** 能不能点；禁用态换 textTertiary 色表达（iOS `toolbarIcon` 同款，不降透明度）。
   * @Prop 单向同步：父组件状态变化（如正文从空到有字）会实时更新，
   * 普通成员只在建组件时赋一次值，✓ 会永远停在进页面时的禁用态。
   * 不叫 enabled：与通用属性 enabled 撞名会报 10505001 */
  @Prop pressEnabled: boolean = true;
  onTap: () => void = (): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph(this.iconRes)
        .fontSize(this.iconSize)
        .fontWeight(FontWeight.Medium)
        // 2026-10-16 三主题可读性实测调优：图标用 textPrimary 而非 iOS 的
        // textSecondary——iOS 是裸图标直接压在页面底色上；本组件多了一层
        // 玻璃圆片（materialColor 赋色后的局部底色），皮革主题金片
        // (86,73,57) 与 textSecondary(138,123,106) 同调，对比仅 2.1:1，
        // 图标融进玻璃片；升 textPrimary 后 素笺 9.9 / 肯特 13.9 / 皮革 5.1
        .fontColor([this.pressEnabled ? this.theme.textPrimary : this.theme.textTertiary])
    }
    .width(32)
    .height(32)
    .padding(0)
    .borderRadius(16)
    // 透明底：破除「Button 主题色材质样式」默认渲染（官方组件适配文档）；
    // 材质在生效范围内时背景会被材质接管，范围外呈透明底图标钮
    .backgroundColor(Color.Transparent)
    // 沉浸光感系统材质：THIN 薄材质 + 交互形变 + 白色点光源 + 主题赋色。
    // lightEffect 开启后按压/悬浮态由光感交互反馈替代（官方说明）。
    // materialColor 用主题玻璃色（官方《沉浸光感视觉》「为材质赋色」）：
    // THIN 纯玻璃在素笺/肯特浅底上 Δ≈1 不可见（2026-10-16 真机实测），
    // 混入各主题 glassBackground（半透明暖灰/浅灰）后按钮在浅色底上
    // 也能成型；深色皮革下金调赋色同为正向增益。
    // 禁用态 materialColor 透明（纯 THIN 玻璃，视觉上≈裸图标）——对齐 iOS：
    // 禁用只是「不可点的淡图标」，不该是「可点的玻璃片变淡」；且玻璃片
    // 抬亮局部底色会把 textTertiary 吃到 1.7:1（皮革实测），裸图标保持 3.5:1
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      interactive: true,
      materialColor: this.pressEnabled ? this.theme.glassBackground : Color.Transparent,
      lightEffect: { color: Color.White }
    }))
    // 禁用态不降透明度（iOS 同款只用 textTertiary 换色表达）：0.35 透明度
    // 会把图标+玻璃片一起弱化到近隐形（真机实测禁用 ✓ 无可见度）
    .onClick((): void => {
      if (this.pressEnabled) {
        this.onTap();
      }
    })
  }
}
