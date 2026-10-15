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

  build() {
    Column() {
      this.content()
    }
    .padding(16)
    .backgroundColor(this.theme.cardBackground)
    .borderRadius(12)
    .border({ width: 0.5, color: this.theme.border })
    .alignItems(HorizontalAlign.Start)
  }
}

@Builder
function emptyCardContent() {
}
