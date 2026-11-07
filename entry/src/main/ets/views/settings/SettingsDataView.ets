/**
 * 设置 →「数据与备份」二级页（10_BUILD_MANUAL.md 6.1）。对应 iOS `SettingsDataView.swift`。
 *
 * - 云同步行：🔴 R-DATA-05——**不许拿「系统登了云账号」当「数据已同步」**。
 *   端云同步是 6.6 的事（Q3 结论：华为端云数据同步，AGC 云侧容器是前置），
 *   落地前这里**如实**展示「未开启」+ 红字警告「日记只在这台设备上」并引导导出备份；
 *   6.6 接上后同步状态只认真实的同步成功事件
 * - 导出 / 导入备份：行先立（6.5 / 6.4 接路由），分组结构与文案一次到位
 * - 同步 Live Photo 视频不做（Q10 死设置）
 * - 照片与录音占用（R-DATA-08）：扫盘统计（usage()），值未回来显示「统计中…」
 * - 清理残留文件：只在扫出孤儿时出现（s_3ae6d0bf40「清理 %d 个残留文件」）；
 *   确认走官方 AlertDialog（iOS confirmationDialog 同款文案），确认后重扫
 *
 * 路由：系统路由表（router_map.json → name `Data`）。
 */
import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { MediaStorageService } from '../../services/MediaStorageService';
import { MediaUsage } from '../../services/MediaStorage';
import { AppDatabase } from '../../data/Database';
import { BackupFormat } from '../../services/backup/BackupFormat';

const DOMAIN = 0x0000;
const TAG = 'SettingsDataView';

@Builder
export function SettingsDataBuilder() {
  SettingsDataView()
}

