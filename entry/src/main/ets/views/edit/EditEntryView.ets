/**
 * 编辑已有日记页（10_BUILD_MANUAL.md 2.4）。对应 iOS `Views/Edit/EditEntryView.swift`。
 *
 * - 全屏，**只能经 ✕ / ✓ 退出**（R-ENTRY-11）：系统返回（手势 / 按键）在
 *   路由页 onBackPress 整个拦下，不留第三条出口
 * - ✕ = 放弃这次编辑（不弹确认，iOS 同款——写日记页的 ‹ 才有存草稿的歧义，
 *   这里 glyph 用 ✕ 诚实表达「丢」）；✓ = 保存
 * - 复用写日记页的编辑组件与排版（MoodSelector / NotebookSelector /
 *   CircleIconButton / RichEditor 标题 + 2.5 RichBodyEditor 正文——
 *   2026-10-18 回退备忘录式，绕排连环平台缺陷后产品拍板，见 09 Q23）；
 *   底部四灯工具条 + 照片键与写日记页同款
 * - 保存必须走 entry.setContentBlocks（派生 content / wordCount / updatedAt，
 *   R-RICH-10 —— iOS 在这页出过「直接写 content 被静默丢弃」的 bug）
 * - 老日记录音补进正文（R-RICH-09）：散在 audioURLs 里没进过正文的录音
 *   打开编辑时补成块挂末尾（blocksWithLooseAudio，2.7）
 */
