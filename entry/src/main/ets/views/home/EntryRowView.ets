/**
 * 记录页列表卡（10_BUILD_MANUAL.md 2.2，R-HOME-03）。对应 iOS
 * `Views/Home/EntryRowView.swift` 的信息层级：日期 + 星期、心情徽标、
 * 标题（单行）、正文摘要、日记本标签。
 * 统一标准大小 + 四行四角排版（2026-10-19 用户拍板）：固定卡高 118vp，
 * 行 1 日期星期（左上角）+ 心情徽标（右上角，与日期同行靠右）；
 * 行 2 标题（heading，单行，无标题卡用正文摘要当标题——备忘录同款：
 * 首行即标题）；行 3 正文摘要（单行，有独立标题才显示防重复）；
 * 行 4 日记本胶囊 ≤3（左下角，只放分类）+ 天气·定位（右下角，2.10）。
 * 卡色与页面同纸色（theme.listCardBackground，融入一体）+ 16vp 圆角 +
 * 0.5 描边 + 柔影成型；色差浮卡（白卡/暖象牙卡）与标签独立行、高度
 * 不齐均为历史方案。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { dayAndWeekday } from '../../services/AppDateFormatters';
import { JournalEntry } from '../../models/JournalEntry';
import { MoodBadge } from '../components/MoodBadge';
import { TagPill } from '../components/TagPill';
import { WeatherLocationBadge } from '../components/WeatherLocationBadge';

@Component
export struct EntryRowView {
  /** 点卡进详情（R-HOME 列表交互）：导航由父组件决定，这里只回调 */
  onTap: () => void = (): void => {};
  @Prop entry: JournalEntry = new JournalEntry('', Date.now(), Date.now(), Date.now());
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';

  /** 正文摘要截断长度（与 iOS `entry.content.prefix(60)` 一致） */
  private static readonly previewLimit: number = 60;

  /** 统一标准卡高：行 1 含心情徽标时最高（~22）+ 标题 21 + 摘要 16
   * + 胶囊 22 + 3×3 间距 + 24 上下内边距 ≈ 112，定 118 留余量防
   * Blank 被挤成负值溢出卡底（Blank 沉底吸收余量） */
  private static readonly cardHeightVp: number = 118;

  build() {
    // 行距用显式 margin 不用 Column space：Blank 的剩余空间计算不含
    // space 间距，space+Blank 组合会让底角行恒溢出底内边距 3×space
    // （真机实测 #生活 胶囊距卡底仅 9px）
    Column() {
      // 行 1（顶角）：日期星期（左上）+ 心情徽标（右上角，与日期同行）
      Row() {
        Text(dayAndWeekday(new Date(this.entry.date), this.appLanguage))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textTertiary)
        if (this.entry.mood.length > 0) {
          MoodBadge({ name: this.entry.mood, colorHex: this.entry.moodColorHex ?? '' })
        }
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .margin({ bottom: 3 })

      // 行 2：标题（heading，单行截断）。无标题卡用正文摘要当标题
      // （备忘录同款行为：首行即标题），恒渲染保四行结构不塌
      Text(this.titleLineText())
        .fontSize(this.theme.headingFont.size)
        .fontWeight(this.theme.headingFont.weight)
        .fontFamily(this.theme.headingFont.family)
        .fontColor(this.theme.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ bottom: 3 })

      // 行 3：正文摘要（单行）。有独立标题才显示——无标题卡正文已上移
      // 当标题，不重复
      if (this.titlePresent() && this.contentPreview().length > 0) {
        Text(this.contentPreview())
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ bottom: 3 })
      }

      // 弹性占位：底角行压到卡底（四角定位）
      Blank()

      // 行 4（底角）：日记本胶囊 ≤3（左下角，只放分类，心情已移右上角）；
      // 天气·定位（右下角，2.10 此时此地——无内容时徽标自身渲染为空不占位）
      Row({ space: 6 }) {
        ForEach(this.entry.tags.slice(0, 3), (tag: string) => {
          TagPill({ name: tag })
        }, (tag: string): string => tag)
        Blank()
        WeatherLocationBadge({
          weatherCode: this.entry.weatherCode ?? '',
          weatherInfo: this.entry.weatherInfo ?? '',
          locationInfo: this.entry.locationInfo ?? '',
          fontSize: 10,
          iconSize: 9,
          fontColor: this.theme.textTertiary
        })
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    // 左右 16（备忘录规格）；上下 12（112vp 内四行 + 行距 ≈ 106，
    // 余量 Blank 吸收沉底）
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .height(EntryRowView.cardHeightVp)
    .backgroundColor(this.theme.listCardBackground)
    .borderRadius(16)
    // 卡色与页面同纸色（融入一体）：0.5 描边 + 柔影成型，不靠色差浮卡
    .border({ width: 0.5, color: this.theme.border })
    .shadow(this.theme.listCardShadow)
    .width('100%')
    .onClick((): void => {
      // 点卡进详情（R-HOME 列表交互，2.3 详情页）
      this.onTap();
    })
  }

  /** 行 2 标题：有标题用标题；无标题用正文摘要（备忘录：首行即标题） */
  private titleLineText(): string {
    if (this.titlePresent()) {
      return this.entry.title;
    }
    return this.contentPreview();
  }

  /** 有没有独立标题（决定行 3 是否重复显示摘要） */
  private titlePresent(): boolean {
    return this.entry.title.length > 0;
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
