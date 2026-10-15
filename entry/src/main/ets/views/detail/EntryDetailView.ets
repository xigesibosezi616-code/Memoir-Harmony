/**
 * 日记详情页 v1（10_BUILD_MANUAL.md 2.3 最小版）。对应 iOS
 * `Views/Detail/EntryDetailView.swift` 的只读骨架。
 *
 * - 素笺「和纸版式」、此时此地、补记、右上编辑是完整 2.3 / 2.4 / 2.10
 *   的卡片，本版不做；只做：只读展示 + 删除（确认弹窗 + 媒体清理）
 * - 删除：先 `deleteEntryMedia`（照片三件套 + 录音）再删库记录
 *   （05 §2 顺序，R-DATA-07），返回后主页刷新由 Index.onPageShow 的
 *   reload tick 驱动（与保存链路同一条）
 * - 删除按钮与返回同分量（CircleIconButton 玻璃圆钮），破坏性用
 *   destructive 图标色表达；确认弹窗用官方 AlertDialog（操作确认类
 *   弹出框，华为备忘录删除确认同款组件：居中标题 + 正文 + 底部双按钮）
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import {
  STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP
} from '../../services/ImmersiveChrome';
import { AppDatabase } from '../../data/Database';
import { EntryRepository } from '../../data/EntryRepository';
import { MediaStorageService } from '../../services/MediaStorageService';
import { dayAndWeekday } from '../../services/AppDateFormatters';
import { JournalEntry } from '../../models/JournalEntry';
import { CircleIconButton } from '../compose/CircleIconButton';
import { MoodBadge } from '../components/MoodBadge';
import { TagPill } from '../components/TagPill';

const DOMAIN = 0x0000;
const TAG = 'EntryDetailView';

@Component
export struct EntryDetailView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  @State entry: JournalEntry | undefined = undefined;

  /** 路由参数：日记 id（aboutToAppear 从 router params 取） */
  private entryId: string = '';
  private store: relationalStore.RdbStore | undefined = undefined;

  aboutToAppear(): void {
    const raw = this.getUIContext().getRouter().getParams();
    if (raw !== undefined) {
      const params = raw as Record<string, Object>;
      const id = params['id'];
      if (typeof id === 'string') {
        this.entryId = id;
      }
    }
    const context = this.getUIContext().getHostContext();
    if (context !== undefined && this.entryId.length > 0) {
      this.loadEntry(context);
    }
  }

  build() {
    Column() {
      // 顶栏：左返回、右删除（同分量玻璃圆钮；破坏性由图标色表达）
      Row() {
        CircleIconButton({
          iconRes: $r('sys.symbol.chevron_left'),
          iconSize: 14,
          onTap: (): void => {
            this.getUIContext().getRouter().back();
          }
        })
        Blank()
        if (this.entry !== undefined) {
          CircleIconButton({
            iconRes: $r('sys.symbol.trash'),
            iconSize: 14,
            onTap: (): void => {
              this.showDeleteConfirm();
            }
          })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: this.safeAreaTopVp + 6, bottom: 6 })

      if (this.entry !== undefined) {
        Scroll() {
          Column({ space: 12 }) {
            // 日期 + 星期 + 心情（信息层级与列表行一致）
            Row() {
              Text(dayAndWeekday(new Date(this.entry.date), this.appLanguage))
                .fontSize(this.theme.captionFont.size)
                .fontWeight(this.theme.captionFont.weight)
                .fontFamily(this.theme.captionFont.family)
                .fontColor(this.theme.textTertiary)
              Blank()
              if (this.entry.mood.length > 0) {
                MoodBadge({ name: this.entry.mood, colorHex: this.entry.moodColorHex ?? '' })
              }
            }
            .width('100%')

            if (this.entry.title.length > 0) {
              Text(this.entry.title)
                .fontSize(this.theme.titleFont.size)
                .fontWeight(this.theme.titleFont.weight)
                .fontFamily(this.theme.titleFont.family)
                .fontColor(this.theme.textPrimary)
                .lineHeight(this.theme.titleFont.size * 1.36)
            }

            // 正文只读（v1 纯文本；照片 / 录音块在 2.5~2.7 的卡片渲染）
            if (this.entry.content.length > 0) {
              Text(this.entry.content)
                .fontSize(this.theme.bodyFont.size)
                .fontWeight(this.theme.bodyFont.weight)
                .fontFamily(this.theme.bodyFont.family)
                .fontColor(this.theme.textSecondary)
                .lineHeight(this.theme.bodyFont.size * 1.43)
            }

            // 日记本标签（与列表行同款，最多 3 个）
            if (this.entry.tags.length > 0) {
              Row({ space: 4 }) {
                ForEach(this.entry.tags.slice(0, 3), (tag: string) => {
                  TagPill({ name: tag })
                }, (tag: string): string => tag)
              }
              .padding({ top: 8 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({
            left: 20,
            right: 20,
            top: 16,
            bottom: this.safeAreaBottomVp + 24
          })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }

  private async loadEntry(context: common.Context): Promise<void> {
    try {
      const store = await AppDatabase.open(context);
      this.store = store;
      const loaded = await EntryRepository.fetchEntryById(store, this.entryId);
      this.entry = loaded ?? undefined;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadEntry failed id=%{public}s: %{public}s', this.entryId, JSON.stringify(err));
    }
  }

  /**
   * 删除确认：官方 AlertDialog（操作确认类弹出框，华为备忘录删除同款；
   * 居中标题/正文 + 底部双按钮，系统自动深浅色背板与圆角 32vp）。
   */
  private showDeleteConfirm(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.s_215574245b'),
      message: $r('app.string.s_502b05fb33'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.s_4d0b4688c7'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.s_3755f56f2f'),
        fontColor: this.theme.destructive,
        action: (): void => {
          this.deleteEntryAndClose();
        }
      }
    });
  }

  /**
   * 删除：先媒体（deleteEntryMedia，照片三件套 + 录音）后库记录（05 §2），
   * 成功返回；失败只记日志留在页内（本地库删除几乎不失败，错误提示
   * 链路随完整 2.3 卡片再接）。
   */
  private async deleteEntryAndClose(): Promise<void> {
    const store = this.store;
    const entry = this.entry;
    if (store === undefined || entry === undefined) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext();
      if (context !== undefined) {
        MediaStorageService.create(context, store).deleteEntryMedia(entry);
      }
      await EntryRepository.deleteEntry(store, entry.id);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'delete entry failed id=%{public}s: %{public}s', entry.id, JSON.stringify(err));
      return;
    }
    this.getUIContext().getRouter().back();
  }
}