@Component
export struct SettingsDataView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 媒体占用统计（null = 还没扫完；扫盘要遍历目录，不放在 build 里同步做） */
  @State private mediaUsage: MediaUsage | null = null;

  private navPathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 20 }) {
            // 云同步 + 导出 / 导入 + 占用 / 清理（华为设置分组卡）
            Column() {
              this.syncRow()
              // 🔴 未同步成功必须说清后果（R-DATA-05 华为版，红字）
              Text($r('app.string.s_f71802e114'))
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.destructive)
                .padding({ left: 20, right: 20, bottom: 14, top: 2 })
                .width('100%')
              Divider()
                .color(this.theme.border)
                .strokeWidth(0.5)
                .margin({ left: 20 })
              this.exportRow()
              Divider()
                .color(this.theme.border)
                .strokeWidth(0.5)
                .margin({ left: 20 })
              this.importRow()
              Divider()
                .color(this.theme.border)
                .strokeWidth(0.5)
                .margin({ left: 20 })
              this.usageRow()
              if (this.mediaUsage !== null && this.mediaUsage.orphanCount > 0) {
                Divider()
                  .color(this.theme.border)
                  .strokeWidth(0.5)
                  .margin({ left: 20 })
                this.reclaimRow()
              }
            }
            .borderRadius(16)
            .backgroundColor(this.theme.settingsCardBackground)
            .width('100%')

            // footer：导入语义 + 残留文件说明（iOS footer 同款两条）
            Column({ space: 6 }) {
              Text($r('app.string.s_06829794c0'))
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textTertiary)
              if (this.mediaUsage !== null && this.mediaUsage.orphanCount > 0) {
                Text($r('app.string.s_ca4fe69fd3'))
                  .fontSize(this.theme.labelFont.size)
                  .fontWeight(this.theme.labelFont.weight)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textTertiary)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: 8, right: 8 })

            // 底部：手势条让位
            Column().width('100%').height(this.safeAreaBottomVp + 32)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 24, right: 24 })
        }
        .width('100%')
        .layoutWeight(1)
        // 🔴 Scroll 设高度限制后内容小于视口默认居中（官方 FAQ faqs-arkui-725）——必须显式顶对齐
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.safeAreaTopVp })
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.settingsPageBackground)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      this.scanMediaUsage();
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题（SettingsAccountView 同款） ----

  @Builder
  private topBar() {
    Stack() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textPrimary])
        }
        .width(34)
        .height(34)
        .padding(0)
        .backgroundColor(this.theme.glassBackground)
        .border({ width: 0.5, color: this.theme.glassBorder })
        .onClick((): void => {
          this.navPathStack.pop();
        })
        Blank()
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text($r('app.string.s_9199a16092'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textSecondary)
          .letterSpacing(this.theme.letterSpacingWide)
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(TOP_BAR_ROW_HEIGHT_VP)
    .margin({ bottom: TOP_BAR_CONTENT_GAP_VP })
  }

  // ---- 云同步（R-DATA-05：如实展示；6.6 接真状态） ----

  @Builder
  private syncRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.cloud'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_6ed1b2bd01'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      Text($r('app.string.s_b9004e6f7b'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
    }
    .width('100%')
    .padding({ top: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
  }

  // ---- 导出 / 导入备份（6.5 / 6.4 接路由） ----

  @Builder
  private exportRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.share'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_d11b66842a'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textTertiary])
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.navPathStack.pushPathByName('BackupExport', '');
    })
  }

  @Builder
  private importRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_a26f1abe64'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textTertiary])
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.pickBackupFile();
    })
  }

  // ---- 照片与录音占用（R-DATA-08） ----

  @Builder
  private usageRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.externaldrive'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_5ed893c012'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      Text(this.usageText())
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
  }

  /** 占用值：没扫完显示「统计中…」（iOS "统计中…" 同款） */
  private usageText(): ResourceStr {
    if (this.mediaUsage === null) {
      return $r('app.string.s_0f449019e8');
    }
    return formatBytes(this.mediaUsage.totalBytes);
  }

  // ---- 清理残留文件（扫出孤儿才出现） ----

  @Builder
  private reclaimRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.wand_and_stars'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_3ae6d0bf40', this.mediaUsage === null ? 0 : this.mediaUsage.orphanCount))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      Text(formatBytes(this.mediaUsage === null ? 0 : this.mediaUsage.orphanBytes))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.accent)
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.confirmReclaim();
    })
  }

  // ---- 动作 ----

  /**
   * 6.4 导入备份：系统文件选择器挑 .memoir，选完把选择器 URI 直接推给
   * 导入页（导入页第一件事就把它拷进沙箱——选择器 URI 的临时读权限随时会失效）。
   * 用户取消不算错，静默返回。
   */
  private pickBackupFile(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const options = new picker.DocumentSelectOptions();
    options.fileSuffixFilters = ['.' + BackupFormat.fileExtension];
    options.maxSelectNumber = 1;
    const docPicker = new picker.DocumentViewPicker(context);
    docPicker.select(options).then((uris: Array<string>): void => {
      if (uris.length > 0) {
        this.navPathStack.pushPathByName('BackupImport', uris[0]);
      }
    }).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'document picker cancelled: %{public}d %{public}s',
        err.code, err.message);
    });
  }

  /** 扫盘统计媒体占用（onReady 触发一次；清理后重扫）。放异步任务里，不阻塞渲染 */
  private scanMediaUsage(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const scan = async (): Promise<void> => {
      const store = await AppDatabase.open(context);
      const service = MediaStorageService.create(context, store);
      this.mediaUsage = await service.usage();
    };
    scan().catch((): void => {
      // 扫盘失败：保持「统计中…」占位，不打扰用户（下次进页重扫）
    });
  }

  /** 清理确认（官方 AlertDialog；文案 iOS confirmationDialog 同款） */
  private confirmReclaim(): void {
    const usage = this.mediaUsage;
    if (usage === null || usage.orphanCount <= 0) {
      return;
    }
    this.getUIContext().showAlertDialog({
      message: $r('app.string.s_7147dd5d08', usage.orphanCount, formatBytes(usage.orphanBytes)),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.s_4d0b4688c7'),
        action: (): void => {}
      },
      secondaryButton: {
        value: $r('app.string.s_907c3945d8'),
        action: (): void => {
          this.reclaimOrphans();
        }
      }
    });
  }

  /** 确认清理：reclaimOrphans 后重扫（以库为准，不依赖缓存清单） */
  private reclaimOrphans(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const reclaim = async (): Promise<void> => {
      const store = await AppDatabase.open(context);
      const service = MediaStorageService.create(context, store);
      await service.reclaimOrphans();
      this.mediaUsage = await service.usage();
    };
    reclaim().catch((): void => {
      // 清理失败：保持现状（一个文件都没删，安全闸在 service 内部兜底）
    });
  }
}

/** 字节数格式化（iOS ByteCountFormatter .file 同观感：<1024 B / KB / MB / GB，1 位小数） */
function formatBytes(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  const units: string[] = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let unit = -1;
  while (value >= 1024 && unit < units.length - 1) {
    value = value / 1024;
    unit++;
  }
  const rounded = Math.round(value * 10) / 10;
  return `${rounded} ${units[unit]}`;
}
