/**
 * 日记本标签小胶囊（10_BUILD_MANUAL.md 2.2 记录页列表行）。
 * 对应 iOS `Views/Components/TagPill.swift`：`#名字` + surfaceBackground 底。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

@Component
export struct TagPill {
  name: string = '';
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Text('#' + this.name)
      .fontSize(this.theme.captionFont.size)
      .fontWeight(this.theme.captionFont.weight)
      .fontFamily(this.theme.captionFont.family)
      .fontColor(this.theme.textSecondary)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(this.theme.surfaceBackground)
      .borderRadius(12)
  }
}
