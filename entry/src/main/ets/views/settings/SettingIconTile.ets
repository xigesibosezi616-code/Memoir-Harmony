/**
 * 设置一级页行图标底座（10_BUILD_MANUAL.md 6.1；用户指令 2026-11-05：
 * 设置页 UI 参考华为手机设置页）。
 *
 * 华为系统设置页特征：每行左侧彩色圆角方块底座 + 白色官方 sys.symbol 图标。
 * 底座色按行固定（外观蓝/日记绿/笔友橙/位置青/语言紫/数据橙红/统计玫红/评分金/关于灰），
 * 不随主题换——华为同款（系统设置彩色底座三主题不变）。
 * 图标一律官方 sys.symbol（名称经资源表 ∩ 字体验证）。
 */

@Component
export struct SettingIconTile {
  /** 官方 sys.symbol 图标资源 */
  @Prop icon: Resource = $r('sys.symbol.info_circle');
  /** 底座色（华为风格固定彩色） */
  @Prop tileColor: ResourceColor = 0xFF8E8E93;

  build() {
    Stack() {
      SymbolGlyph(this.icon)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor([Color.White])
    }
    .width(28)
    .height(28)
    .borderRadius(8)
    .backgroundColor(this.tileColor)
  }
}
