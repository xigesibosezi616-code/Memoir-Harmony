/**
 * 每篇日记首页顶部的页眉（10_BUILD_MANUAL.md 3.5，R-READ-03）。
 * 对应 iOS `Reader/DiaryPageHeader.swift`：月份 + 日期大数字（前小后大、底部对齐）
 * + 心情印章 + 星期 + 短分割线 + 标题 + 标签。
 *
 * ⚠️ 版式数字都在 `ReaderHeaderMetrics`（models/ReaderPages），分页器按同一套
 * 数字给首页正文留位置（`estimateHeaderHeight`）—— 改字号 / 间距只动那边，
 * 这里自动跟上；但加了新的一行元素要同步加进估算，否则首页装不下（R-READ-05）。
 */
import { LengthMetrics } from '@kit.ArkUI';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import {
  dayOnes,
  dayTens,
  isChineseLanguage,
  monthYearUppercased,
  weekdayString
} from '../../services/AppDateFormatters';
import { JournalEntry } from '../../models/JournalEntry';
import { isDefaultMoodKey } from '../../models/Mood';
import { moodLabelRes } from '../components/MoodBadge';
import { StampView } from '../components/StampView';
import { ReaderHeaderMetrics } from '../../models/ReaderPages';

@Component
export struct DiaryPageHeaderView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = '';
  entry: JournalEntry = new JournalEntry('', 0, 0, 0);

  /** 心情印章显示条件（R-ENTRY-16 同款：中文界面 + 预设心情 + 显示名 ≤ 2 字） */
  private shouldShowStamp(): boolean {
    if (this.entry.mood.length === 0 || !isDefaultMoodKey(this.entry.mood)) {
      return false;
    }
    if (this.moodDisplayName().length > 2) {
      return false;
    }
    return isChineseLanguage(this.appLanguage);
  }

  /** 心情显示名（默认 key 查 mood.* 译文；自定义显示原名） */
  private moodDisplayName(): string {
    if (isDefaultMoodKey(this.entry.mood)) {
      const res = moodLabelRes(this.entry.mood);
      if (res !== undefined) {
        try {
          const context = this.getUIContext().getHostContext();
          if (context !== undefined) {
            return context.resourceManager.getStringSync(res.id);
          }
        } catch (err) {
          // 译文查询失败显示原名
        }
      }
    }
    return this.entry.mood;
  }

  build() {
    Column() {
      // 月份小字
      Text(monthYearUppercased(new Date(this.entry.date), this.appLanguage))
        .fontSize(ReaderHeaderMetrics.monthFontSize)
        .fontColor(this.theme.textTertiary)
        .letterSpacing(3)
        .margin({ bottom: ReaderHeaderMetrics.monthBottomGap })

      // 日期数字（前小后大、底部对齐）+ 印章
      Row() {
        Row({ space: 1 }) {
          Text(dayTens(new Date(this.entry.date)))
            .fontSize(ReaderHeaderMetrics.dayTensFontSize)
            .fontWeight(300)
            .fontFamily('serif')
            .fontColor(this.theme.textPrimary)
          Text(dayOnes(new Date(this.entry.date)))
            .fontSize(ReaderHeaderMetrics.dayOnesFontSize)
            .fontWeight(300)
            .fontFamily('serif')
            .fontColor(this.theme.textPrimary)
        }
        .alignItems(VerticalAlign.Bottom)

        Blank()

        if (this.shouldShowStamp()) {
          StampView({ moodName: this.moodDisplayName() })
        }
      }
      .alignItems(VerticalAlign.Top)
      .margin({ top: ReaderHeaderMetrics.dayTopGap })

      // 星期
      Text(weekdayString(new Date(this.entry.date), this.appLanguage))
        .fontSize(ReaderHeaderMetrics.weekdayFontSize)
        .fontColor(this.theme.textSecondary)
        .margin({
          top: ReaderHeaderMetrics.weekdayTopGap,
          bottom: ReaderHeaderMetrics.weekdayBottomGap
        })

      // 短分割线
      Column()
        .width(ReaderHeaderMetrics.dividerWidth)
        .height(1)
        .backgroundColor(this.theme.borderAccent)
        .margin({ bottom: ReaderHeaderMetrics.dividerBottomGap })

      // 标题（不截断，最多约三行）
      if (this.entry.title.length > 0) {
        Text(this.entry.title)
          .fontSize(ReaderHeaderMetrics.titleFontSize)
          .fontWeight(FontWeight.Medium)
          .fontFamily('serif')
          .fontColor(this.theme.textPrimary)
          .lineSpacing(LengthMetrics.vp(ReaderHeaderMetrics.titleLineSpacing))
          .margin({ bottom: ReaderHeaderMetrics.titleBottomGap })
      }

      // 标签（单行；溢出裁掉，与 iOS HStack 同款）
      if (this.entry.tags.length > 0) {
        Row({ space: 6 }) {
          ForEach(this.entry.tags, (tag: string) => {
            Text(`#${tag}`)
              .fontSize(ReaderHeaderMetrics.tagFontSize)
              .fontColor(this.theme.textSecondary)
              .padding({
                left: 10,
                right: 10,
                top: ReaderHeaderMetrics.tagVerticalPadding,
                bottom: ReaderHeaderMetrics.tagVerticalPadding
              })
              .backgroundColor(this.theme.accentBackground)
              .borderRadius(12)
          }, (tag: string): string => tag)
        }
        .clip(true)
      }
    }
    .alignItems(HorizontalAlign.Start)
  }
}
