/**
 * 导出备份包（10_BUILD_MANUAL.md 6.5）。对应 iOS `BackupExportView.swift`。
 *
 * 顺序刻意设计过：**先让用户看见「这里面是什么、有多大」，再决定加不加密，
 * 最后才是导出**。免责声明放在最后一步且必须勾选 —— 用户点导出的那一刻，
 * 应该完全清楚自己在把什么交出去。
 *
 * 默认加密（密码 ≥ 4 位两次一致）；超过 80 MB 提示别走微信（单文件上限）。
 * 产物落 cacheDir，经 systemShare 分享面板发出（沙箱文件转 file:// URI 即可，
 * 无需持久化权限）。
 *
 * 路由：系统路由表（router_map.json → name `BackupExport`）。
 */
import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AppDatabase } from '../../data/Database';
import { EntryRepository } from '../../data/EntryRepository';
import { NotebookRepository } from '../../data/NotebookRepository';
import { LetterRepository } from '../../data/LetterRepository';
import { JournalEntry } from '../../models/JournalEntry';
import { Notebook } from '../../models/Notebook';
import { Letter } from '../../models/Letter';
import { BackupFormat } from '../../services/backup/BackupFormat';
import { lastPathComponent } from '../../services/backup/BackupFs';
import { BackupExportService, BackupExportOptions,
  BackupExportResult } from '../../services/backup/BackupExportService';

const DOMAIN = 0x0000;
const TAG = 'BackupExportView';

/** 超过这个体积就提示别走微信（微信单文件上限约 100MB，留余量） */
const WECHAT_LIMIT_BYTES: number = 80 * 1024 * 1024;

@Builder
export function BackupExportBuilder() {
  BackupExportView()
}

