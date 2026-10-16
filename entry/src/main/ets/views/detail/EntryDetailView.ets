/**
 * 日记详情页（10_BUILD_MANUAL.md 2.3）。对应 iOS `Views/Detail/EntryDetailView.swift`。
 *
 * - 挂在记录 Tab 内的 Navigation 栈里（系统路由表 `router_map.json` 注册
 *   `EntryDetail`）：推入后底部 Tab 栏保留可见——对齐 iOS 在 TabView 的
 *   NavigationStack 里 push 详情页的呈现（2026-10-16 真机需求）
 * - 素笺主题 =「和纸版式」（R-ENTRY-15）：月份大写 + 日期数字前小(28)后大(64)
 *   基线对齐 + 心情印章（R-ENTRY-16：中文界面 + 预设心情 + 显示名 ≤ 2 字）
 *   + 星期 + 此时此地 + 短分割线 + 标题 + 和纸色标签药丸 + 全宽分割线 + 正文；
 *   其余主题普通版式：日期星期 + 心情徽标 + 此时此地 + 标题 + 标签 + 分割线 + 正文
 * - 「补记 N 次」行不渲染：addendumDays 依赖块级时间戳（Ink），2.5 富文本
 *   之前恒为空 —— 与 R-ENTRY-14「没补记过不显示」一致，偏差记 09 Q24
 * - 正文颜色 textPrimary（iOS `RichTextAppearance.textColor`），与写日记页同一套排版；
 *   两种版式都内联在 build() 里（@Builder 参数传值不响应状态刷新，且
 *   `this.entry!` 非空断言被 ArkTS 禁用——build 内的 if 收窄是唯一安全写法）
 * - 右上编辑（push 2.4 编辑页）+ 删除（官方 AlertDialog 确认 + 先媒体后库记录，
 *   R-DATA-07）；从编辑页返回由 Index.onPageShow 广播的 reload tick 驱动重查
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import {
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP
} from '../../services/ImmersiveChrome';
import { AppDatabase } from '../../data/Database';
import { EntryRepository } from '../../data/EntryRepository';
import { STORAGE_KEY_HOME_RELOAD_TICK } from '../../data/HomeLogic';
import { MediaStorageService } from '../../services/MediaStorageService';
import {
  dayAndWeekday,
  isChineseLanguage,
  monthYearUppercased,
  weekdayString,
  dayTens,
  dayOnes
} from '../../services/AppDateFormatters';
import { JournalEntry } from '../../models/JournalEntry';
import { isDefaultMoodKey } from '../../models/Mood';
import { CircleIconButton } from '../compose/CircleIconButton';
import { MoodBadge, moodLabelRes } from '../components/MoodBadge';
import { TagPill } from '../components/TagPill';
import { StampView } from '../components/StampView';
import {
  WeatherLocationBadge,
  weatherBadgeHasContent
} from '../components/WeatherLocationBadge';

const DOMAIN = 0x0000;
const TAG = 'EntryDetailView';

/** 路由页 Index.onPageShow 广播：从编辑页返回后重查（编辑保存 / ✕ 都触发，重查幂等） */
export const STORAGE_KEY_DETAIL_RELOAD_TICK = 'detail.reloadTick';

/** 系统路由表入口（router_map.json → name `EntryDetail`）：Navigation 推入用 */
@Builder
export function EntryDetailBuilder() {
  EntryDetailView()
}

