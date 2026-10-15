/**
 * 导航栏 / 浮层上的圆形图标按钮（10_BUILD_MANUAL.md 2.1）。
 * 对应 iOS `Views/Components/CircleIconButton.swift` 的 glass 分量
 * （写日记页的返回与完成都用它：次级操作，半透明不抢视线）。
 *
 * 🔴 与 iOS 同款教训：**不要给主行动画实心圆底** —— 写日记页的主行动是「写」，
 * 不是「完成」，✓ 与返回同一种分量，能不能点由 disabled 表达（iOS 注释原话）。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

@Component
export struct CircleIconButton {
  /** sys.symbol 图标资源 */
  iconRes: Resource = $r('sys.symbol.chevron_left');
  /** 图标字号（fp） */
  iconSize: number = 15;
  /** 能不能点；禁用态只降透明度不换色系（iOS `toolbarIcon` 同款）。
   * @Prop 单向同步：父组件状态变化（如正文从空到有字）会实时更新，
   * 普通成员只在建组件时赋一次值，✓ 会永远停在进页面时的禁用态。
   * 不叫 enabled：与通用属性 enabled 撞名会报 10505001 */
  @Prop pressEnabled: boolean = true;
  onTap: () => void = (): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Stack() {
      SymbolGlyph(this.iconRes)
        .fontSize(this.iconSize)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.pressEnabled ? this.theme.textSecondary : this.theme.textTertiary])
    }
    .width(32)
    .height(32)
    .borderRadius(16)
    // 玻璃分量：主题化半透明底 + 0.5vp 玻璃边框（iOS 26 `.glass` 对应物）。
    // 沉浸光感系统材质按官方限制仅标题栏/底部 TabBar 生效，内容区按钮
    // 不能走 systemMaterial，只能主题 token 玻璃化（每主题单独配色）
    .backgroundColor(this.theme.glassBackground)
    .border({ width: 1, color: this.theme.glassBorder })
    .opacity(this.pressEnabled ? 1 : 0.35)
    .onClick((): void => {
      if (this.pressEnabled) {
        this.onTap();
      }
    })
  }
}