@Component
export struct BackupExportView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @State private includesMedia: boolean = true;
  @State private useEncryption: boolean = true;
  @State private password: string = '';
  @State private passwordConfirm: string = '';
  @State private acknowledged: boolean = false;
  @State private isExporting: boolean = false;
  @State private exported: BackupExportResult | null = null;
  @State private entryCount: number = 0;
  @State private letterCount: number = 0;
  /** 媒体体积预估（「照片与录音」开着时显示；关掉显示 0） */
  @State private mediaBytesWithMedia: number = 0;

  private navPathStack: NavPathStack = new NavPathStack();
  private entries: JournalEntry[] = [];
  private letters: Letter[] = [];
  private tags: Notebook[] = [];

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 20 }) {
            this.contentSection()
            this.encryptionSection()
            this.disclaimerSection()
            this.exportSection()
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
      this.loadLibrary();
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题（SettingsDataView 同款） ----

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
        Text($r('app.string.s_d11b66842a'))
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

  // ---- 1. 包含内容 ----

  @Builder
  private contentSection() {
    Text($r('app.string.s_3150ea0d70'))
      .fontSize(this.theme.captionFont.size)
      .fontWeight(this.theme.captionFont.weight)
      .fontFamily(this.theme.captionFont.family)
      .fontColor(this.theme.textTertiary)
      .width('100%')
      .padding({ left: 8 })

    Column() {
      // 🔴 计数行必须内联 + 方法读 @State：@Builder 按值传参会把首帧的 0 冻住
      // （来信行原本因 if 晚建才显示正确；日记/大小行真机实测停在 0）
      Row() {
        Text($r('app.string.s_bf50d67138'))
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .layoutWeight(1)
        Text(this.entryCountText())
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textTertiary)
      }
      .width('100%')
      .padding({ top: 15, bottom: 15, left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      this.rowDivider()
      if (this.letterCount > 0) {
        Row() {
          Text($r('app.string.s_0f47f66752'))
            .fontSize(this.theme.bodyFont.size)
            .fontWeight(this.theme.bodyFont.weight)
            .fontFamily(this.theme.bodyFont.family)
            .fontColor(this.theme.textPrimary)
            .layoutWeight(1)
          Text(this.letterCountText())
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textTertiary)
        }
        .width('100%')
        .padding({ top: 15, bottom: 15, left: 20, right: 20 })
        .alignItems(VerticalAlign.Center)
        this.rowDivider()
      }
      Row() {
        Text($r('app.string.s_ebabcca5f6'))
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.includesMedia })
          .selectedColor(this.theme.accent)
          .onChange((isOn: boolean): void => {
            this.includesMedia = isOn;
          })
      }
      .width('100%')
      .padding({ top: 15, bottom: 15, left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      this.rowDivider()
      Row() {
        Text($r('app.string.s_e83afd599a'))
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .layoutWeight(1)
        Text(formatBytes(this.mediaBytes()))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textTertiary)
      }
      .width('100%')
      .padding({ top: 15, bottom: 15, left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      if (this.includesMedia && this.mediaBytes() > WECHAT_LIMIT_BYTES) {
        this.rowDivider()
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textSecondary])
            .width(20)
          Text($r('app.string.s_6b4f2d224d'))
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.textSecondary)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 15, bottom: 15, left: 20, right: 20 })
        .alignItems(VerticalAlign.Top)
      }
    }
    .borderRadius(16)
    .backgroundColor(this.theme.settingsCardBackground)
    .width('100%')

    Text(this.includesMedia
      ? $r('app.string.s_2dde9465fd')
      : $r('app.string.s_5f03b3f09c'))
      .fontSize(this.theme.labelFont.size)
      .fontWeight(this.theme.labelFont.weight)
      .fontFamily(this.theme.labelFont.family)
      .fontColor(this.theme.textTertiary)
      .width('100%')
      .padding({ left: 8, right: 8 })
  }

  // ---- 2. 加密 ----

  @Builder
  private encryptionSection() {
    Text($r('app.string.s_c51f0d0011'))
      .fontSize(this.theme.captionFont.size)
      .fontWeight(this.theme.captionFont.weight)
      .fontFamily(this.theme.captionFont.family)
      .fontColor(this.theme.textTertiary)
      .width('100%')
      .padding({ left: 8 })

    Column() {
      Row() {
        Text($r('app.string.s_6b19ea408a'))
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.useEncryption })
          .selectedColor(this.theme.accent)
          .onChange((isOn: boolean): void => {
            this.useEncryption = isOn;
          })
      }
      .width('100%')
      .padding({ top: 15, bottom: 15, left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)

      if (this.useEncryption) {
        this.rowDivider()
        Row() {
          TextInput({
            placeholder: $r('app.string.s_55b7664990'),
            text: this.password
          })
            .type(InputType.Password)
            .fontSize(this.theme.bodyFont.size)
            .fontColor(this.theme.textPrimary)
            .caretColor(this.theme.textSecondary)
            .backgroundColor(this.theme.surfaceBackground)
            .borderRadius(10)
            .padding({ left: 12, right: 12 })
            .height(42)
            .layoutWeight(1)
            .onChange((value: string): void => {
              this.password = value;
            })
        }
        .width('100%')
        .padding({ top: 12, bottom: 12, left: 20, right: 20 })
        .alignItems(VerticalAlign.Center)

        Row() {
          TextInput({
            placeholder: $r('app.string.s_bfd6de1bee'),
            text: this.passwordConfirm
          })
            .type(InputType.Password)
            .fontSize(this.theme.bodyFont.size)
            .fontColor(this.theme.textPrimary)
            .caretColor(this.theme.textSecondary)
            .backgroundColor(this.theme.surfaceBackground)
            .borderRadius(10)
            .padding({ left: 12, right: 12 })
            .height(42)
            .layoutWeight(1)
            .onChange((value: string): void => {
              this.passwordConfirm = value;
            })
            .onSubmit((_enterKey: EnterKeyType, _event: SubmitEvent): void => {
              if (this.canExport()) {
                this.runExport();
              }
            })
        }
        .width('100%')
        .padding({ top: 12, bottom: 12, left: 20, right: 20 })
        .alignItems(VerticalAlign.Center)

        if (this.password.length > 0 && this.passwordConfirm.length > 0
          && this.password !== this.passwordConfirm) {
          Text($r('app.string.s_5c6e6c1b88'))
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.destructive)
            .padding({ left: 20, right: 20, bottom: 12 })
            .width('100%')
        }
      }
    }
    .borderRadius(16)
    .backgroundColor(this.theme.settingsCardBackground)
    .width('100%')

    Text(this.useEncryption
      ? $r('app.string.s_42b37aa07d')
      : $r('app.string.s_d567eeebd2'))
      .fontSize(this.theme.labelFont.size)
      .fontWeight(this.theme.labelFont.weight)
      .fontFamily(this.theme.labelFont.family)
      .fontColor(this.theme.textTertiary)
      .width('100%')
      .padding({ left: 8, right: 8 })
  }

  // ---- 3. 免责声明（必须勾选） ----

  @Builder
  private disclaimerSection() {
    Row({ space: 10 }) {
      // 手绘勾选框：方框 + checkmark（不用系统 Checkbox，观感与 iOS checkmark.square 对齐）
      Stack() {
        if (this.acknowledged) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor([Color.White])
        }
      }
      .width(18)
      .height(18)
      .borderRadius(4)
      .backgroundColor(this.acknowledged ? this.theme.accent : Color.Transparent)
      .border({
        width: 1,
        color: this.acknowledged ? this.theme.accent : this.theme.textTertiary
      })

      Text($r('app.string.s_fe06546672'))
        .fontSize(this.theme.labelFont.size)
        .fontWeight(this.theme.labelFont.weight)
        .fontFamily(this.theme.labelFont.family)
        .fontColor(this.theme.textSecondary)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Top)
    .borderRadius(16)
    .backgroundColor(this.theme.settingsCardBackground)
    .onClick((): void => {
      this.acknowledged = !this.acknowledged;
    })
  }

  // ---- 4. 导出 ----

  @Builder
  private exportSection() {
    Column() {
      if (this.exported !== null) {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.share'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textSecondary])
            .width(20)
          Text($r('app.string.s_121c1f2d8e', formatBytes(this.exported.byteCount)))
            .fontSize(this.theme.bodyFont.size)
            .fontWeight(this.theme.bodyFont.weight)
            .fontFamily(this.theme.bodyFont.family)
            .fontColor(this.theme.accent)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 15, bottom: 15, left: 20, right: 20 })
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.shareExportedFile();
        })
      } else {
        Row({ space: 10 }) {
          if (this.isExporting) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(this.theme.accent)
            Text($r('app.string.s_534de73969'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.textSecondary)
          } else {
            Text($r('app.string.s_df73c654d2'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.canExport() ? this.theme.accent : this.theme.textTertiary)
          }
        }
        .width('100%')
        .padding({ top: 15, bottom: 15 })
        .justifyContent(FlexAlign.Center)
        .onClick((): void => {
          if (this.canExport()) {
            this.runExport();
          }
        })
      }
    }
    .borderRadius(16)
    .backgroundColor(this.theme.settingsCardBackground)
    .width('100%')

    if (this.exported !== null) {
      Text($r('app.string.s_771ba2fa48'))
        .fontSize(this.theme.labelFont.size)
        .fontWeight(this.theme.labelFont.weight)
        .fontFamily(this.theme.labelFont.family)
        .fontColor(this.theme.textTertiary)
        .width('100%')
        .padding({ left: 8, right: 8 })
    }
  }

  // ---- 行零件 ----

  @Builder
  private rowDivider() {
    Divider()
      .color(this.theme.border)
      .strokeWidth(0.5)
      .margin({ left: 20, right: 20 })
  }

  // ---- 动作 ----

  /** 查库拿计数与媒体体积预估（进页一次；导出时再取全量数据） */
  private loadLibrary(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const load = async (): Promise<void> => {
      const store = await AppDatabase.open(context);
      this.entries = await EntryRepository.fetchAllEntries(store);
      this.letters = await LetterRepository.listLetters(store);
      this.tags = await NotebookRepository.fetchAllNotebooks(store);
      this.entryCount = this.entries.length;
      this.letterCount = this.letters.length;
      this.mediaBytesWithMedia = BackupExportService.estimateMediaBytes(context,
        this.entries, this.tags);
    };
    load().catch((err: Object): void => {
      hilog.error(DOMAIN, TAG, 'load library failed: %{public}s', JSON.stringify(err));
    });
  }

  /** 「照片与录音」关掉时预估清零（iOS mediaBytes 计算属性同款） */
  private mediaBytes(): number {
    return this.includesMedia ? this.mediaBytesWithMedia : 0;
  }

  /** 加密开时密码 ≥ 4 位且两次一致；不开恒真 */
  private passwordValid(): boolean {
    return !this.useEncryption
      || (this.password.length >= 4 && this.password === this.passwordConfirm);
  }

  private canExport(): boolean {
    return this.entryCount > 0 && this.acknowledged
      && this.passwordValid() && !this.isExporting;
  }

  /** 生成备份包（成功后导出段变「分享备份包（大小）」） */
  private runExport(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.isExporting = true;
    const run = async (): Promise<void> => {
      try {
        const store = await AppDatabase.open(context);
        const options = new BackupExportOptions();
        options.includesMedia = this.includesMedia;
        options.password = this.useEncryption ? this.password : undefined;
        this.exported = await BackupExportService.export(context, store,
          this.entries, this.letters, this.tags, options);
      } finally {
        this.isExporting = false;
      }
    };
    run().catch((err: Object): void => {
      hilog.error(DOMAIN, TAG, 'export failed: %{public}s', JSON.stringify(err));
      this.env.errors.present(this.getStringRes($r('app.string.s_6753381261')),
        ErrorToastKind.Error);
    });
  }

  /**
   * 系统分享面板（systemShare）：沙箱文件转 file:// URI 直接分享，
   * 无需持久化权限；utd 用自定义 TypeId（utd.json5 声明的 .memoir 类型），
   * 接收端能认出「这是尺素备份包」。
   */
  private shareExportedFile(): void {
    const exported = this.exported;
    if (exported === null) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      return;
    }
    try {
      const record: systemShare.SharedRecord = {
        utd: BackupFormat.utdTypeId,
        uri: fileUri.getUriFromPath(exported.filePath),
        title: lastPathComponent(exported.filePath)
      };
      const data = new systemShare.SharedData(record);
      const controller = new systemShare.ShareController(data);
      const options: systemShare.ShareControllerOptions = {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      };
      controller.show(context, options).catch((err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'share panel failed: %{public}d %{public}s',
          err.code, err.message);
      });
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'share prepare failed: %{public}d %{public}s',
        e.code, e.message);
    }
  }

  /** Resource → string（resourceManager 同步取） */
  private getStringRes(res: Resource): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringSync(res.id);
  }

  /** 「%d 篇」：方法内读 @State 才能在 loadLibrary 回来后刷新（getStringSync 带参格式化） */
  private entryCountText(): string {
    return this.countText($r('app.string.s_54c43eaca1'), this.entryCount);
  }

  /** 「%d 封」同上 */
  private letterCountText(): string {
    return this.countText($r('app.string.s_da142a5478'), this.letterCount);
  }

  private countText(res: Resource, count: number): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return `${count}`;
    }
    return context.resourceManager.getStringSync(res.id, count);
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
