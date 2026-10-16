/**
 * 编辑已有日记页（10_BUILD_MANUAL.md 2.4）。对应 iOS `Views/Edit/EditEntryView.swift`。
 *
 * - 全屏，**只能经 ✕ / ✓ 退出**（R-ENTRY-11）：系统返回（手势 / 按键）在
 *   路由页 onBackPress 整个拦下，不留第三条出口
 * - ✕ = 放弃这次编辑（不弹确认，iOS 同款——写日记页的 ‹ 才有存草稿的歧义，
 *   这里 glyph 用 ✕ 诚实表达「丢」）；✓ = 保存
 * - 复用写日记页的编辑组件与排版（MoodSelector / NotebookSelector /
 *   CircleIconButton / RichEditor 标题 + RichBodyEditor 富文本正文，2.5），
 *   行为与 iOS 一致
 * - 保存必须走 entry.setContentBlocks（派生 content / wordCount / updatedAt，
 *   R-RICH-10 —— iOS 在这页出过「直接写 content 被静默丢弃」的 bug）
 * - 老日记录音补进正文（R-RICH-09）：v1 无录音，2.8 接（09 Q25）
 */
import { relationalStore } from '@kit.ArkData';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import {
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP
} from '../../services/ImmersiveChrome';
import { AppEnvironment, STORAGE_KEY_APP_ENVIRONMENT } from '../../environment/AppEnvironment';
import { ErrorToastKind, createDefaultErrorPresenter } from '../../environment/ErrorPresenter';
import { AppDatabase } from '../../data/Database';
import { EntryRepository } from '../../data/EntryRepository';
import { NotebookRepository } from '../../data/NotebookRepository';
import { MoodRepository } from '../../data/MoodRepository';
import { composeCleanedBlocks } from '../../data/ComposeLogic';
import { JournalEntry } from '../../models/JournalEntry';
import { ContentBlock } from '../../models/ContentBlock';
import {
  RichEditorDocument,
  blocksWithEditorDocument,
  editorDocumentFromBlocks
} from '../../models/RichDocument';
import { RichBodyController, RichBodyEditor } from '../components/richtext/RichBodyEditor';
import { RichFormatToolbar } from '../components/richtext/RichFormatToolbar';
import { MoodTag } from '../../models/Mood';
import { Notebook, cleanedName, nameKey, nextSortOrder } from '../../models/Notebook';
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

  /** 路由参数：日记 id */
  private entryId: string = '';
  /** 进页面时查出的这篇；✓ 在它身上改再写回 */
  private entry: JournalEntry | undefined = undefined;
  private store: relationalStore.RdbStore | undefined = undefined;
  /** 标题与写日记页同款 RichEditor（空态标准竖线光标，已像素级验证） */
  private titleEditor: RichEditorController = new RichEditorController();
  /** 正文富文本控制器（2.5：格式灯 / 选中菜单 / 文档装载读回都在它身上） */
  private bodyController: RichBodyController = new RichBodyController();
  private titleEditorReady: boolean = false;
  private bodyReady: boolean = false;
  /** 原文只注入一次（onReady 与 loadEntry 谁后到谁触发） */
  private injectedTitle: boolean = false;
  private injectedBody: boolean = false;
  /** 原文的编辑器文档（loadEntry 建好，bodyReady 后装载） */
  private originalDoc: RichEditorDocument | undefined = undefined;

  aboutToAppear(): void {
    // 键盘避让与写日记页一致：内容收到键盘上方、可滚动
    // （灯态由工具条自己订阅 controller.onFlagsChange，页面不再整页重渲染）
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
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
            Text(dayAndWeekday(new Date(this.entryDateMillis()), this.appLanguage))
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
              })
              .onWillChange((value: RichEditorChangeValue): boolean => this.titleWillChange(value))
              .onDidChange((): void => {
                this.title = this.titleEditor.toStyledString({}).getString();
              })

            // 正文（2.5 富文本，注入原文）
            RichBodyEditor({
              controller: this.bodyController,
              editable: true,
              onReady: (): void => {
                this.bodyReady = true;
                this.injectOriginalIntoEditors();
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

          // 底部格式工具条（2.5）：与写日记页同款，间距与灯态镜像由工具条自管
          RichFormatToolbar({ controller: this.bodyController })
        }
        .width('100%')
        .height('100%')
      }
      .title(this.topBar)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')

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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
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

  private entryDateMillis(): number {
    return this.entry?.date ?? Date.now();
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

  /** 原文注入：onReady 与 loadEntry 谁后到谁触发，各自只注一次（注入前清洗老标题） */
  private injectOriginalIntoEditors(): void {
    if (this.titleEditorReady && !this.injectedTitle) {
      this.injectedTitle = true;
      const restored: string = JournalEntry.sanitizedTitle(this.title);
      this.title = restored;
      if (restored.length > 0) {
        this.titleEditor.addTextSpan(restored, { style: this.titleTextStyle() });
      }
    }
    if (this.bodyReady && !this.injectedBody) {
      this.injectedBody = true;
      // 原文文档整篇装载（格式 / 分段随 span 注入）
      this.bodyController.loadDocument(this.originalDoc ?? new RichEditorDocument());
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
      // 正文按块转成编辑器文档（格式 / 分段随文档装载恢复）
      this.originalDoc = editorDocumentFromBlocks(loaded.contentBlocks);
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
    // 正文读回 → 块（2.5：格式随 TextStyleRun 存盘；照片 / 录音锚点 2.6/2.7 接）
    const blocks = composeCleanedBlocks(
      blocksWithEditorDocument(this.bodyController.currentDocument(),
        new Map<string, ContentBlock>(), generateUuid), generateUuid);
    entry.setContentBlocks(blocks, now); // 唯一写入口：content / wordCount / audioURLs / updatedAt 同步派生
    try {
      await EntryRepository.updateEntry(store, entry);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'update entry failed id=%{public}s: %{public}s', entry.id, JSON.stringify(err));
      this.presentSaveFailed();
      return;
    }
    this.getUIContext().getRouter().back();
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