@Component
export struct EntryDetailView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @StorageProp(STORAGE_KEY_DETAIL_RELOAD_TICK) @Watch('onReloadTick')
  reloadTick: number = 0;

  @State entry: JournalEntry | undefined = undefined;

  /** 路由参数：日记 id（onReady 从 NavDestinationContext.pathInfo 取） */
  private entryId: string = '';
  /** 导航栈：onReady 时由 NavDestinationContext 注入真栈 */
  private navPathStack: NavPathStack = new NavPathStack();
  private store: relationalStore.RdbStore | undefined = undefined;

  build() {
    // NavDestination 自定义标题栏：沉浸光感 Button 的官方生效范围（API 26：
    // 其他组件仅在 Navigation/NavDestination 标题栏或底部 TabBar 生效，
    // 《沉浸光感常见问题》）。标题栏自动避让状态栏，无需手动 safeAreaTop。
    NavDestination() {
      if (this.entry !== undefined) {
        Scroll() {
          if (this.theme.id === 'bamboo') {
            // ---- 和纸版式（素笺；用自己的色板，不走 theme token） ----
            Column() {
              // 月份
              Text(monthYearUppercased(new Date(this.entry.date), this.appLanguage))
                .fontSize(11)
                .fontColor('#B8AD9C')
                .letterSpacing(3)
                .padding({ bottom: 4 })

              // 日期大字（前小后大、顶对齐）+ 印章（底对齐）
              Row() {
                Row() {
                  Text(dayTens(new Date(this.entry.date)))
                    .fontSize(28)
                    .fontWeight(300)
                    .fontFamily('serif')
                    .fontColor('#3D3428')
                  Text(dayOnes(new Date(this.entry.date)))
                    .fontSize(64)
                    .fontWeight(300)
                    .fontFamily('serif')
                    .fontColor('#3D3428')
                }
                .alignItems(VerticalAlign.Top)

                Blank()

                // 印章（条件显示，R-ENTRY-16）
                if (this.shouldShowStamp()) {
                  StampView({ moodName: this.moodDisplayName() })
                    .padding({ bottom: 4 })
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Bottom)
              .padding({ bottom: 2 })

              // 星期 + 此时此地
              Row({ space: 8 }) {
                Text(weekdayString(new Date(this.entry.date), this.appLanguage))
                  .fontSize(13)
                  .fontColor('#8B7E6A')
                if (weatherBadgeHasContent(
                  this.entry.weatherCode ?? '', this.entry.weatherInfo ?? '', this.entry.locationInfo ?? '')) {
                  Text('|')
                    .fontSize(10)
                    .fontColor('#D4C9B8')
                  WeatherLocationBadge({
                    weatherCode: this.entry.weatherCode ?? '',
                    weatherInfo: this.entry.weatherInfo ?? '',
                    locationInfo: this.entry.locationInfo ?? '',
                    fontSize: 12,
                    fontColor: '#8B7E6A',
                    iconSize: 10
                  })
                }
              }
              .padding({ bottom: 16 })

              // 短分割线
              Row()
                .width(32)
                .height(1)
                .backgroundColor('#D4C9B8')
                .margin({ bottom: 20 })

              // 标题
              if (this.entry.title.length > 0) {
                Text(this.entry.title)
                  .fontSize(22)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily('serif')
                  .fontColor('#3D3428')
                  .lineHeight(34)
                  .padding({ bottom: 10 })
              }

              // 标签药丸（和纸专用色）
              if (this.entry.tags.length > 0) {
                Row({ space: 6 }) {
                  ForEach(this.entry.tags, (tag: string) => {
                    Text('#' + tag)
                      .fontSize(11)
                      .fontColor('#8B7E6A')
                      .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                      .backgroundColor('#F0EBE1')
                      .borderRadius(12)
                      .border({ width: 0.5, color: '#E0D9CC' })
                  }, (tag: string): string => tag)
                }
                .margin({ bottom: 16 })
              }

              // 心情药丸（印章不显示时才用药丸）
              if (this.entry.mood.length > 0 && !this.shouldShowStamp()) {
                MoodBadge({ name: this.entry.mood, colorHex: this.entry.moodColorHex ?? '' })
                  .margin({ bottom: 16 })
              }

              // 全宽分割线（正文区起点）
              Row()
                .width('100%')
                .height(0.5)
                .backgroundColor(0x80D4C9B8)

              // 正文（与写日记页同一套排版；紧接全宽分割线）
              if (this.entry.content.length > 0) {
                Text(this.entry.content)
                  .fontSize(this.theme.bodyFont.size)
                  .fontWeight(this.theme.bodyFont.weight)
                  .fontFamily(this.theme.bodyFont.family)
                  .fontColor(this.theme.textPrimary)
                  .lineHeight(this.theme.bodyFont.size * 1.43)
                  .padding({ top: 6 })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({
              left: 20,
              right: 20,
              top: 16,
              bottom: this.safeAreaBottomVp + 114
            })
          } else {
            // ---- 普通版式（皮革 / 肯特，iOS defaultLayout） ----
            Column({ space: 16 }) {
              // 日期 + 星期 + 心情
              Row() {
                Text(dayAndWeekday(new Date(this.entry.date), this.appLanguage))
                  .fontSize(this.theme.captionFont.size)
                  .fontWeight(this.theme.captionFont.weight)
                  .fontFamily(this.theme.captionFont.family)
                  .fontColor(this.theme.textTertiary)
                  .letterSpacing(this.theme.letterSpacingWide)
                Blank()
                if (this.entry.mood.length > 0) {
                  MoodBadge({ name: this.entry.mood, colorHex: this.entry.moodColorHex ?? '' })
                }
              }
              .width('100%')

              // 此时此地（写作当时的天气与地点）
              WeatherLocationBadge({
                weatherCode: this.entry.weatherCode ?? '',
                weatherInfo: this.entry.weatherInfo ?? '',
                locationInfo: this.entry.locationInfo ?? '',
                fontSize: this.theme.labelFont.size,
                fontColor: this.theme.textTertiary,
                iconSize: 11
              })

              // 标题
              if (this.entry.title.length > 0) {
                Text(this.entry.title)
                  .fontSize(this.theme.titleFont.size)
                  .fontWeight(this.theme.titleFont.weight)
                  .fontFamily(this.theme.titleFont.family)
                  .fontColor(this.theme.textPrimary)
                  .lineHeight(this.theme.titleFont.size * 1.36)
              }

              // 日记本标签
              if (this.entry.tags.length > 0) {
                Row({ space: 4 }) {
                  ForEach(this.entry.tags, (tag: string) => {
                    TagPill({ name: tag })
                  }, (tag: string): string => tag)
                }
              }

              // 分割线
              Divider()
                .strokeWidth(0.5)
                .color(this.theme.border)

              // 正文（只读；照片 / 录音块在 2.5~2.8 的卡片渲染）
              if (this.entry.content.length > 0) {
                Text(this.entry.content)
                  .fontSize(this.theme.bodyFont.size)
                  .fontWeight(this.theme.bodyFont.weight)
                  .fontFamily(this.theme.bodyFont.family)
                  .fontColor(this.theme.textPrimary)
                  .lineHeight(this.theme.bodyFont.size * 1.43)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({
              left: 20,
              right: 20,
              top: 16,
              bottom: this.safeAreaBottomVp + 114
            })
          }
        }
        .height('100%')
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    // 112vp 大标题区（NavDestinationCustomTitle；builder 必须内联在调用点传
    // this 引用——捕获进字段会丢掉 @Builder 作用域装置，渲染时崩溃
    // 「observeComponentCreation2 is not callable」）
    .title({
      builder: this.topBar,
      height: 112
    })
    // 标题栏坍缩根因（2026-10-16 真机 dump 定位）：全屏窗口下页面布局即窗口
    // 坐标（y0 起），系统状态栏遮挡 [0,122]px。旧 56vp 标题栏内容顶部对齐在
    // y0 → 钻进遮挡区（可见仅 14px 条）；且系统返回键把内容区右移 175px →
    // Row('100%') 右溢出屏幕、删除钮被顶出屏外。修复 = 复刻书写页 NavBar 的
    // 大标题结构：112vp 栏 + 内容下移 56vp（遮挡区之下）+ hideBackButton 改用
    // 自带沉浸光感返回钮（与书写页一致）。
    .hideBackButton(true)
    .backgroundColor(this.theme.background)
    // onReady：取真导航栈 + 路由参数（日记 id）并首查；
    // 之后从编辑页返回由 Index.onPageShow 广播的 reload tick 重查
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      // 边界一次断言：pushPathByName 传的是 string id（HomeView），
      // Record 分支兼容历史路由参数形态
      const raw = ctx.pathInfo.param as Record<string, Object> | string | undefined;
      if (typeof raw === 'string') {
        this.entryId = raw;
      } else if (raw !== undefined) {
        const id = raw['id'];
        if (typeof id === 'string') {
          this.entryId = id;
        }
      }
      const context = this.getUIContext().getHostContext();
      if (context !== undefined && this.entryId.length > 0) {
        this.loadEntry(context);
      }
    })
  }

  /** 顶栏（NavDestination 标题栏内）：左返回、右编辑 + 删除
   * （同分量沉浸光感圆钮；破坏性由图标语义表达） */
  @Builder
  topBar() {
    Row() {
      CircleIconButton({
        iconRes: $r('sys.symbol.chevron_left'),
        iconSize: 14,
        onTap: (): void => {
          this.navPathStack.pop();
        }
      })
      Blank()
      if (this.entry !== undefined) {
        Row({ space: 12 }) {
          CircleIconButton({
            // pencil_line（ID 125831649）在本机运行时表缺资源渲染为空白
            // （2026-10-16 真机像素实测 0%）；square_and_pencil 为早期稳定
            // 资源且设备字体含该字形，iOS「编辑」同语义
            iconRes: $r('sys.symbol.square_and_pencil'),
            iconSize: 14,
            onTap: (): void => {
              this.openEdit();
            }
          })
          CircleIconButton({
            iconRes: $r('sys.symbol.trash'),
            iconSize: 14,
            onTap: (): void => {
              this.showDeleteConfirm();
            }
          })
        }
      }
    }
    .width('100%')
    // 112vp 标题栏内下移 56vp：内容落在 [56,99.5]vp（窗口 y175~311px），
    // 状态栏遮挡区之下，与书写页 NavBar 大标题区内容位置一致
    .margin({ top: 56 })
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  }

  // ---- 印章判定（R-ENTRY-16） ----

  /** 心情印章显示条件：中文界面 + 预设心情 + 显示名 ≤ 2 字 */
  private shouldShowStamp(): boolean {
    const entry = this.entry;
    if (entry === undefined || entry.mood.length === 0) {
      return false;
    }
    if (!isDefaultMoodKey(entry.mood)) {
      return false;
    }
    if (this.moodDisplayName().length > 2) {
      return false;
    }
    return isChineseLanguage(this.appLanguage);
  }

  /** 心情显示名（默认 key 查 mood.* 译文；查不到 / 自定义显示原名） */
  private moodDisplayName(): string {
    const entry = this.entry;
    if (entry === undefined) {
      return '';
    }
    if (isDefaultMoodKey(entry.mood)) {
      const res = moodLabelRes(entry.mood);
      if (res !== undefined) {
        return this.stringFromResource(res);
      }
    }
    return entry.mood;
  }

  // ---- 编辑（2.4） ----

  private openEdit(): void {
    const entry = this.entry;
    if (entry === undefined) {
      return;
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/EditEntry',
      params: { 'id': entry.id } as Record<string, Object>
    });
  }

  // ---- 数据 ----

  private onReloadTick(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined && this.entryId.length > 0) {
      this.loadEntry(context);
    }
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

  // ---- 删除（R-DATA-07） ----

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
   * 成功返回；失败记日志留在页内（本地库删除几乎不失败）。
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
    // pop 返回首页不触发 Index.onPageShow（无路由切换），首页列表不会重查——
    // 主动 bump home tick 让挂载中的 HomeView 立即重查（对齐 iOS @Query 自动响应）
    AppStorage.setOrCreate(STORAGE_KEY_HOME_RELOAD_TICK,
      (AppStorage.get<number>(STORAGE_KEY_HOME_RELOAD_TICK) ?? 0) + 1);
    this.navPathStack.pop();
  }

  private stringFromResource(res: Resource): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    try {
      return context.resourceManager.getStringSync(res.id);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read string resource failed: %{public}s', JSON.stringify(err));
      return '';
    }
  }
}
