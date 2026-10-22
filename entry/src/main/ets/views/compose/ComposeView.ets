/**
 * 写日记页 v1（10_BUILD_MANUAL.md 2.1，纯文本）。对应 iOS `Views/Compose/ComposeView.swift`。
 *
 * - 全屏：左上返回（chevron：退出≠丢弃，可以存草稿）、右上 ✓（**只有点 ✓ 才算完成一篇**，
 *   R-ENTRY-01）；正文空时 ✓ 只降透明度不可点
 * - 左上返回 + 系统返回（手势 / 返回键，路由页 onBackPress 拦截后经
 *   AppStorage tick 转到这里，真机踩坑：不拦截则 router.back() 直接退出）：
 *   有内容 → 「不保存 / 保存草稿」（官方 @CustomDialog，点遮罩=取消，
 *   R-ENTRY-02/03）；全空直接退出
 * - 进页面恢复草稿（全局一份，R-ENTRY-04/05），顶部提示「接着上次没写完的」
 * - 日期自动取当下、不可改（R-ENTRY-06）；标题 ≤40、去换行、最多三行（R-ENTRY-07）
 * - 正文富文本（2.5 RichBodyEditor，2026-10-18 回退备忘录式——绕排连环平台
 *   缺陷后产品拍板，见 09 Q23）：照片整行锚点卡 + 文字上下独立段；底部四灯
 *   工具条（加粗/斜体/小标题/荧光笔）+ 照片键（≤5 张，R-RICH-03/05）
 *   + 录音键（≤3 段，2.7：权限 → 录音面板 → 光标所在段下面插录音卡）
 * - v1 不做：天气地点（2.8+ 各自的卡片）
 */
import { relationalStore } from '@kit.ArkData';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { dayAndWeekday } from '../../services/AppDateFormatters';
import {
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_HIDE_TAB_BAR
} from '../../services/ImmersiveChrome';
import { AppEnvironment, STORAGE_KEY_APP_ENVIRONMENT } from '../../environment/AppEnvironment';
import { ErrorToastKind, createDefaultErrorPresenter } from '../../environment/ErrorPresenter';
import { AppDatabase } from '../../data/Database';
import { DraftRepository } from '../../data/DraftRepository';
import { EntryRepository } from '../../data/EntryRepository';
import { NotebookRepository } from '../../data/NotebookRepository';
import { MoodRepository } from '../../data/MoodRepository';
import {
  composeCleanedBlocks,
  restoredNotebookSelection
} from '../../data/ComposeLogic';
import { JournalEntry } from '../../models/JournalEntry';
import {
  ContentBlock,
  ContentBlockType,
  PaperStyle,
  PhotoPosition,
  blocksAudioPaths
} from '../../models/ContentBlock';
import { RichBodyController, RichBodyEditor } from '../components/richtext/RichBodyEditor';
import { RichFormatToolbar } from '../components/richtext/RichFormatToolbar';
import {
  anchoredBlocksOf,
  blocksWithEditorDocument,
  editorDocumentFromBlocks
} from '../../models/RichDocument';
import { PhotoLibraryPicker, PickedLibraryPhoto } from '../../services/PhotoLibraryPicker';
import { PhotoPaperIO } from '../../services/PhotoPaperIO';
import { CameraShot } from '../../services/CameraSession';
import { saveCameraShot } from '../../services/CameraPhotoFiles';
import { deleteAudioFile } from '../../services/AudioRecorderManager';
import { PaperStylePickerSheet } from '../components/photo/PaperStylePickerSheet';
import { PhotoFullScreenCover } from '../components/photo/PhotoFullScreenCover';
import { PaperCameraView } from '../camera/PaperCameraView';
import { VoiceRecordingSheet } from '../components/audio/VoiceRecordingSheet';
import { WeatherLocationBadge } from '../components/WeatherLocationBadge';
import { MoodTag } from '../../models/Mood';
import { Notebook, cleanedName, nameKey, nextSortOrder, quietestColor } from '../../models/Notebook';
import { DraftEntry, PlaceMode } from '../../models/Draft';
import { generateUuid } from '../../models/Uuid';
import { MediaStorageService } from '../../services/MediaStorageService';
import { AppPrefs } from '../../services/AppPrefs';
import { LocationWeatherManager } from '../../services/LocationWeatherManager';
import { CircleIconButton } from './CircleIconButton';
import { MoodSelector } from './MoodSelector';
import { NotebookSelector } from './NotebookSelector';
import { DraftExitDialog } from './DraftExitDialog';
import { CreateNotebookDialog } from './CreateNotebookDialog';
import { LocationPickerView } from './LocationPickerView';

const DOMAIN = 0x0000;
const TAG = 'ComposeView';

/** 系统返回（手势/按键）拦截信号：路由页 onBackPress +1，这里 @Watch 决策 */
export const STORAGE_KEY_COMPOSE_BACK_TICK = 'compose.systemBackTick';

