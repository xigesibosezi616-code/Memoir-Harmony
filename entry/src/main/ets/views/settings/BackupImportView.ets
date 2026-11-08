/**
 * 导入备份包（10_BUILD_MANUAL.md 6.4）。对应 iOS `BackupImportView.swift`。
 *
 * 两个入口都进这里：文件关联「用尺素打开 .memoir」（EntryAbility 立刻把 URI
 * 落成沙箱中转副本，经 SettingsTabView 推路由，参数 = 沙箱路径），或
 * 设置 → 数据与备份 → 导入备份（文件选择器，参数 = 选择器 URI，本页自己
 * 做中转拷贝——选择器 URI 的临时读权限随时会失效，拿到就先拷进来）。
 *
 * 五态（iOS Phase 同款）：打开中 → 要密码 → 预览确认 → 导入中 → 结果。
 * 语气和导出页刻意不同：导入只增不减，只需说清「已有的会跳过」。
 * 导入中禁止退出（onBackPressed 拦截 + 藏返回钮，iOS interactiveDismissDisabled 同款）。
 *
 * 路由：系统路由表（router_map.json → name `BackupImport`）。
 */
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { AppDatabase } from '../../data/Database';
import { STORAGE_KEY_HOME_RELOAD_TICK } from '../../data/HomeLogic';
import { STORAGE_KEY_LETTER_OUTBOX_TICK } from '../../services/LetterOutboxService';
import { BackupImportService, BackupImportSummary, BackupPackage, BackupImportFailure,
  BackupImportError, TagConflictPolicy } from '../../services/backup/BackupImportService';
import { removeTree } from '../../services/backup/BackupFs';
import { BackupConflictDialog } from './BackupConflictDialog';

const DOMAIN = 0x0000;
const TAG = 'BackupImportView';

/** 页面五态（iOS `Phase` 同款） */
enum ImportPhase {
  Opening = 'opening',
  AskPassword = 'askPassword',
  Ready = 'ready',
  Importing = 'importing',
  Finished = 'finished'
}

@Builder
export function BackupImportBuilder() {
  BackupImportView()
}

