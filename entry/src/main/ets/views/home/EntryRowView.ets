/**
 * 记录页列表卡（10_BUILD_MANUAL.md 2.2，R-HOME-03）。对应 iOS
 * `Views/Home/EntryRowView.swift` 的信息层级：日期 + 星期、心情徽标、
 * 标题（单行）、正文摘要、日记本标签。
 * 排版按华为备忘录卡片式（2026-10-16 真机实测规格）：实色卡
 * （theme.listCardBackground）+ 16vp 圆角 + 柔影，两级文字层次——
 * 行 1 标题（heading）+ 心情徽标（右侧），行 2 日期星期 · 摘要（单行），
 * 行 3 标签 ≤3。此前线式（divider 分隔）与近透明玻璃卡（真机显示异常
 * 已回退）均为历史方案；此时此地徽标 v1 还没有数据（天气 / 地点在
 * 2.5/2.6），结构暂不渲染。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { dayAndWeekday } from '../../services/AppDateFormatters';
import { JournalEntry } from '../../models/JournalEntry';
import { MoodBadge } from '../components/MoodBadge';
import { TagPill } from '../components/TagPill';

@Component
export struct EntryRowView {
  /** 点卡进详情（R-HOME 列表交互）：导航由父组件决定，这里只回调 */
  onTap: () => void = (): void => {};
  @Prop entry: JournalEntry = new JournalEntry('', Date.now(), Date.now(), Date.now());
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';

  /** 正文摘要截断长度（与 iOS `entry.content.prefix(60)` 一致） */
  private static readonly previewLimit: number = 60;

  build() {
    Column({ space: 8 }) {
      // 行 1：标题（单行截断）+ 心情徽标（右侧，备忘录「彩色分类图标」位）
      if (this.entry.title.length > 0 || this.entry.mood.length > 0) {
        Row({ space: 8 }) {
          if (this.entry.title.length > 0) {
            Text(this.entry.title)
              .fontSize(this.theme.headingFont.size)
              .fontWeight(this.theme.headingFont.weight)
              .fontFamily(this.theme.headingFont.family)
              .fontColor(this.theme.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          if (this.entry.mood.length > 0) {
            MoodBadge({ name: this.entry.mood, colorHex: this.entry.moodColorHex ?? '' })
          }
        }
        .width('100%')
      }

      // 行 2：日期星期 · 摘要（备忘录式单行 meta）
      Row({ space: 6 }) {
        Text(dayAndWeekday(new Date(this.entry.date), this.appLanguage))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textTertiary)
        Text(this.contentPreview())
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')

      // 行 3：标签在左（最多 3 个，与 iOS prefix(3) 一致）
      if (this.entry.tags.length > 0) {
        Row({ space: 4 }) {
          ForEach(this.entry.tags.slice(0, 3), (tag: string) => {
            TagPill({ name: tag })
          }, (tag: string): string => tag)
        }
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    // 备忘录卡片规格（真机实测）：左右/上下 14~16 内边距
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(this.theme.listCardBackground)
    .borderRadius(16)
    .shadow(this.theme.listCardShadow)
    .width('100%')
    .onClick((): void => {
      // 点卡进详情（R-HOME 列表交互，2.3 详情页）
      this.onTap();
    })
  }

  /** 正文前 60 字 + 超出补省略号（iOS `prefix(60)` 同款） */
  private contentPreview(): string {
    const content = this.entry.content;
    if (content.length > EntryRowView.previewLimit) {
      return content.substring(0, EntryRowView.previewLimit) + '...';
    }
    return content;
  }
}
