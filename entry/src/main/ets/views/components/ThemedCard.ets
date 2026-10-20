/**
 * 主题卡片容器（10_BUILD_MANUAL.md 2.2 起多处复用）。
 * 对应 iOS `Views/Components/ThemedCard.swift`：内容 + 16 内边距 +
 * cardBackground + 12 圆角 + 0.5 边框。内容用 @BuilderParam 尾随闭包传入。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

@Component
export struct ThemedCard {
  @BuilderParam content: () => void = emptyCardContent;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  /** 可选卡高下限（vp）：空态卡等需要与标准卡（118vp）同款高度时传入；
   * 默认 undefined = 内容自适应（原行为不变） */
  minHeightVp?: number = undefined;

  build() {
    Column() {
      this.content()
    }
    .padding(16)
    .backgroundColor(this.theme.cardBackground)
    .borderRadius(12)
    .border({ width: 0.5, color: this.theme.border })
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ minHeight: this.minHeightVp })
  }
}

@Builder
function emptyCardContent() {
}
