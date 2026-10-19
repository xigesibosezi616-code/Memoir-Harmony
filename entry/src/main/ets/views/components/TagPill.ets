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
      // 0.5 细描边：胶囊色与列表卡色接近时靠边框成型（2026-10-19
      // 卡色随主题后补，肯特 F8F8F8 胶囊对 F7F7F7 卡仅 Δ1）
      .border({ width: 0.5, color: this.theme.border })
  }
}