@Component
export struct ComposeView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_APP_ENVIRONMENT) env: AppEnvironment =
    new AppEnvironment(createDefaultErrorPresenter());
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  @State title: string = '';
  @State bodyText: string = '';
  @State moodName: string = '';
  @State moodColorHex: string = '';
  @State selectedNotebookName: string = '';
  @State didRestoreDraft: boolean = false;
  @State moods: MoodTag[] = [];
  @State notebooks: Notebook[] = [];
  @State showCreateNotebook: boolean = false;
  // ---- 2.6 照片 ----
  /** 正文照片张数镜像（✓ 判定 / 退出判定：只有照片没有文字也算写了，iOS hasContent） */
  @State bodyPhotoCount: number = 0;
  /** 相纸选择 sheet（新照片选相纸 / 给已插照片换相纸共用） */
  @State showPaperSheet: boolean = false;
  @State paperSheetPixelMap: image.PixelMap | undefined = undefined;
  /** 相册选完待落盘的产物（动态照片带原样字节，选完相纸才落盘） */
  private pendingPickedPhoto: PickedLibraryPhoto | undefined = undefined;
  /** 照片全屏查看（页面内浮层；长按正文照片打开） */
  @State @Watch('onPhotoFullscreenChanged') showPhotoFullscreen: boolean = false;
  @State fullscreenPhoto: ContentBlock | undefined = undefined;
  /** 换相纸的目标照片 id（undefined = sheet 是「新照片选相纸」） */
  private restylePhotoId: string | undefined = undefined;
  // ---- 2.9 尺素相机 ----
  /** 相机浮层（页面内条件浮层，全屏照片同款挂法；开/关联动藏 Tab 栏） */
  @State @Watch('onCameraOverlayChanged') showCamera: boolean = false;
  /** 本次进页面新落盘的照片文件（存盘 / 放弃时清没被引用的，iOS insertedMediaNames） */
  private insertedMediaNames: Set<string> = new Set<string>();
  /** 草稿带进来的照片文件（删掉时清没被新草稿引用的，iOS restoredPhotoNames） */
  private restoredPhotoNames: Set<string> = new Set<string>();
  // ---- 2.7 录音 ----
  /** 正文录音段数镜像（✓ 判定：只有录音没有文字也算写了） */
  @State bodyAudioCount: number = 0;
  /** 录音面板 sheet（工具条 mic 键 → 先申请麦克风权限再开） */
  @State showRecordingSheet: boolean = false;
  /** 麦克风权限被拒（面板渲染「去设置」引导态） */
  @State recordingMicDenied: boolean = false;
  /** 本次进页面新落盘的录音文件（存盘 / 放弃时清没被引用的） */
  private insertedAudioPaths: Set<string> = new Set<string>();
  /** 草稿带进来的录音文件（删掉时清没被新草稿引用的） */
  private restoredAudioPaths: Set<string> = new Set<string>();
  // ---- 2.10 此时此地 ----
  /** 天气 + 地点解析（@State 观察第一层；异步收尾 bump tick 兜底刷新） */
  @State weather: LocationWeatherManager = new LocationWeatherManager();
  /** 这篇日记记哪个地点：auto / none / manual（PlaceMode） */
  @State placeMode: string = PlaceMode.Auto;
  /** manual 模式挑中的名字 */
  @State manualPlaceName: string = '';
  /** 地点选择器 sheet */
  @State showLocationPicker: boolean = false;
  /** 解析完成信号：@State 类内部异步写 + bump 一下，确保最终态必刷（防内部写不通知的兜底） */
  @State weatherPlaceTick: number = 0;
  /** 系统返回信号（路由页 onBackPress 拦截后 +1） */
  @StorageProp(STORAGE_KEY_COMPOSE_BACK_TICK) @Watch('onSystemBackTick')
  systemBackTick: number = 0;

  /** 官方弹窗控制器：DraftExitDialog（autoCancel 点遮罩=取消；customStyle 玻璃卡自绘） */
  private exitDialogController: CustomDialogController = new CustomDialogController({
    builder: DraftExitDialog({
      onDiscard: (): void => {
        this.discardAndClose();
      },
      onSave: (): void => {
        this.saveDraftAndClose();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  });

  /** 库句柄（aboutToAppear 打开；AppDatabase 内部有缓存单例） */
  private store: relationalStore.RdbStore | undefined = undefined;
  /** 恢复进来的草稿；保存 / 转正 / 丢弃都以它为准 */
  private draft: DraftEntry | undefined = undefined;
  /**
   * 标题用 RichEditor 而非 TextArea：真机实测 TextArea 空态光标是
   * 纺锤形 + 前 ~3s 选择手柄引导（caretColor / caretStyle 均不改形状），
   * RichEditor 空态是标准 2vp 竖线光标（已像素级验证），与 iOS 一致。
   */
  private titleEditor: RichEditorController = new RichEditorController();
  /**
   * 正文控制器（2.5，2026-10-18 回退备忘录式恢复接线）：驱动 RichBodyEditor；
   * 照片编辑方法（startPhotoPick / togglePhotoPosition 等）经工具条与锚点卡可达。
   */
  private bodyController: RichBodyController = new RichBodyController();
  /** controller 就绪标志：setTypingStyle / loadDocument 必须在组件绑定后调用 */
  private titleEditorReady: boolean = false;
  /** 草稿标题只注入一次（onReady 与 loadPageData 谁后到谁触发） */
  private draftInjectedTitle: boolean = false;
  /** 正文编辑器就绪（RichBodyEditor onReady；与 pageDataLoaded 双信号装载） */
  private bodyEditorReady: boolean = false;
  /** 草稿正文只注入一次（onReady 与 loadPageData 谁后到谁触发） */
  private draftInjectedBody: boolean = false;
  /** loadPageData 已备好草稿数据（无草稿 = 空正文，也算就绪） */
  private pageDataLoaded: boolean = false;
  /** 草稿块（装载正文编辑器用；无草稿 = 空数组） */
  private draftBlocks: ContentBlock[] = [];
  /** 路由参数带入的日记本名（从某本点「写一篇」时预选；草稿的选择优先） */
  private initialNotebookName: string = '';

  aboutToDisappear(): void {
    // 全屏浮层没关就被路由弹走（边滑返回）时，别把主框架 Tab 栏一直藏着
    AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, false);
  }

  aboutToAppear(): void {
    // 键盘避让：压缩页面跟随光标（默认 OFFSET 只保证聚焦输入框可见，
    // 心情/日记本会被键盘盖住；RESIZE_WITH_CARET 让内容收到键盘上方、可滚动）
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
    // 正文控制器回调接线（2.5/2.6 回退备忘录式恢复）：
    // 文本镜像（✓ 判定 / 字数）+ 照片锚点卡五路动作（长按全屏 / 功能条四项）
    this.bodyController.onTextChange = (text: string): void => {
      this.bodyText = text;
    };
    this.bodyController.onPhotoTap = (blockId: string): void => {
      this.openPhotoFullscreen(blockId);
    };
    this.bodyController.onPhotoTogglePosition = (blockId: string): void => {
      this.togglePhotoPosition(blockId);
    };
    this.bodyController.onPhotoToggleCover = (blockId: string): void => {
      this.togglePhotoCover(blockId);
    };
    this.bodyController.onPhotoRestyle = (blockId: string): void => {
      this.restylePhoto(blockId);
    };
    this.bodyController.onPhotoDelete = (blockId: string): void => {
      this.confirmDeletePhoto(blockId);
    };
    this.bodyController.onPhotoRemoved = (_blockId: string): void => {
      // 两段式退格 / 范围删除出的照片（页面方法外路径）：张数镜像跟着走
      this.bodyPhotoCount = this.bodyController.photoCount();
    };
    this.bodyController.onAudioRemoved = (_blockId: string): void => {
      // 卡片 ✕ / 两段式退格 / 范围删除出的录音（文件存盘时统一清）
      this.bodyAudioCount = this.bodyController.audioCount();
    };
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.readInitialNotebookParam();
      this.loadPageData(context);
    }
  }

  /** 路由参数「写一篇」入口带入的日记本名（BookDetail 传；其他入口没有） */
  private readInitialNotebookParam(): void {
    const raw: Object | undefined = this.getUIContext().getRouter().getParams();
    if (raw === undefined) {
      return;
    }
    const params = raw as Record<string, Object>;
    const value = params['initialNotebookName'];
    if (typeof value === 'string') {
      this.initialNotebookName = value;
    }
  }

  build() {
    Stack() {
      // Navigation 自定义标题栏：沉浸光感 Button 的官方生效范围（API 26，
      // 《沉浸光感常见问题》）；标题栏自动避让状态栏
      Navigation() {
        Column() {
          Scroll() {
          Column({ space: 16 }) {
            // 日期 + 星期 + 字数（有字才显示，R-ENTRY-06）
            Row() {
              Text(dayAndWeekday(new Date(), this.appLanguage))
                .fontSize(this.theme.captionFont.size)
                .fontWeight(this.theme.captionFont.weight)
                .fontFamily(this.theme.captionFont.family)
                .fontColor(this.theme.textTertiary)
                .letterSpacing(this.theme.letterSpacingWide)
              Blank()
              if (this.charCount() > 0) {
                Text($r('app.string.s_3aad2fe07a', this.charCount()))
                  .fontSize(this.theme.labelFont.size)
                  .fontWeight(this.theme.labelFont.weight)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textTertiary)
              }
            }
            .width('100%')

            // 从草稿恢复时说一声，否则用户会以为自己上次的东西还在别处
            if (this.didRestoreDraft) {
              Row({ space: 5 }) {
                // pencil_line 本机运行时缺资源渲染空白（2026-10-16 实测），
                // 换 square_and_pencil（早期稳定资源）
                SymbolGlyph($r('sys.symbol.square_and_pencil'))
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.theme.textTertiary])
                Text($r('app.string.s_eab9fafde7'))
                  .fontSize(this.theme.labelFont.size)
                  .fontWeight(this.theme.labelFont.weight)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textTertiary)
              }
            }

            // 此时此地（2.10，R-PLACE-01~04）：拿到天气/地点后胶囊可点开换地点；
            // 没拿到给轻量入口，不打扰写作
            this.weatherLocationRow()

            // 标题：可换行（最多三行，与详情页、书封面的实际呈现一致）
            // 光标色 = accent（对齐 iOS `.tint(accent)`：光标与文字区分，
            // 用文字近似色会让光标线叠进首字笔画、看起来像首字被劈开/遮挡）
            RichEditor({ controller: this.titleEditor })
              .placeholder($r('app.string.s_ec85a65494'), {
                font: {
                  size: this.theme.titleFont.size,
                  weight: this.theme.titleFont.weight,
                  family: this.theme.titleFont.family
                },
                fontColor: this.theme.textTertiary
              })
              .caretColor(this.theme.accent)
              .maxLines(3)
              .backgroundColor(Color.Transparent)
              // 上下留 2/4vp：RESIZE_WITH_CARET 只保证光标点进视口，贴边会让末行留在键盘底下；
              // 左右必须显式 0：不写会回退组件默认缩进
              .padding({ left: 0, right: 0, top: 2, bottom: 4 })
              // 空文档时高度自适应可能塌陷，保底一行（22fp × 1.5）
              .constraintSize({ minHeight: 34 })
              .width('100%')
              .onReady((): void => {
                this.titleEditorReady = true;
                this.titleEditor.setTypingStyle(this.titleTextStyle());
                this.injectDraftIntoEditors();
              })
              // ≤40、去换行（R-ENTRY-07）：onWillChange 拒绝变更，
              // 比「先输入再 sanitize 回写」干净（不闪、不打断 IME 组合）
              .onWillChange((value: RichEditorChangeValue): boolean => this.titleWillChange(value))
              .onDidChange((): void => {
                this.title = this.titleEditor.toStyledString({}).getString();
              })

            // 正文（2.5 RichBodyEditor，备忘录式：照片整行锚点卡 + 文字上下独立段；
            // 草稿装载走 onReady + pageDataLoaded 双信号，见 injectDraftIntoBody）
            RichBodyEditor({
              controller: this.bodyController,
              editable: true,
              onReady: (): void => {
                this.bodyEditorReady = true;
                this.injectDraftIntoBody();
              }
            })

            // 心情（单选、只读预设，R-ENTRY-09）
            Column({ space: 8 }) {
              Text($r('app.string.s_300ee58e24'))
                .fontSize(this.theme.captionFont.size)
                .fontWeight(this.theme.captionFont.weight)
                .fontFamily(this.theme.captionFont.family)
                .fontColor(this.theme.textTertiary)
              MoodSelector({
                moods: this.moods,
                selectedMoodName: this.moodName,
                onMoodPicked: (mood: MoodTag): void => {
                  this.moodName = mood.name;
                  this.moodColorHex = mood.colorHex;
                }
              })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            // 收进日记本（不选 = 只在「全部日记」里，R-ENTRY-10）
            Column({ space: 8 }) {
              Text($r('app.string.s_ff8c685438'))
                .fontSize(this.theme.captionFont.size)
                .fontWeight(this.theme.captionFont.weight)
                .fontFamily(this.theme.captionFont.family)
                .fontColor(this.theme.textTertiary)
              NotebookSelector({
                notebooks: this.notebooks,
                selectedNotebookName: this.selectedNotebookName,
                onToggle: (name: string): void => {
                  this.toggleNotebook(name);
                },
                onCreateTap: (): void => {
                  this.showCreateNotebook = true;
                }
              })
              // 一本都不选时说清楚去向，否则用户会担心这篇日记「没地方放」
              if (this.selectedNotebookName.length === 0) {
                Text($r('app.string.s_ce4ad523f3'))
                  .fontSize(this.theme.labelFont.size)
                  .fontWeight(this.theme.labelFont.weight)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textTertiary)
                  .transition(TransitionEffect.OPACITY)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({
            left: 20,
            right: 20,
            top: 16,
            bottom: 24
          })
          }
          .layoutWeight(1)
          .width('100%')
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)

          // 底部格式工具条（2.5 回退恢复）：四灯 + 照片键；键盘 RESIZE_WITH_CARET
          // 弹出时贴键盘顶（keyboardHeightChange 组件内自处理），收起落回安全区
          RichFormatToolbar({
            controller: this.bodyController,
            onCameraButtonTap: (): void => {
              this.startCameraFlow();
            },
            onPhotoButtonTap: (): void => {
              this.startPhotoPick();
            },
            onMicButtonTap: (): void => {
              this.startRecordingFlow();
            }
          })
        }
        .width('100%')
        .height('100%')
        // 地点选择器（2.10）：挂内容 Column——录音 sheet 已占 Navigation、
        // 相纸 sheet 已占根 Stack，同节点双 sheet 有覆盖风险，分开挂
        .bindSheet(this.showLocationPicker, this.LocationPickerBuilder(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          showClose: false,
          onDisappear: (): void => {
            this.showLocationPicker = false;
          }
        })
      }
      .title(this.topBar)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
      // 录音面板（2.7）：挂 Navigation（相纸 sheet 已占根 Stack 的 bindSheet，
      // 同节点双 sheet 有覆盖风险，分开挂）
      .bindSheet(this.showRecordingSheet, this.RecordingSheetBuilder(), {
        detents: [SheetSize.MEDIUM],
        showClose: false,
        onDisappear: (): void => {
          this.showRecordingSheet = false;
        }
      })

      // 返回确认弹窗（官方 @CustomDialog，CustomDialogController 挂窗口层，
      // 遮罩连顶栏一起盖住）；新建日记本弹窗（撞名判定在 createNotebook 里）
      if (this.showCreateNotebook) {
        CreateNotebookDialog({
          onCancel: (): void => {
            this.showCreateNotebook = false;
          },
          onCreate: (name: string): void => {
            this.showCreateNotebook = false;
            this.createNotebook(name);
          }
        })
      }

      // 照片全屏查看（2.6）：页面内条件浮层（Stack 末位 = 最顶层）。
      // 2026-10-17 真机定位弃用 bindContentCover：设为封面等 updatePhoto 序列后
      // 模态会进入「隐形挂载」态——aboutToAppear 有日志、零像素渲染、整页触摸
      // 被吞（12:38 干净复现，tap 穿透导致误存）；浮层自控层级与触摸，结构上
      // 消灭隐形模态层。转场在 PhotoFullScreenCover 根节点内置。
      if (this.showPhotoFullscreen) {
        this.PhotoFullscreenBuilder()
      }

      // 尺素相机（2.9）：页面内条件浮层（全屏照片同款挂法；自带转场与触摸）
      if (this.showCamera) {
        this.CameraBuilder()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
    // 相纸选择（2.6）：新照片选相纸 / 给已插照片换相纸共用（半高 sheet，iOS medium 同款）
    .bindSheet(this.showPaperSheet, this.PaperSheetBuilder(), {
      detents: [SheetSize.MEDIUM],
      showClose: false,
      onDisappear: (): void => {
        this.paperSheetPixelMap = undefined;
        this.pendingPickedPhoto = undefined;
        this.restylePhotoId = undefined;
      }
    })
  }

  // ---- 2.10 此时此地 ----

  /**
   * 内容胶囊要不要补描边：素笺/肯特的 cardBackground 与页面底同色
   * （FAF7F2/FAF7F2、FFFFFF/FFFFFF），胶囊底融进页面看不出「dock」形状
   * （2026-10-22 用户反馈：皮革正常、素笺/肯特不行）；皮革 card ≠ bg 自带
   * 可见深色底，不加边框保持原样。对 iOS 偏差（iOS 三主题同样融底），
   * 用户拍板单独优化，记录于 PROGRESS.md 2.10。
   * 主题色值均为 0xAARRGGBB 数字字面量，typeof 收窄后直接比较
   * （ThemeDebug colorToHex 同款前提）。
   */
  private weatherCapsuleNeedsOutline(): boolean {
    const card: ResourceColor = this.theme.cardBackground;
    const bg: ResourceColor = this.theme.background;
    if (typeof card === 'number' && typeof bg === 'number') {
      return card === bg;
    }
    return false;
  }

  /**
   * 「此时此地」行四态（iOS weatherLocationRow 同款，R-PLACE-01~04）：
   * 有内容 = 胶囊（点开地点选择器）+ 天气失败重试行；
   * 解析中 = 占位文案；权限拒 = 去设置引导；没取过 = 轻量入口。
   */
  @Builder
  private weatherLocationRow(): void {
    if (this.weatherBadgeHasContent()) {
      Column({ space: 8 }) {
        // 内容胶囊：天气徽标 + 「可改」暗示（不记位置时显示斜杠图标），点开选择器
        Row({ space: 6 }) {
          WeatherLocationBadge({
            weatherCode: this.weather.weatherCode,
            weatherInfo: this.weather.weatherInfo,
            locationInfo: this.effectivePlaceName(),
            fontColor: this.theme.textSecondary
          })
          SymbolGlyph(this.placeMode === PlaceMode.None
            ? $r('sys.symbol.map_slash') : $r('sys.symbol.chevron_down'))
            .fontSize(9)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textTertiary])
        }
        .alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(this.theme.cardBackground)
        // 融底主题补 0.5vp 描边让胶囊有形（同页笔记本标签的既有语言）
        .border({
          width: this.weatherCapsuleNeedsOutline() ? 0.5 : 0,
          color: this.theme.border
        })
        .borderRadius(14)
        .onClick((): void => {
          this.showLocationPicker = true;
        })

        // 天气单独失败：可点重试 + 错误码上屏（域+码，截图即可报，R-PLACE-04）
        if (this.weather.weatherFailed) {
          Column({ space: 1 }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(9)
                .fontWeight(FontWeight.Medium)
                .fontColor([this.theme.textTertiary])
              Text($r('app.string.s_f65ce37afd'))
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textTertiary)
            }
            if (this.weather.lastWeatherError.length > 0) {
              Text(this.weather.lastWeatherError)
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textTertiary)
                .opacity(0.6)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 2 })
          .onClick((): void => {
            this.startPlaceWeatherFetch();
          })
        }
      }
      .alignItems(HorizontalAlign.Start)
    } else if (this.weather.isResolving) {
      Text($r('app.string.s_bb69e30f5a'))
        .fontSize(this.theme.labelFont.size)
        .fontWeight(this.theme.labelFont.weight)
        .fontFamily(this.theme.labelFont.family)
        .fontColor(this.theme.textTertiary)
    } else if (this.weather.locationDenied) {
      // 权限被拒：系统不会再弹第二次，引导去系统设置（R-PLACE-03，不能点了没反应）
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.map_slash'))
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.textTertiary])
        Text($r('app.string.s_0cfc3b0e21'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
      }
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.openLocationSettings();
      })
    } else {
      // 还没取过：轻量入口（关了「记录位置」时只提天气）
      Row({ space: 4 }) {
        SymbolGlyph(AppPrefs.isLocationRecordingEnabled()
          ? $r('sys.symbol.location_north_up_right') : $r('sys.symbol.thermometer'))
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.textTertiary])
        if (AppPrefs.isLocationRecordingEnabled()) {
          Text($r('app.string.s_aaa25533ca'))
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.textTertiary)
        } else {
          Text($r('app.string.s_7645c5d19c'))
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.textTertiary)
        }
      }
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.startPlaceWeatherFetch();
      })
    }
  }

  /** 地点选择器 sheet 内容（2.10）：数据全来自当前解析状态与选择态 */
  @Builder
  private LocationPickerBuilder(): void {
    LocationPickerView({
      currentMode: this.placeMode,
      manualName: this.manualPlaceName,
      autoName: this.weather.locationInfo,
      latitude: this.weather.latitude,
      longitude: this.weather.longitude,
      hasCoordinate: this.weather.hasCoordinateForSearch(),
      onSelect: (mode: string, manualName: string): void => {
        this.placeMode = mode;
        if (mode === PlaceMode.Manual) {
          this.manualPlaceName = manualName;
        }
        this.showLocationPicker = false;
      },
      onCancel: (): void => {
        this.showLocationPicker = false;
      }
    })
  }

  /** 有没有可展示的天气 / 地名（iOS hasContent：任一即算） */
  private weatherBadgeHasContent(): boolean {
    return this.weather.weatherCode.length > 0 || this.weather.locationInfo.length > 0;
  }

  /** 最终写进日记的地名：auto 用解析值 / none 不记 / manual 用挑的（iOS effectivePlaceName） */
  private effectivePlaceName(): string {
    if (this.placeMode === PlaceMode.None) {
      return '';
    }
    if (this.placeMode === PlaceMode.Manual) {
      return this.manualPlaceName;
    }
    return this.weather.locationInfo;
  }

  /** 草稿里的 placeMode 归一化：认识 auto/none/manual，其余按 auto（旧数据不崩） */
  private validPlaceMode(raw: string): string {
    if (raw === PlaceMode.None || raw === PlaceMode.Manual) {
      return raw;
    }
    return PlaceMode.Auto;
  }

  /**
   * 发起「此时此地」解析：外部置解析态（首屏必刷），完成后 bump tick 兜底
   * （@State 类内部异步写在极端时序下不通知的保险，最终态一定渲染）。
   */
  private startPlaceWeatherFetch(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.weather.isResolving = true;
    this.weatherPlaceTick++;
    this.weather.requestLocationAndWeather(context).then((): void => {
      this.weatherPlaceTick++;
    });
  }

  /** 跳系统设置的本应用详情页（权限被拒引导，R-PLACE-03） */
  private openLocationSettings(): void {
    // 窄化到 UIAbilityContext：startAbility / abilityInfo 都在它上面
    // （getHostContext 返回基类 Context，项目既有模式同款窄化）
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      return;
    }
    context.startAbility({
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: {
        pushParams: context.abilityInfo.bundleName
      }
    }).catch((err: BusinessError): void => {
      hilog.error(DOMAIN, TAG, 'open settings failed: %{public}d %{public}s',
        err.code, err.message ?? '');
    });
  }

  // ---- 2.6 照片：相册选图 → 选相纸 → 光标处插入（R-RICH-03 / R-PHOTO-01） ----

  /** 工具条照片键：拉系统图库（免权限）选一张 → 弹相纸选择（2.9 起动态照片也走这里） */
  private async startPhotoPick(): Promise<void> {
    if (this.bodyController.photoCount() >= 5) {
      return; // 满 5 张（键已置灰，兜底）
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const picked = await PhotoLibraryPicker.pick(context);
    if (picked === undefined) {
      return; // 用户取消 / 解码失败：静默收场
    }
    this.pendingPickedPhoto = picked;
    this.restylePhotoId = undefined;
    this.paperSheetPixelMap = picked.pixelMap;
    this.showPaperSheet = true;
  }

  /** 相纸选择 sheet 内容（选完即插 / 换，无二次确认，iOS 同款；新照片带「放在左/右」分段） */
  @Builder
  PaperSheetBuilder() {
    if (this.paperSheetPixelMap !== undefined) {
      PaperStylePickerSheet({
        pixelMap: this.paperSheetPixelMap,
        showPositionPicker: this.restylePhotoId === undefined,
        onSelect: (style: PaperStyle, position: PhotoPosition): void => {
          this.onPaperStylePicked(style, position);
        },
        onCancel: (): void => {
          this.showPaperSheet = false;
        }
      })
    }
  }

  /** 选定相纸：换相纸（已有照片）或落盘新照片按所选边插到光标处 */
  private async onPaperStylePicked(style: PaperStyle, position: PhotoPosition): Promise<void> {
    this.showPaperSheet = false;
    const restyleId = this.restylePhotoId;
    if (restyleId !== undefined) {
      // 换相纸：只改块字段，文件不动
      const block = this.bodyController.photoBlocks.get(restyleId);
      if (block !== undefined) {
        block.paperStyle = style;
        this.bodyController.updatePhoto(block);
      }
      return;
    }
    const picked = this.pendingPickedPhoto;
    if (picked === undefined) {
      return;
    }
    // 新照片 → 光标处插入；动态照片原样字节落盘（R-PHOTO-03），普通照片重编码 q85
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const io = PhotoPaperIO.forFilesDir(context.filesDir);
    if (picked.isMovingPhoto) {
      await this.insertPickedMovingPhoto(picked, io, position, style);
      return;
    }
    const filename = `photo_${generateUuid().substring(0, 8)}.jpg`;
    const saved = await io.saveImage(picked.pixelMap, filename);
    if (!saved) {
      // iOS failed() 同款：落盘失败静默收场（不打断书写）
      hilog.error(DOMAIN, TAG, 'photo save failed %{public}s', filename);
      return;
    }
    this.insertedMediaNames.add(filename);
    const block = ContentBlock.makePhoto(generateUuid(), filename, undefined,
      position, style);
    if (!this.bodyController.insertPhoto(block)) {
      io.deleteImage(filename);
      this.insertedMediaNames.delete(filename);
      return;
    }
    this.bodyPhotoCount = this.bodyController.photoCount();
  }

  /**
   * 相册动态照片落盘插入：原图 + 视频原样字节 `photo_<uuid8>.jpg` / `.mp4`
   * （R-PHOTO-03，无 _full —— 相机动态照片才有配对未裁原图）；视频落盘失败
   * 退普通照片（原图原样字节还在，只是丢了动态）。
   */
  private async insertPickedMovingPhoto(picked: PickedLibraryPhoto, io: PhotoPaperIO,
    position: PhotoPosition, style: PaperStyle): Promise<void> {
    const still = picked.stillBuffer;
    const video = picked.videoBuffer;
    if (still === undefined || video === undefined) {
      return;
    }
    const base = generateUuid().substring(0, 8);
    const stillName = `photo_${base}.jpg`;
    const videoName = `photo_${base}.mp4`;
    if (!await io.saveData(still, stillName)) {
      hilog.error(DOMAIN, TAG, 'moving photo still save failed %{public}s', stillName);
      return;
    }
    this.insertedMediaNames.add(stillName);
    const videoSaved = await io.saveData(video, videoName);
    if (!videoSaved) {
      hilog.error(DOMAIN, TAG, 'moving photo video save failed %{public}s', videoName);
    } else {
      this.insertedMediaNames.add(videoName);
    }
    const block = ContentBlock.makePhoto(generateUuid(), stillName,
      videoSaved ? videoName : undefined, position, style);
    if (!this.bodyController.insertPhoto(block)) {
      io.deleteImage(stillName);
      io.deleteImage(videoName);
      this.insertedMediaNames.delete(stillName);
      this.insertedMediaNames.delete(videoName);
      return;
    }
    this.bodyPhotoCount = this.bodyController.photoCount();
  }

  // ---- 2.6 照片：全屏查看与编辑（R-PHOTO-01 / R-RICH-05） ----

  /** 全屏查看内容：⚠️ 菜单编辑回调全给（写日记页可编辑）；删除确认在组件内 */
  @Builder
  PhotoFullscreenBuilder() {
    if (this.fullscreenPhoto !== undefined) {
      PhotoFullScreenCover({
        photo: this.fullscreenPhoto,
        onDismiss: (): void => {
          this.closePhotoFullscreen();
        },
        onTogglePosition: (): void => {
          this.toggleFullscreenPosition();
        },
        onToggleCover: (): void => {
          this.toggleFullscreenCover();
        },
        onRestyle: (): void => {
          this.startFullscreenRestyle();
        },
        onDelete: (): void => {
          this.deleteFullscreenPhoto();
        }
      })
    }
  }

  private openPhotoFullscreen(blockId: string): void {
    const block = this.photoBlockById(blockId);
    if (block === undefined) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'open fullscreen id=%{public}s', blockId);
    this.fullscreenPhoto = block;
    this.showPhotoFullscreen = true;
  }

  /** 当前正文里找照片（onPhotoTap 的 blockId → 本体；侧表直查） */
  private photoBlockById(blockId: string): ContentBlock | undefined {
    const block = this.bodyController.photoBlocks.get(blockId);
    if (block !== undefined && block.type === ContentBlockType.Photo) {
      return block;
    }
    return undefined;
  }

  private closePhotoFullscreen(): void {
    hilog.info(DOMAIN, TAG, 'close fullscreen requested');
    this.showPhotoFullscreen = false;
    this.fullscreenPhoto = undefined;
  }

  /** 全屏浮层开/关 → 联动藏/显主框架浮动 Tab 栏（@Watch） */
  private onPhotoFullscreenChanged(): void {
    AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, this.showPhotoFullscreen);
  }

  // ---- 2.9 尺素相机：拍照 → 落盘链 → 光标处插入（R-PHOTO-01/03/04） ----

  /** 工具条拍照键：满 5 张不开（键已置灰，兜底）；权限申请在相机浮层内（被拒有引导态） */
  private startCameraFlow(): void {
    if (this.bodyController.photoCount() >= 5) {
      return;
    }
    this.showCamera = true;
  }

  /** 相机浮层开/关 → 联动藏/显主框架浮动 Tab 栏（全屏照片同款） */
  private onCameraOverlayChanged(): void {
    AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, this.showCamera);
  }

  /** 相机浮层内容（页面内条件浮层） */
  @Builder
  private CameraBuilder() {
    PaperCameraView({
      onCapture: (shot: CameraShot, squarePixelMap: image.PixelMap, style: PaperStyle): void => {
        this.showCamera = false;
        this.onCameraCaptured(shot, squarePixelMap, style);
      },
      onCancel: (): void => {
        this.showCamera = false;
      }
    })
  }

  /**
   * 相机拍完「写下这一刻」：落盘链（显示图重编码 q85 + 动态配对原样字节，
   * R-PHOTO-03）→ 光标处插入（iOS `PhotoInsertFlow.insert` 相机分支同款）。
   * 配对落盘失败自动退化普通照片（saveCameraShot 内处理）。
   */
  private async onCameraCaptured(shot: CameraShot, squarePixelMap: image.PixelMap,
    style: PaperStyle): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const io = PhotoPaperIO.forFilesDir(context.filesDir);
    const files = await saveCameraShot(io, shot, squarePixelMap);
    if (files === undefined) {
      // iOS failed() 同款：落盘失败静默收场（不打断书写）
      hilog.error(DOMAIN, TAG, 'camera shot save failed');
      return;
    }
    const names = files.allFilenames();
    for (const name of names) {
      this.insertedMediaNames.add(name);
    }
    const block = ContentBlock.makePhoto(generateUuid(), files.displayFilename,
      files.videoFilename, PhotoPosition.Right, style);
    block.livePhotoStillFilename = files.fullStillFilename;
    if (!this.bodyController.insertPhoto(block)) {
      for (const name of names) {
        io.deleteImage(name);
        this.insertedMediaNames.delete(name);
      }
      return;
    }
    this.bodyPhotoCount = this.bodyController.photoCount();
  }

  /** 靠左 / 靠右互换（功能条 / 双击秒换边 / 全屏菜单同路；blockId 定位） */
  private togglePhotoPosition(blockId: string): void {
    const block = this.bodyController.photoBlocks.get(blockId);
    if (block === undefined) {
      return;
    }
    block.position = block.position === PhotoPosition.Left ? PhotoPosition.Right : PhotoPosition.Left;
    this.bodyController.updatePhoto(block);
  }

  /** 设为 / 取消封面（一篇最多一张：开新的先清别的） */
  private togglePhotoCover(blockId: string): void {
    const block = this.bodyController.photoBlocks.get(blockId);
    if (block === undefined) {
      return;
    }
    const turningOn = block.isCover !== true;
    this.bodyController.photoBlocks.forEach((other: ContentBlock): void => {
      if (other.id !== block.id) {
        other.isCover = undefined;
      }
    });
    block.isCover = turningOn ? true : undefined;
    this.bodyController.updatePhoto(block);
  }

  /** 换相纸：加载这张照片的缩略图重开相纸 sheet */
  private async restylePhoto(blockId: string): Promise<void> {
    const block = this.bodyController.photoBlocks.get(blockId);
    if (block === undefined) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const pixelMap = await PhotoPaperIO.forFilesDir(context.filesDir).loadImage(block.photoFilename);
    if (pixelMap === undefined) {
      hilog.warn(DOMAIN, TAG, 'restyle load failed %{public}s', block.photoFilename);
      return;
    }
    this.restylePhotoId = block.id;
    this.paperSheetPixelMap = pixelMap;
    this.showPaperSheet = true;
  }

  /** 功能条「删除」：先确认（AlertDialog，destructive 语义）再删 */
  private confirmDeletePhoto(blockId: string): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.s_c488684daf'),
      message: $r('app.string.s_223d9e4e74'),
      primaryButton: {
        value: $r('app.string.s_4d0b4688c7'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.s_c488684daf'),
        fontColor: '#B5473A',
        action: (): void => {
          this.deletePhotoById(blockId);
        }
      },
      cancel: (): void => {
      }
    });
  }

  /** 删除照片：出正文、清文件等存盘时统一做（全屏菜单已过组件内确认） */
  private deletePhotoById(blockId: string): void {
    this.bodyController.deletePhoto(blockId);
    this.bodyPhotoCount = this.bodyController.photoCount();
  }

  // ---- 全屏菜单旧入口 → blockId 化（fullscreenPhoto 只是定位用） ----

  private toggleFullscreenPosition(): void {
    const block = this.fullscreenPhoto;
    if (block !== undefined) {
      this.togglePhotoPosition(block.id);
    }
  }

  private toggleFullscreenCover(): void {
    const block = this.fullscreenPhoto;
    if (block !== undefined) {
      this.togglePhotoCover(block.id);
    }
  }

  private async startFullscreenRestyle(): Promise<void> {
    const block = this.fullscreenPhoto;
    if (block !== undefined) {
      await this.restylePhoto(block.id);
    }
  }

  private deleteFullscreenPhoto(): void {
    const block = this.fullscreenPhoto;
    if (block !== undefined) {
      this.deletePhotoById(block.id);
    }
  }

  /**
   * 存盘 / 放弃时清没被引用的照片文件（iOS removeUnusedMedia）：
   * 本次新落盘的 + 草稿带进来的，凡不在最终块里的删掉；文件真删（不留撤销余地，
   * 摇一摇撤销是 iOS 独有，鸿蒙 2.x 不做）。
   */
  private cleanupUnreferencedPhotos(keptBlocks: ContentBlock[]): void {
    const referenced = new Set<string>();
    for (const block of keptBlocks) {
      const names = [block.photoFilename, block.livePhotoVideoFilename, block.livePhotoStillFilename];
      for (const name of names) {
        if (name !== undefined) {
          referenced.add(name);
        }
      }
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const io = PhotoPaperIO.forFilesDir(context.filesDir);
    const tracked = new Set<string>();
    this.insertedMediaNames.forEach((name: string): void => {
      tracked.add(name);
    });
    this.restoredPhotoNames.forEach((name: string): void => {
      tracked.add(name);
    });
    for (const name of tracked) {
      if (!referenced.has(name)) {
        io.deleteImage(name);
      }
    }
    this.insertedMediaNames = new Set<string>(); // restored 留着跨多次存盘用（iOS 同款）
  }

  /** 放弃：本次新落盘的文件全清（草稿自己的文件走 deleteDraftMedia） */
  private deleteAllInsertedPhotos(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined || this.insertedMediaNames.size === 0) {
      this.insertedMediaNames = new Set<string>();
      return;
    }
    const io = PhotoPaperIO.forFilesDir(context.filesDir);
    for (const name of this.insertedMediaNames) {
      io.deleteImage(name);
    }
    this.insertedMediaNames = new Set<string>();
  }

  /** 草稿带进来的照片文件名记账（存盘清理时认「草稿原有、这次删掉的」） */
  private collectRestoredPhotoNames(blocks: ContentBlock[]): void {
    for (const block of blocks) {
      if (block.type !== ContentBlockType.Photo) {
        continue;
      }
      const names = [block.photoFilename, block.livePhotoVideoFilename, block.livePhotoStillFilename];
      for (const name of names) {
        if (name !== undefined) {
          this.restoredPhotoNames.add(name);
        }
      }
    }
  }

  // ---- 2.7 录音：权限 → 面板 → 光标所在段下面插入（R-ENTRY-08 / R-RICH-04） ----

  /** 录音面板 sheet 内容（录制 / 试听 / 插入由组件自持，页面只接结果） */
  @Builder
  RecordingSheetBuilder() {
    VoiceRecordingSheet({
      micDenied: this.recordingMicDenied,
      onInsert: (relativePath: string): void => {
        this.onRecordingInserted(relativePath);
      },
      onCancel: (): void => {
        this.showRecordingSheet = false;
      }
    })
  }

  /**
   * 工具条 mic 键：先申请麦克风权限（系统弹窗，首次 / 每次拒绝后再试都走它），
   * 授权与否都开面板 —— 被拒时面板渲染「去设置」引导态（iOS requestRecordingPermission 同款）
   */
  private async startRecordingFlow(): Promise<void> {
    if (this.bodyController.audioCount() >= 3) {
      return; // 满 3 段（键已置灰，兜底）
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    let granted = false;
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context,
        ['ohos.permission.MICROPHONE']);
      granted = result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'request mic permission failed: %{public}s', JSON.stringify(err));
      granted = false;
    }
    this.recordingMicDenied = !granted;
    this.showRecordingSheet = true;
  }

  /** 面板「插入」：落好盘的录音（"audio/xxx.m4a"）插到光标所在段下面 */
  private onRecordingInserted(relativePath: string): void {
    const block = ContentBlock.makeAudio(generateUuid(), relativePath);
    if (!this.bodyController.insertAudio(block)) {
      // 插不进（理论上不可达：面板开着就不可能满 3 段）：文件不留孤儿
      const context = this.getUIContext().getHostContext();
      if (context !== undefined) {
        deleteAudioFile(context.filesDir, relativePath);
      }
      this.showRecordingSheet = false;
      return;
    }
    this.insertedAudioPaths.add(relativePath);
    this.bodyAudioCount = this.bodyController.audioCount();
    this.showRecordingSheet = false;
  }

  /** 存盘 / 存草稿时清没被引用的录音文件（照片 cleanupUnreferencedPhotos 同款） */
  private cleanupUnreferencedAudios(keptBlocks: ContentBlock[]): void {
    const referenced = new Set<string>(blocksAudioPaths(keptBlocks));
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const tracked = new Set<string>();
    this.insertedAudioPaths.forEach((path: string): void => {
      tracked.add(path);
    });
    this.restoredAudioPaths.forEach((path: string): void => {
      tracked.add(path);
    });
    for (const path of tracked) {
      if (!referenced.has(path)) {
        deleteAudioFile(context.filesDir, path);
      }
    }
    this.insertedAudioPaths = new Set<string>();
  }

  /** 放弃：本次新落盘的录音全清（草稿自己的文件走 deleteDraftMedia） */
  private deleteAllInsertedAudios(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      for (const path of this.insertedAudioPaths) {
        deleteAudioFile(context.filesDir, path);
      }
    }
    this.insertedAudioPaths = new Set<string>();
  }

  /** 草稿带进来的录音路径记账（存盘清理用） */
  private collectRestoredAudioPaths(blocks: ContentBlock[]): void {
    for (const path of blocksAudioPaths(blocks)) {
      this.restoredAudioPaths.add(path);
    }
  }

  /** 顶栏（Navigation 标题栏内）：左上返回、右上完成
   * （同一种分量；能不能点由 enabled 表达） */
  @Builder
  topBar() {
    Row() {
      CircleIconButton({
        iconRes: $r('sys.symbol.chevron_left'),
        iconSize: 14,
        onTap: (): void => {
          this.attemptExit();
        }
      })
      Blank()
      CircleIconButton({
        iconRes: $r('sys.symbol.checkmark'),
        iconSize: 14,
        // 直接引用 @State 的表达式（@Prop 依赖分析跟不进方法体），
        // 与 hasContent() 等价：文字 / 照片 / 录音任一有就算写了（iOS hasContent）
        pressEnabled: this.bodyText.trim().length > 0 || this.bodyPhotoCount > 0 ||
          this.bodyAudioCount > 0,
        onTap: (): void => {
          this.saveEntryAndClose();
        }
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  }

  // ---- 判定（V1 组件不许用 getter，全部普通方法） ----

  /** 正文有没有内容（✓ 能不能点）。照片 / 录音也算（iOS hasContent）；只有标题不算 */
  private hasContent(): boolean {
    return this.bodyText.trim().length > 0 || this.bodyPhotoCount > 0 ||
      this.bodyAudioCount > 0;
  }

  /** 顶部字数 */
  private charCount(): number {
    return this.bodyText.length;
  }

  /** 块列表 → 正文纯文本（字数 / ✓ 判定镜像，2.5b） */
  private bodyTextOf(blocks: ContentBlock[]): string {
    let text = '';
    for (const block of blocks) {
      if (block.type === ContentBlockType.Text && block.text !== undefined) {
        text += block.text;
      }
    }
    return text;
  }

  /** 块列表 → 照片张数（✓ 判定镜像） */
  private photoCountOf(blocks: ContentBlock[]): number {
    let count = 0;
    for (const block of blocks) {
      if (block.type === ContentBlockType.Photo) {
        count++;
      }
    }
    return count;
  }

  /** 块列表 → 录音段数（✓ 判定镜像） */
  private audioCountOf(blocks: ContentBlock[]): number {
    let count = 0;
    for (const block of blocks) {
      if (block.type === ContentBlockType.Audio) {
        count++;
      }
    }
    return count;
  }

  // ---- RichEditor（标题 / 正文） ----

  /**
   * 标题文字样式（typingStyle 与草稿注入共用）。
   * serif 字形完整高度（ascent+descent）≈1.35em，默认行框仅≈1.1em 会裁字形上部；
   * lineHeight 22fp × 1.36 ≈ 30fp 留足空间，halfLeading 让半行距上下对称（接近 iOS 行为）。
   */
  private titleTextStyle(): RichEditorTextStyle {
    return {
      fontSize: this.theme.titleFont.size,
      fontWeight: this.theme.titleFont.weight,
      fontFamily: this.theme.titleFont.family,
      fontColor: this.theme.textPrimary,
      lineHeight: 30,
      halfLeading: true
    };
  }

  /** 正文文字样式已移入 RichTextAppearance（2.5 三主题各一套，素笺 17fp） */

  /**
   * 标题变更拦截（R-ENTRY-07）：换行直接拒绝；超出 40 字拒绝。
   * 返回 false = 本次变更不进文档，比 sanitize 回写干净（不闪、不打断输入法组合）。
   */
  private titleWillChange(value: RichEditorChangeValue): boolean {
    let incoming: string = '';
    for (const span of value.replacedSpans) {
      incoming += span.value;
    }
    if (incoming.includes('\n')) {
      return false;
    }
    const removed: number = (value.rangeBefore?.end ?? 0) - (value.rangeBefore?.start ?? 0);
    if (this.title.length - removed + incoming.length > 40) {
      return false;
    }
    return true;
  }

  /**
   * 草稿标题注入标题编辑器：onReady 与 loadPageData 谁后到谁触发，只注一次。
   * 历史草稿标题可能超 40 / 带换行（旧版本存入），注入前就地清洗。
   * （正文走 injectDraftIntoBody 双信号装载。）
   */
  private injectDraftIntoEditors(): void {
    if (this.titleEditorReady && !this.draftInjectedTitle) {
      this.draftInjectedTitle = true;
      const restored: string = JournalEntry.sanitizedTitle(this.title);
      this.title = restored;
      if (restored.length > 0) {
        this.titleEditor.addTextSpan(restored, { style: this.titleTextStyle() });
      }
    }
  }

  /**
   * 草稿正文装载：编辑器 onReady 与 loadPageData 双信号到齐才装一次
   * （格式 / 分段 / 照片锚点随块恢复，2.5 装载语义）。
   */
  private injectDraftIntoBody(): void {
    if (this.bodyEditorReady && this.pageDataLoaded && !this.draftInjectedBody) {
      this.draftInjectedBody = true;
      this.bodyController.loadDocument(
        editorDocumentFromBlocks(this.draftBlocks),
        anchoredBlocksOf(this.draftBlocks));
      this.bodyPhotoCount = this.bodyController.photoCount();
      this.bodyAudioCount = this.bodyController.audioCount();
    }
  }

  // ---- 数据加载 ----

  private async loadPageData(context: common.Context): Promise<void> {
    try {
      const store = await AppDatabase.open(context);
      this.store = store;
      // 恢复草稿（全局一份，R-ENTRY-04/05）
      const draft = await DraftRepository.loadCurrentDraft(store);
      if (draft !== null) {
        this.draft = draft;
        this.title = draft.title;
        // 草稿正文按块备好（injectDraftIntoBody 装载编辑器，格式 / 分段 / 照片随块恢复）
        this.draftBlocks = draft.contentBlocks;
        this.collectRestoredPhotoNames(draft.contentBlocks);
        this.collectRestoredAudioPaths(draft.contentBlocks);
        this.bodyText = this.bodyTextOf(draft.contentBlocks);
        this.bodyPhotoCount = this.photoCountOf(draft.contentBlocks);
        this.bodyAudioCount = this.audioCountOf(draft.contentBlocks);
        this.moodName = draft.mood;
        this.moodColorHex = draft.moodColorHex ?? '';
        const restored = restoredNotebookSelection(draft.tags, [this.initialNotebookName]);
        this.selectedNotebookName = restored.length > 0 ? restored[0] : '';
        this.didRestoreDraft = true;
        // 此时此地（2.10）：原样还原存草稿那一刻的快照，不重新定位（R-ENTRY-05）
        this.weather.restore(draft.weatherCode ?? '', draft.weatherInfo ?? '', draft.locationInfo ?? '');
        this.placeMode = this.validPlaceMode(draft.placeMode);
        this.manualPlaceName = draft.manualPlaceName ?? '';
        // RichEditor 不能用 text 参数绑定，草稿标题在 controller 就绪后注入
        this.injectDraftIntoEditors();
      }
      // 有无草稿都算数据就绪（空数组 = 空正文），装载信号二
      this.pageDataLoaded = true;
      this.injectDraftIntoBody();
      this.moods = await MoodRepository.fetchAllMoods(store);
      this.notebooks = await NotebookRepository.fetchAllNotebooks(store);
      if (draft === null) {
        // 新的一篇：自动取此时此地（R-PLACE-01）；有草稿则用还原的快照，不重取
        this.startPlaceWeatherFetch();
        // 从某本点「写一篇」进来：没有草稿选择时预选那本
        // （名字对不上库里任何一本时原样保留，与 iOS 传 tag.name 同款不设防）
        const restored = restoredNotebookSelection([], [this.initialNotebookName]);
        this.selectedNotebookName = restored.length > 0 ? restored[0] : '';
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadPageData failed: %{public}s', JSON.stringify(err));
      this.presentSaveFailed();
    }
  }

  // ---- 退出 / 保存（R-ENTRY-01~05） ----

  /** 按返回：空白页直接走，不拿弹窗打扰（R-ENTRY-02） */
  private attemptExit(): void {
    if (!this.hasContent()) {
      this.getUIContext().getRouter().back();
      return;
    }
    this.exitDialogController.open();
  }

  /**
   * 系统返回（手势 / 返回键）决策：路由页 onBackPress 拦截 +1 到这里。
   * 新建日记本弹窗开着先收它；有内容弹保存确认；全空直接退。
   * 保存确认弹窗开着时系统返回由弹窗自己消费（关闭=取消），不会到这。
   */
  private onSystemBackTick(): void {
    if (this.showCreateNotebook) {
      this.showCreateNotebook = false;
      return;
    }
    this.attemptExit();
  }

  /**
   * 点 ✓ = 完成了一篇书写，这一刻才产生正式日记（R-ENTRY-01）。
   * `createdAt` = `date` = 此刻（R-ENTRY-06 日期不可改）；草稿只删记录、不删媒体（R-ENTRY-03）。
   */
  private async saveEntryAndClose(): Promise<void> {
    const store = this.store;
    if (store === undefined) {
      this.presentSaveFailed();
      return;
    }
    const now = Date.now();
    const entry = new JournalEntry(generateUuid(), now, now, now);
    entry.title = this.title.trim();
    entry.mood = this.moodName;
    if (this.moodColorHex.length > 0) {
      entry.moodColorHex = this.moodColorHex;
    }
    if (this.selectedNotebookName.length > 0) {
      entry.tags = [this.selectedNotebookName];
    }
    // 此时此地（2.10）：天气 + 最终地名（选择器可换 / 不显示）写进日记，
    // 只存本地不上传（R-PLACE-05）
    if (this.weather.weatherCode.length > 0) {
      entry.weatherCode = this.weather.weatherCode;
    }
    if (this.weather.weatherInfo.length > 0) {
      entry.weatherInfo = this.weather.weatherInfo;
    }
    const entryPlaceName = this.effectivePlaceName();
    if (entryPlaceName.length > 0) {
      entry.locationInfo = entryPlaceName;
    }
    // 正文块（编辑器文档读回 + 照片/录音侧表拆回，2.5 保存链路）
    const blocks = composeCleanedBlocks(
      blocksWithEditorDocument(this.bodyController.currentDocument(),
        this.bodyController.anchoredSideTable(), generateUuid),
      generateUuid);
    entry.setContentBlocks(blocks, now); // 唯一写入口：content / wordCount / audioURLs 同步派生
    try {
      await EntryRepository.insertEntry(store, entry);
      if (this.draft !== undefined) {
        await DraftRepository.deleteDraftRecord(store, this.draft.id);
      }
      // 转正的文件归日记了；这次新落盘又没进正文的清掉（iOS removeUnusedMedia）
      this.cleanupUnreferencedPhotos(blocks);
      this.cleanupUnreferencedAudios(blocks);
      // 保存成功后主页刷新由 Index.onPageShow 的 reload tick 驱动
      //（主页被本页盖住时赋值不渲染，写入侧通知不可用，见 HomeLogic 注释）
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveEntry failed: %{public}s', JSON.stringify(err));
      this.presentSaveFailed();
      return;
    }
    this.getUIContext().getRouter().back();
  }

  /** 「保存草稿」：存草稿 → 关闭 → toast「草稿已保存」（先关再提示：toast 挂在主界面上） */
  private async saveDraftAndClose(): Promise<void> {
    const saved = await this.saveDraft();
    if (!saved) {
      return; // 保存失败留在编辑页，用户还能再试
    }
    this.getUIContext().getRouter().back();
    this.env.errors.present(this.stringFromResource($r('app.string.s_9d84cfe84d')),
      ErrorToastKind.Success, 2000);
  }

  /** 存草稿。已有草稿就地更新，没有才新建 —— 保证全局只有一份 */
  private async saveDraft(): Promise<boolean> {
    const store = this.store;
    if (store === undefined) {
      this.presentSaveFailed();
      return false;
    }
    const now = Date.now();
    const draft = this.draft ?? new DraftEntry(generateUuid(), now, now);
    draft.title = this.title;
    // 正文块（编辑器文档读回 + 照片/录音侧表拆回，2.5 保存链路）
    const blocks = composeCleanedBlocks(
      blocksWithEditorDocument(this.bodyController.currentDocument(),
        this.bodyController.anchoredSideTable(), generateUuid),
      generateUuid);
    draft.setContentBlocks(blocks, now);
    draft.mood = this.moodName;
    draft.moodColorHex = this.moodColorHex.length > 0 ? this.moodColorHex : undefined;
    draft.tags = this.selectedNotebookName.length > 0 ? [this.selectedNotebookName] : [];
    // 此时此地（2.10）：快照存草稿——恢复时原样还原、不重新定位（R-ENTRY-05）
    draft.weatherCode = this.weather.weatherCode.length > 0 ? this.weather.weatherCode : undefined;
    draft.weatherInfo = this.weather.weatherInfo.length > 0 ? this.weather.weatherInfo : undefined;
    const draftPlaceName = this.effectivePlaceName();
    draft.locationInfo = draftPlaceName.length > 0 ? draftPlaceName : undefined;
    draft.placeMode = this.placeMode;
    draft.manualPlaceName = this.placeMode === PlaceMode.Manual ? this.manualPlaceName : undefined;
    draft.audioURLs = blocksAudioPaths(blocks); // 录音从块派生（2.7）
    try {
      await DraftRepository.saveDraft(store, draft);
      this.draft = draft;
      // 草稿还引用的文件留给草稿；这次删掉没进草稿的清掉（iOS removeUnusedMedia）
      this.cleanupUnreferencedPhotos(blocks);
      this.cleanupUnreferencedAudios(blocks);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveDraft failed: %{public}s', JSON.stringify(err));
      this.presentSaveFailed();
      return false;
    }
  }

  /**
   * 「不保存」：这篇就此作废 —— 连同已存在的草稿一起丢弃（记录 + 引用的媒体，R-ENTRY-03）。
   * 误触的出口是点遮罩取消（回到编辑），不是让「不保存」变得半吊子。
   */
  private async discardAndClose(): Promise<void> {
    const store = this.store;
    if (store !== undefined && this.draft !== undefined) {
      try {
        const context = this.getUIContext().getHostContext();
        if (context !== undefined) {
          MediaStorageService.create(context, store).deleteDraftMedia(this.draft);
        }
        await DraftRepository.deleteDraftRecord(store, this.draft.id);
      } catch (err) {
        // 丢弃路径的清理失败只记日志：不能因为删不干净挡住用户离开
        hilog.error(DOMAIN, TAG, 'discard draft failed: %{public}s', JSON.stringify(err));
      }
    }
    // 本次新落盘又没进草稿的照片 / 录音文件一并清掉（不留孤儿文件）
    this.deleteAllInsertedPhotos();
    this.deleteAllInsertedAudios();
    this.getUIContext().getRouter().back();
  }

  // ---- 日记本（R-ENTRY-10） ----

  /** 单选：点另一本 = 换，点已选 = 取消 */
  private toggleNotebook(name: string): void {
    this.selectedNotebookName = this.selectedNotebookName === name ? '' : name;
  }

  /** 当场新建：撞名（忽略大小写 / 全半角）直接选中已有那本；建完自动选中 */
  private async createNotebook(rawName: string): Promise<void> {
    const store = this.store;
    if (store === undefined) {
      return;
    }
    const typed = cleanedName(rawName);
    if (typed.length === 0) {
      return;
    }
    const key = nameKey(typed);
    for (const notebook of this.notebooks) {
      if (nameKey(notebook.name) === key) {
        this.selectedNotebookName = notebook.name;
        return;
      }
    }
    const now = Date.now();
    const notebook = new Notebook(generateUuid(), typed, now, now);
    // 写日记页顺手新建没机会挑颜色：取书架上用得最少的颜色（05 §4.1，iOS quietestColor）
    notebook.colorId = quietestColor(this.notebooks);
    notebook.sortOrder = nextSortOrder(this.notebooks.map((n: Notebook): number => n.sortOrder));
    try {
      await NotebookRepository.insertNotebook(store, notebook);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'createNotebook failed: %{public}s', JSON.stringify(err));
      this.presentSaveFailed();
      return;
    }
    try {
      this.notebooks = await NotebookRepository.fetchAllNotebooks(store);
    } catch (err) {
      // 重读失败就本地补上：库里已经有了，别让用户看到列表少一本
      hilog.warn(DOMAIN, TAG, 'reload notebooks failed: %{public}s', JSON.stringify(err));
      this.notebooks = this.notebooks.concat([notebook]);
    }
    this.selectedNotebookName = typed;
  }

  // ---- 文案 ----

  private presentSaveFailed(): void {
    this.env.errors.present(this.stringFromResource($r('app.string.s_40525a7328')),
      ErrorToastKind.Error, 4000);
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