@Component
export struct BackupImportView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'en';
  @State private phase: ImportPhase = ImportPhase.Opening;
  @State private password: string = '';
  @State private passwordFailed: boolean = false;
  @State private pkg: BackupPackage | null = null;
  @State private summary: BackupImportSummary | null = null;
  /** 同名日记本冲突弹窗开着（包里的写法在 tagConflicts 里） */
  @State private showConflictDialog: boolean = false;

  private navPathStack: NavPathStack = new NavPathStack();
  /** 路由参数：选择器 URI（file:// 开头）或文件关联的沙箱中转副本路径 */
  private sourceRef: string = '';
  /** 解析后实际读取的沙箱路径 */
  private filePath: string = '';
  /** 离开页面时要不要顺手删掉这份中转副本（cache 里的临时文件，不删就攒垃圾） */
  private ownsIntakeCopy: boolean = false;
  private tagConflicts: string[] = [];

  aboutToDisappear(): void {
    // 解压出来的临时文件和中转副本都得清掉，不然每导一次就在沙箱里多压几十 MB 死文件
    if (this.pkg !== null) {
      BackupImportService.discard(this.pkg);
      this.pkg = null;
    }
    if (this.ownsIntakeCopy && this.filePath.length > 0) {
      removeTree(this.filePath);
    }
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.topBar()

          Scroll() {
            Column({ space: 20 }) {
              if (this.phase === ImportPhase.Opening) {
                this.busySection($r('app.string.s_b0059123ef'))
              } else if (this.phase === ImportPhase.AskPassword) {
                this.passwordSection()
              } else if (this.phase === ImportPhase.Ready) {
                this.packageSection()
                this.confirmSection()
              } else if (this.phase === ImportPhase.Importing) {
                this.busySection($r('app.string.s_cd74f09629'))
              } else {
                this.resultSection()
              }
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

        // 同名日记本冲突：树内条件渲染弹窗（ComposeView 同款范式）
        if (this.showConflictDialog) {
          BackupConflictDialog({
            names: this.tagConflicts,
            onMerge: (): void => {
              this.pickConflictPolicy(true);
            },
            onKeepSeparate: (): void => {
              this.pickConflictPolicy(false);
            },
            onCancel: (): void => {
              this.showConflictDialog = false;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.settingsPageBackground)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      const param = ctx.pathInfo.param as string | undefined;
      if (typeof param === 'string' && param.length > 0) {
        this.sourceRef = param;
      }
      this.openPackage(undefined);
    })
    // 导入进行中禁止返回（iOS interactiveDismissDisabled 同款）：中途退出留下半套数据
    .onBackPressed((): boolean => {
      return this.phase === ImportPhase.Importing;
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题（SettingsDataView 同款；导入中藏返回钮） ----

  @Builder
  private topBar() {
    Stack() {
      Row() {
        if (this.phase !== ImportPhase.Importing) {
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
        }
        Blank()
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text($r('app.string.s_a26f1abe64'))
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

  // ---- 打开中 / 导入中 ----

  @Builder
  private busySection(titleRes: Resource) {
    Column() {
      Row({ space: 10 }) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(this.theme.accent)
        Text(titleRes)
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textSecondary)
      }
      .width('100%')
      .padding({ top: 18, bottom: 18 })
      .justifyContent(FlexAlign.Center)
    }
    .borderRadius(16)
    .backgroundColor(this.theme.settingsCardBackground)
    .width('100%')

    if (this.phase === ImportPhase.Importing) {
      Text($r('app.string.s_b768d5ebc5'))
        .fontSize(this.theme.labelFont.size)
        .fontWeight(this.theme.labelFont.weight)
        .fontFamily(this.theme.labelFont.family)
        .fontColor(this.theme.textTertiary)
        .width('100%')
        .padding({ left: 8, right: 8 })
    }
  }

  // ---- 要密码 ----

  @Builder
  private passwordSection() {
    Text($r('app.string.s_39bc5e6806'))
      .fontSize(this.theme.captionFont.size)
      .fontWeight(this.theme.captionFont.weight)
      .fontFamily(this.theme.captionFont.family)
      .fontColor(this.theme.textTertiary)
      .width('100%')
      .padding({ left: 8 })

    Column() {
      Row() {
        TextInput({
          placeholder: $r('app.string.s_ab7fb2e196'),
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
          .onSubmit((_enterKey: EnterKeyType, _event: SubmitEvent): void => {
            this.unlock();
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12, left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)

      if (this.passwordFailed) {
        Text($r('app.string.s_a33bda51e5'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.destructive)
          .padding({ left: 20, right: 20, bottom: 12 })
          .width('100%')
      }

      Row() {
        Text($r('app.string.s_eb7cf7b71a'))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.password.length === 0 ? this.theme.textTertiary : this.theme.accent)
      }
      .width('100%')
      .padding({ top: 15, bottom: 15 })
      .justifyContent(FlexAlign.Center)
      .onClick((): void => {
        this.unlock();
      })
    }
    .borderRadius(16)
    .backgroundColor(this.theme.settingsCardBackground)
    .width('100%')

    Text($r('app.string.s_01d498446e'))
      .fontSize(this.theme.labelFont.size)
      .fontWeight(this.theme.labelFont.weight)
      .fontFamily(this.theme.labelFont.family)
      .fontColor(this.theme.textTertiary)
      .width('100%')
      .padding({ left: 8, right: 8 })
  }

  // ---- 包里有什么 ----

  @Builder
  private packageSection() {
    if (this.pkg !== null) {
      Text($r('app.string.s_677fa61f1d'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
        .width('100%')
        .padding({ left: 8 })

      Column() {
        this.infoRow($r('app.string.s_bf50d67138'),
          $r('app.string.s_54c43eaca1', this.pkg.manifest.counts.entries))
        if (this.pkg.manifest.counts.letters > 0) {
          this.rowDivider()
          this.infoRow($r('app.string.s_0f47f66752'),
            $r('app.string.s_da142a5478', this.pkg.manifest.counts.letters))
        }
        this.rowDivider()
        this.infoRow($r('app.string.s_ebabcca5f6'),
          this.pkg.manifest.includesMedia
            ? $r('app.string.s_820929d497', this.pkg.manifest.counts.media)
            : $r('app.string.s_199e333f97'))
        if (this.pkg.manifest.exportedAtMs > 0) {
          this.rowDivider()
          this.infoRow($r('app.string.s_d4e077f9d4'), this.exportedAtText())
        }
        this.rowDivider()
        this.infoRow($r('app.string.s_16593aa84d'), this.sourceDescription())
      }
      .borderRadius(16)
      .backgroundColor(this.theme.settingsCardBackground)
      .width('100%')

      if (!this.pkg.manifest.includesMedia) {
        Text($r('app.string.s_2643a85f0c'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
          .width('100%')
          .padding({ left: 8, right: 8 })
      }
    }
  }

  // ---- 开始导入 ----

  @Builder
  private confirmSection() {
    Row() {
      Text($r('app.string.s_3d04880897'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.accent)
    }
    .width('100%')
    .padding({ top: 15, bottom: 15 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(16)
    .backgroundColor(this.theme.settingsCardBackground)
    .onClick((): void => {
      this.startImport();
    })

    Text($r('app.string.s_918e4226fe'))
      .fontSize(this.theme.labelFont.size)
      .fontWeight(this.theme.labelFont.weight)
      .fontFamily(this.theme.labelFont.family)
      .fontColor(this.theme.textTertiary)
      .width('100%')
      .padding({ left: 8, right: 8 })
  }

  // ---- 结果 ----

  @Builder
  private resultSection() {
    if (this.summary !== null) {
      Text(this.summary.entriesImported > 0
        ? $r('app.string.s_75c33f5c2e')
        : $r('app.string.s_be58bf9d7d'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
        .width('100%')
        .padding({ left: 8 })

      Column() {
        this.infoRow($r('app.string.s_b991e9b2ca'),
          $r('app.string.s_54c43eaca1', this.summary.entriesImported))
        if (this.summary.entriesSkipped > 0) {
          this.rowDivider()
          this.infoRow($r('app.string.s_c558e955b8'),
            $r('app.string.s_54c43eaca1', this.summary.entriesSkipped))
        }
        if (this.summary.lettersImported > 0) {
          this.rowDivider()
          this.infoRow($r('app.string.s_e32c03cfb9'),
            $r('app.string.s_da142a5478', this.summary.lettersImported))
        }
        if (this.summary.tagsImported > 0) {
          this.rowDivider()
          this.infoRow($r('app.string.s_6fde12863f'),
            $r('app.string.s_820929d497', this.summary.tagsImported))
        }
        if (this.summary.missingMedia > 0) {
          this.rowDivider()
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor([this.theme.textSecondary])
              .width(20)
            Text($r('app.string.s_ebf9dfc91c', this.summary.missingMedia))
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

      Text(this.summary.entriesImported > 0
        ? $r('app.string.s_cfe9c440c8')
        : $r('app.string.s_8b196caa75'))
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
  private infoRow(titleRes: Resource, value: ResourceStr) {
    Row() {
      Text(titleRes)
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      Text(value)
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private rowDivider() {
    Divider()
      .color(this.theme.border)
      .strokeWidth(0.5)
      .margin({ left: 20, right: 20 })
  }

  // ---- 动作 ----

  /** 解锁：密码非空才开 */
  private unlock(): void {
    if (this.password.length === 0) {
      return;
    }
    this.openPackage(this.password);
  }

  /**
   * 解密 + 解压 + 读 manifest。第一次先做中转拷贝（选择器 URI 的临时读权限
   * 随时会失效，拿到就立刻拷进沙箱固定位置，之后都走副本）。
   * 加密包没给密码 → AskPassword；密码错 → 红字再试；其他失败 → toast 后退出。
   */
  private openPackage(password: string | undefined): void {
    this.phase = ImportPhase.Opening;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const open = async (): Promise<void> => {
      if (this.filePath.length === 0) {
        if (this.sourceRef.length === 0) {
          throw new BackupImportFailure(BackupImportError.UnreadableFile);
        }
        if (this.sourceRef.startsWith('file://')) {
          this.filePath = await BackupImportService.intakeExternalFile(context, this.sourceRef);
        } else {
          this.filePath = this.sourceRef;
        }
        this.ownsIntakeCopy = this.filePath === BackupImportService.intakePath(context);
      }
      const opened = await BackupImportService.open(context, this.filePath, password);
      this.pkg = opened;
      this.passwordFailed = false;
      this.phase = ImportPhase.Ready;
    };
    open().catch((err: Object): void => {
      if (err instanceof BackupImportFailure) {
        if (err.kind === BackupImportError.NeedsPassword) {
          this.phase = ImportPhase.AskPassword;
          return;
        }
        if (err.kind === BackupImportError.WrongPassword) {
          this.passwordFailed = true;
          this.phase = ImportPhase.AskPassword;
          return;
        }
      }
      hilog.error(DOMAIN, TAG, 'open package failed: %{public}s', JSON.stringify(err));
      this.env.errors.present(this.getStringRes($r('app.string.s_573ee77a59')),
        ErrorToastKind.Error);
      this.navPathStack.pop();
    });
  }

  /** 开始导入：先查同名日记本冲突，没有直接导（Merge），有先弹窗问 */
  private startImport(): void {
    const pkg = this.pkg;
    if (pkg === null) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const run = async (): Promise<void> => {
      const store = await AppDatabase.open(context);
      const conflicts = await BackupImportService.tagConflicts(store, pkg);
      if (conflicts.length > 0) {
        this.tagConflicts = conflicts;
        this.showConflictDialog = true;
        return;
      }
      await this.runImport(context, store, TagConflictPolicy.Merge);
    };
    run().catch((err: Object): void => {
      hilog.error(DOMAIN, TAG, 'start import failed: %{public}s', JSON.stringify(err));
      this.env.errors.present(this.getStringRes($r('app.string.s_a01a8d5393')),
        ErrorToastKind.Error);
    });
  }

  /** 冲突弹窗的选择：合并 / 分开 */
  private pickConflictPolicy(merge: boolean): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.showConflictDialog = false;
      return;
    }
    const run = async (): Promise<void> => {
      const store = await AppDatabase.open(context);
      await this.runImport(context, store,
        merge ? TagConflictPolicy.Merge : TagConflictPolicy.KeepSeparate);
    };
    run().catch((err: Object): void => {
      hilog.error(DOMAIN, TAG, 'conflict import failed: %{public}s', JSON.stringify(err));
      this.env.errors.present(this.getStringRes($r('app.string.s_a01a8d5393')),
        ErrorToastKind.Error);
      this.phase = ImportPhase.Ready;
    });
  }

  /** 真正合并入库。成功后广播刷新（首页 / 书架 / 邮筒），失败回 Ready 再来一次 */
  private async runImport(context: common.Context, store: relationalStore.RdbStore,
    tagPolicy: TagConflictPolicy): Promise<void> {
    const pkg = this.pkg;
    if (pkg === null) {
      return;
    }
    this.showConflictDialog = false;
    this.phase = ImportPhase.Importing;
    try {
      const summary = await BackupImportService.merge(context, store, pkg, tagPolicy);
      this.summary = summary;
      this.phase = ImportPhase.Finished;
      // 导入成功后让记录 / 日记本 / 邮筒都重查（tick 驱动，与编辑日记后的刷新同款）
      AppStorage.setOrCreate(STORAGE_KEY_HOME_RELOAD_TICK,
        (AppStorage.get<number>(STORAGE_KEY_HOME_RELOAD_TICK) ?? 0) + 1);
      AppStorage.setOrCreate(STORAGE_KEY_LETTER_OUTBOX_TICK,
        (AppStorage.get<number>(STORAGE_KEY_LETTER_OUTBOX_TICK) ?? 0) + 1);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'merge failed: %{public}s', JSON.stringify(err));
      this.env.errors.present(this.getStringRes($r('app.string.s_a01a8d5393')),
        ErrorToastKind.Error);
      this.phase = ImportPhase.Ready;
    }
  }

  /** 导出时间按 App 语言格式化（iOS medium 日期 + short 时间同观感；
   *  dateStyle/timeStyle 未验证 ArkTS 类型支持，用保守的逐项 options 写法） */
  private exportedAtText(): string {
    const pkg = this.pkg;
    if (pkg === null) {
      return '';
    }
    return new Intl.DateTimeFormat(this.appLanguage, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit'
    }).format(new Date(pkg.manifest.exportedAtMs));
  }

  /**
   * 备份包来源：「iPhone」是产品名不翻；鸿蒙 / 其他设备是文案；
   * 整行格式 `%1$s · 尺素 %2$s`（设备 · App 版本号）。
   */
  private sourceDescription(): string {
    const pkg = this.pkg;
    if (pkg === null) {
      return '';
    }
    const platform: string = pkg.manifest.platform === 'ios' ? 'iPhone'
      : pkg.manifest.platform === 'harmony'
        ? this.getStringRes($r('app.string.s_34346fa337'))
        : this.getStringRes($r('app.string.s_ca96133fe5'));
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringSync($r('app.string.s_e7b319db30').id,
      platform, pkg.manifest.appVersion);
  }

  /** Resource → string（resourceManager 同步取，无参格式） */
  private getStringRes(res: Resource): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringSync(res.id);
  }
}