import { relationalStore } from '@kit.ArkData';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import {
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_HIDE_TAB_BAR
} from '../../services/ImmersiveChrome';
import { AppEnvironment, STORAGE_KEY_APP_ENVIRONMENT } from '../../environment/AppEnvironment';
import { ErrorToastKind, createDefaultErrorPresenter } from '../../environment/ErrorPresenter';
import { AppDatabase } from '../../data/Database';
import { EntryRepository } from '../../data/EntryRepository';
import { NotebookRepository } from '../../data/NotebookRepository';
import { MoodRepository } from '../../data/MoodRepository';
import { composeCleanedBlocks } from '../../data/ComposeLogic';
import { JournalEntry } from '../../models/JournalEntry';
import {
  ContentBlock,
  ContentBlockType,
  PaperStyle,
  PhotoPosition,
  blocksAudioPaths,
  blocksWithLooseAudio
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
import { MoodTag } from '../../models/Mood';
import { Notebook, cleanedName, nameKey, nextSortOrder, quietestColor } from '../../models/Notebook';
import { generateUuid } from '../../models/Uuid';
import { CircleIconButton } from '../compose/CircleIconButton';
import { MoodSelector } from '../compose/MoodSelector';
import { NotebookSelector } from '../compose/NotebookSelector';
import { CreateNotebookDialog } from '../compose/CreateNotebookDialog';
import { dayAndWeekday } from '../../services/AppDateFormatters';

const DOMAIN = 0x0000;
const TAG = 'EditEntryView';

@Component
export struct EditEntryView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_APP_ENVIRONMENT) env: AppEnvironment =
    new AppEnvironment(createDefaultErrorPresenter());
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  @State title: string = '';
  @State moodName: string = '';
  @State moodColorHex: string = '';
  @State selectedNotebookName: string = '';
  @State moods: MoodTag[] = [];
  @State notebooks: Notebook[] = [];
  @State showCreateNotebook: boolean = false;
  // ---- 2.6 照片 ----
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
  /** 本次编辑新落盘的照片文件（✕ 不留；✓ 后没被引用的清掉，iOS insertedMediaNames） */
  private insertedMediaNames: Set<string> = new Set<string>();
  /** 进页面时日记已有的照片文件（正文里删掉的，✓ 时才真删文件） */
  private originalPhotoNames: Set<string> = new Set<string>();
  // ---- 2.7 录音 ----
  /** 录音面板 sheet（工具条 mic 键 → 先申请麦克风权限再开） */
  @State showRecordingSheet: boolean = false;
  /** 麦克风权限被拒（面板渲染「去设置」引导态） */
  @State recordingMicDenied: boolean = false;
  /** 本次编辑新落盘的录音文件（✕ 不留；✓ 后没被引用的清掉） */
  private insertedAudioPaths: Set<string> = new Set<string>();
  /** 进页面时日记已有的录音文件（正文里删掉的，✓ 时才真删文件） */
  private originalAudioPaths: Set<string> = new Set<string>();
  /** ✓ 存过了：离开页面不再清这次新加的文件（iOS didSave） */
  private didSave: boolean = false;

  /** 路由参数：日记 id */
  private entryId: string = '';
  /** 进页面时查出的这篇；✓ 在它身上改再写回。
   *  @State：日期行读它；普通字段不进 build 依赖追踪，加载完也不会刷新日期
   *  （2026-10-18 真机实测编辑 10-17 条目日期停留在当天）。与详情页同款声明。 */
  @State entry: JournalEntry | undefined = undefined;
  private store: relationalStore.RdbStore | undefined = undefined;
  /** 标题与写日记页同款 RichEditor（空态标准竖线光标，已像素级验证） */
  private titleEditor: RichEditorController = new RichEditorController();
  /**
   * 正文控制器（2.5，2026-10-18 回退备忘录式恢复接线）：驱动 RichBodyEditor；
   * 照片编辑方法（startPhotoPick / togglePhotoPosition 等）经工具条与锚点卡可达。
   */
  private bodyController: RichBodyController = new RichBodyController();
  private titleEditorReady: boolean = false;
  /** loadEntry 已把原文备好（标题注入要等它与 onReady 都到齐） */
  private entryLoaded: boolean = false;
  /** 原文标题只注入一次（onReady 与 loadEntry 都到才注入；单边到就消费标志会把
   *  空标题锁死、原文标题永不出现——2026-10-18 真机实测必现） */
  private injectedTitle: boolean = false;
  /** 正文编辑器就绪（RichBodyEditor onReady；与 entryLoaded 双信号装载） */
  private bodyEditorReady: boolean = false;
  /** 原文正文只装载一次（onReady 与 loadEntry 都到才装） */
  private injectedBody: boolean = false;
  /** 原文块（装载正文编辑器用） */
  private originalBlocks: ContentBlock[] = [];

  aboutToDisappear(): void {
    // 全屏浮层没关就被路由弹走（边滑返回）时，别把主框架 Tab 栏一直藏着
    AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, false);
    // 没保存就离开（✕）：这次新加的照片 / 录音文件不留（iOS onDisappear 同款）
    if (this.didSave || (this.insertedMediaNames.size === 0 && this.insertedAudioPaths.size === 0)) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const io = PhotoPaperIO.forFilesDir(context.filesDir);
    for (const name of this.insertedMediaNames) {
      io.deleteImage(name);
    }
    this.insertedMediaNames = new Set<string>();
    for (const path of this.insertedAudioPaths) {
      deleteAudioFile(context.filesDir, path);
    }
    this.insertedAudioPaths = new Set<string>();
  }

  aboutToAppear(): void {
    // 键盘避让与写日记页一致：内容收到键盘上方、可滚动
    // （灯态由工具条自己订阅 controller.onFlagsChange，页面不再整页重渲染）
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
    // 正文控制器回调接线（2.5/2.6 回退备忘录式恢复）：
    // 照片锚点卡五路动作（长按全屏 / 功能条四项）；文本镜像这页不用（✓ 恒可点）
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
    Stack() {
      // Navigation 自定义标题栏：沉浸光感 Button 的官方生效范围（API 26，
      // 《沉浸光感常见问题》）；标题栏自动避让状态栏
      Navigation() {
        Column() {
          Scroll() {
          Column({ space: 16 }) {
            // 日期 + 星期（写的是哪一天，编辑不改这个归属）
            Text(this.dateLineText())
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.textTertiary)
              .letterSpacing(this.theme.letterSpacingWide)
              .width('100%')

            // 标题：可换行（最多三行，与详情页呈现一致）；≤40、去换行（R-ENTRY-07）
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
              .padding({ left: 0, right: 0, top: 2, bottom: 4 })
              .constraintSize({ minHeight: 34 })
              .width('100%')
              .onReady((): void => {
                this.titleEditorReady = true;
                this.titleEditor.setTypingStyle(this.titleTextStyle());
      this.injectOriginalIntoEditors();
      this.injectOriginalIntoBody();
              })
              .onWillChange((value: RichEditorChangeValue): boolean => this.titleWillChange(value))
              .onDidChange((): void => {
                this.title = this.titleEditor.toStyledString({}).getString();
              })

            // 正文（2.5 RichBodyEditor，备忘录式：照片整行锚点卡 + 文字上下独立段；
            // 原文装载走 onReady + entryLoaded 双信号，见 injectOriginalIntoBody）
            RichBodyEditor({
              controller: this.bodyController,
              editable: true,
              onReady: (): void => {
                this.bodyEditorReady = true;
                this.injectOriginalIntoBody();
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

            // 收进日记本（一篇最多一本，R-ENTRY-10）
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
              if (this.selectedNotebookName.length === 0) {
                Text($r('app.string.s_ce4ad523f3'))
                  .fontSize(this.theme.labelFont.size)
                  .fontWeight(this.theme.labelFont.weight)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textTertiary)
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

          // 底部格式工具条（2.5 回退恢复）：四灯 + 照片键 + 录音键；与写日记页同款
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
      }
      .title(this.topBar)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
      // 录音面板（2.7）：挂 Navigation（相纸 sheet 已占根 Stack 的 bindSheet）
      .bindSheet(this.showRecordingSheet, this.RecordingSheetBuilder(), {
        detents: [SheetSize.MEDIUM],
        showClose: false,
        onDisappear: (): void => {
          this.showRecordingSheet = false;
        }
      })

      // 新建日记本弹窗（与写日记页同款；撞名判定在 createNotebook 里）
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
      // 2026-10-17 真机定位弃用 bindContentCover：与根 Stack 上的 bindSheet
      // 同节点双绑（官方 FAQ faqs-arkui-1375）+ 设为封面后模态「隐形挂载」
      // （appear 有日志、零渲染、整页触摸被吞，12:23 实测穿透到本页触发误存）；
      // 浮层自控层级与触摸，结构上消灭隐形模态层。转场在 PhotoFullScreenCover 根节点内置。
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
    }
  }

  // ---- 2.6 照片：全屏查看与编辑（R-PHOTO-01 / R-RICH-05） ----

  /** 全屏查看内容：⚠️ 菜单编辑回调全给（编辑页可编辑）；删除确认在组件内 */
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
    this.showPhotoFullscreen = false;
    this.fullscreenPhoto = undefined;
  }

  /** 全屏浮层开/关 → 联动藏/显主框架浮动 Tab 栏（@Watch） */
  private onPhotoFullscreenChanged(): void {
    AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, this.showPhotoFullscreen);
  }

  // ---- 2.9 尺素相机：拍照 → 落盘链 → 光标处插入（与写日记页同款） ----

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

  /** 删除照片：出正文；文件 ✓ 时统一清（全屏菜单已过组件内确认） */
  private deletePhotoById(blockId: string): void {
    this.bodyController.deletePhoto(blockId);
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

  /** 顶栏（Navigation 标题栏内）：✕ 放弃 / ✓ 保存（R-ENTRY-11：只有这两个出口） */
  @Builder
  topBar() {
    Row() {
      CircleIconButton({
        iconRes: $r('sys.symbol.xmark'),
        iconSize: 13,
        onTap: (): void => {
          this.getUIContext().getRouter().back();
        }
      })
      Blank()
      CircleIconButton({
        iconRes: $r('sys.symbol.checkmark'),
        iconSize: 14,
        onTap: (): void => {
          this.saveAndClose();
        }
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  }

  // ---- RichEditor（标题 / 正文，与写日记页同一套排版） ----

  /** 日期行文案：加载完成前空串（不闪「今天」——那是错误归属），完成后按 entry.date */
  private dateLineText(): string {
    const entry = this.entry;
    if (entry === undefined) {
      return '';
    }
    return dayAndWeekday(new Date(entry.date), this.appLanguage);
  }

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

  /** 标题变更拦截（R-ENTRY-07）：换行拒绝；超 40 字拒绝（原文已注入，按现长度算） */
  private titleWillChange(value: RichEditorChangeValue): boolean {
    let incoming: string = '';
    for (const span of value.replacedSpans) {
      incoming += span.value;
    }
    if (incoming.includes('\n')) {
      return false;
    }
    const removed: number = (value.rangeBefore?.end ?? 0) - (value.rangeBefore?.start ?? 0);
    if (this.title.length - removed + incoming.length > JournalEntry.titleMaxLength) {
      return false;
    }
    return true;
  }

  /** 原文注入：onReady 与 loadEntry 谁后到谁触发，标题只注一次（注入前清洗老标题）。 */
  private injectOriginalIntoEditors(): void {
    if (this.titleEditorReady && this.entryLoaded && !this.injectedTitle) {
      this.injectedTitle = true;
      const restored: string = JournalEntry.sanitizedTitle(this.title);
      this.title = restored;
      if (restored.length > 0) {
        this.titleEditor.addTextSpan(restored, { style: this.titleTextStyle() });
      }
    }
  }

  /**
   * 原文正文装载：编辑器 onReady 与 loadEntry 双信号到齐才装一次
   * （格式 / 分段 / 照片锚点随块恢复，2.5 装载语义）。
   */
  private injectOriginalIntoBody(): void {
    if (this.bodyEditorReady && this.entryLoaded && !this.injectedBody) {
      this.injectedBody = true;
      this.bodyController.loadDocument(
        editorDocumentFromBlocks(this.originalBlocks),
        anchoredBlocksOf(this.originalBlocks));
    }
  }

  // ---- 数据加载 ----

  private async loadEntry(context: common.Context): Promise<void> {
    try {
      const store = await AppDatabase.open(context);
      this.store = store;
      const loaded = await EntryRepository.fetchEntryById(store, this.entryId);
      if (loaded === null) {
        // 已被并发删除：没有可编辑的东西，直接回详情（详情自己的重查会兜底）
        hilog.warn(DOMAIN, TAG, 'entry not found id=%{public}s', this.entryId);
        this.getUIContext().getRouter().back();
        return;
      }
      this.entry = loaded;
      this.title = loaded.title;
      this.entryLoaded = true;
      // 墨迹上下文（2.8）：干湿基准 = 原日记写下时刻，本次编辑会话 = 现在
      // （之后新打的字记此刻，24h 内算补记、跨天干掉）
      this.bodyController.setInkContext(loaded.createdAt / 1000, Date.now() / 1000);
      // 正文按块备好（injectOriginalIntoBody 装载编辑器，格式 / 分段 / 照片录音随块恢复）；
      // 散在 audioURLs 里没进过正文的录音补成块挂末尾（R-RICH-09）；原媒体文件记账，✓ 后清理用
      this.originalBlocks = blocksWithLooseAudio(loaded.contentBlocks, loaded.audioURLs, generateUuid);
      this.collectOriginalPhotoNames(this.originalBlocks);
      this.collectOriginalAudioPaths(this.originalBlocks);
      this.moodName = loaded.mood;
      this.moodColorHex = loaded.moodColorHex ?? '';
      this.selectedNotebookName = loaded.tags.length > 0 ? loaded.tags[0] : '';
      this.injectOriginalIntoEditors();
      this.moods = await MoodRepository.fetchAllMoods(store);
      this.notebooks = await NotebookRepository.fetchAllNotebooks(store);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadEntry failed id=%{public}s: %{public}s', this.entryId, JSON.stringify(err));
    }
  }

  // ---- 保存（R-ENTRY-11 / R-RICH-10） ----

  /**
   * ✓：在原 entry 上改（title / mood / tags / 内容块），内容必经
   * setContentBlocks（派生 content / wordCount / updatedAt），再整篇写回。
   * 详情页返回后经 reload tick 重查，看到的就是新内容。
   */
  private async saveAndClose(): Promise<void> {
    const store = this.store;
    const entry = this.entry;
    if (store === undefined || entry === undefined) {
      this.presentSaveFailed();
      return;
    }
    const now = Date.now();
    entry.title = this.title.trim();
    entry.mood = this.moodName;
    entry.moodColorHex = this.moodColorHex.length > 0 ? this.moodColorHex : undefined;
    entry.tags = this.selectedNotebookName.length > 0 ? [this.selectedNotebookName] : [];
    // 正文块（编辑器文档读回 + 照片/录音侧表拆回，2.5 保存链路）
    const blocks = composeCleanedBlocks(
      blocksWithEditorDocument(this.bodyController.currentDocument(),
        this.bodyController.anchoredSideTable(), generateUuid),
      generateUuid);
    entry.setContentBlocks(blocks, now); // 唯一写入口：content / wordCount / audioURLs / updatedAt 同步派生
    try {
      await EntryRepository.updateEntry(store, entry);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'update entry failed id=%{public}s: %{public}s', entry.id, JSON.stringify(err));
      this.presentSaveFailed();
      return;
    }
    this.didSave = true;
    // 正文里删掉的照片 / 录音（原有的、这次新加又删的）这时才真删文件（iOS save 同款）
    this.cleanupUnreferencedPhotos(blocks);
    this.cleanupUnreferencedAudios(blocks);
    this.getUIContext().getRouter().back();
  }

  /**
   * ✓ 后清没被引用的照片文件：原有 ∪ 这次新加，凡不在最终块里的删掉
   * （iOS originalPhotoNames.union(insertedMediaNames) 同款）。
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
    this.originalPhotoNames.forEach((name: string): void => {
      tracked.add(name);
    });
    this.insertedMediaNames.forEach((name: string): void => {
      tracked.add(name);
    });
    for (const name of tracked) {
      if (!referenced.has(name)) {
        io.deleteImage(name);
      }
    }
    this.insertedMediaNames = new Set<string>();
  }

  /** 进页面时日记已有的照片文件名记账（正文里删掉的，✓ 时才真删） */
  private collectOriginalPhotoNames(blocks: ContentBlock[]): void {
    for (const block of blocks) {
      if (block.type !== ContentBlockType.Photo) {
        continue;
      }
      const names = [block.photoFilename, block.livePhotoVideoFilename, block.livePhotoStillFilename];
      for (const name of names) {
        if (name !== undefined) {
          this.originalPhotoNames.add(name);
        }
      }
    }
  }

  // ---- 2.7 录音：权限 → 面板 → 光标所在段下面插入（与写日记页同款） ----

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

  /** 工具条 mic 键：先申请麦克风权限（系统弹窗），授权与否都开面板（被拒渲染引导态） */
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

  /** 面板「插入」：落好盘的录音插到光标所在段下面 */
  private onRecordingInserted(relativePath: string): void {
    const block = ContentBlock.makeAudio(generateUuid(), relativePath);
    if (!this.bodyController.insertAudio(block)) {
      // 插不进（理论上不可达）：文件不留孤儿
      const context = this.getUIContext().getHostContext();
      if (context !== undefined) {
        deleteAudioFile(context.filesDir, relativePath);
      }
      this.showRecordingSheet = false;
      return;
    }
    this.insertedAudioPaths.add(relativePath);
    this.showRecordingSheet = false;
  }

  /** ✓ 后清没被引用的录音文件：原有 ∪ 这次新加（照片 cleanup 同款） */
  private cleanupUnreferencedAudios(keptBlocks: ContentBlock[]): void {
    const referenced = new Set<string>(blocksAudioPaths(keptBlocks));
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const tracked = new Set<string>();
    this.originalAudioPaths.forEach((path: string): void => {
      tracked.add(path);
    });
    this.insertedAudioPaths.forEach((path: string): void => {
      tracked.add(path);
    });
    for (const path of tracked) {
      if (!referenced.has(path)) {
        deleteAudioFile(context.filesDir, path);
      }
    }
    this.insertedAudioPaths = new Set<string>();
  }

  /** 进页面时日记已有的录音路径记账（正文里删掉的，✓ 时才真删） */
  private collectOriginalAudioPaths(blocks: ContentBlock[]): void {
    for (const path of blocksAudioPaths(blocks)) {
      this.originalAudioPaths.add(path);
    }
  }

  // ---- 日记本（R-ENTRY-10，与写日记页同款单选） ----

  private toggleNotebook(name: string): void {
    this.selectedNotebookName = this.selectedNotebookName === name ? '' : name;
  }

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
    // 顺手新建没机会挑颜色：取书架上用得最少的颜色（05 §4.1，iOS quietestColor）
    notebook.colorId = quietestColor(this.notebooks);
    notebook.sortOrder = nextSortOrder(this.notebooks.map((n: Notebook): number => n.sortOrder));
    try {
      await NotebookRepository.insertNotebook(store, notebook);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'createNotebook failed: %{public}s', JSON.stringify(err));
      return;
    }
    try {
      this.notebooks = await NotebookRepository.fetchAllNotebooks(store);
    } catch (err) {
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
