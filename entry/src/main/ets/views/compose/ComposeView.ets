/**
 * 写日记页 v1（10_BUILD_MANUAL.md 2.1，纯文本）。对应 iOS `Views/Compose/ComposeView.swift`。
 *
 * - 全屏：左上返回（chevron：退出≠丢弃，可以存草稿）、右上 ✓（**只有点 ✓ 才算完成一篇**，
 *   R-ENTRY-01）；正文空时 ✓ 只降透明度不可点
 * - 左上返回：有内容 → 「不保存 / 保存草稿」（点遮罩=取消，R-ENTRY-02/03）；全空直接退出
 * - 进页面恢复草稿（全局一份，R-ENTRY-04/05），顶部提示「接着上次没写完的」
 * - 日期自动取当下、不可改（R-ENTRY-06）；标题 ≤40、去换行、最多三行（R-ENTRY-07）
 * - v1 不做：照片 / 录音 / 天气地点 / 格式工具条（2.5~2.10 各自的卡片）
 */
import { relationalStore } from '@kit.ArkData';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { dayAndWeekday } from '../../services/AppDateFormatters';
import {
  STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP
} from '../../services/ImmersiveChrome';
import { AppEnvironment, STORAGE_KEY_APP_ENVIRONMENT } from '../../environment/AppEnvironment';
import { ErrorToastKind, createDefaultErrorPresenter } from '../../environment/ErrorPresenter';
import { AppDatabase } from '../../data/Database';
import { DraftRepository } from '../../data/DraftRepository';
import { EntryRepository } from '../../data/EntryRepository';
import { NotebookRepository } from '../../data/NotebookRepository';
import { MoodRepository } from '../../data/MoodRepository';
import {
  bodyTextFromBlocks,
  composeCleanedBlocks,
  restoredNotebookSelection
} from '../../data/ComposeLogic';
import { JournalEntry } from '../../models/JournalEntry';
import { ContentBlock, blocksAudioPaths } from '../../models/ContentBlock';
import { MoodTag } from '../../models/Mood';
import { Notebook, cleanedName, nameKey, nextSortOrder } from '../../models/Notebook';
import { DraftEntry } from '../../models/Draft';
import { generateUuid } from '../../models/Uuid';
import { MediaStorageService } from '../../services/MediaStorageService';
import { CircleIconButton } from './CircleIconButton';
import { MoodSelector } from './MoodSelector';
import { NotebookSelector } from './NotebookSelector';
import { DraftExitDialog } from './DraftExitDialog';
import { CreateNotebookDialog } from './CreateNotebookDialog';

const DOMAIN = 0x0000;
const TAG = 'ComposeView';

@Component
export struct ComposeView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_APP_ENVIRONMENT) env: AppEnvironment =
    new AppEnvironment(createDefaultErrorPresenter());
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  @State title: string = '';
  @State bodyText: string = '';
  @State moodName: string = '';
  @State moodColorHex: string = '';
  @State selectedNotebookName: string = '';
  @State didRestoreDraft: boolean = false;
  @State moods: MoodTag[] = [];
  @State notebooks: Notebook[] = [];
  @State showExitDialog: boolean = false;
  @State showCreateNotebook: boolean = false;

  /** 库句柄（aboutToAppear 打开；AppDatabase 内部有缓存单例） */
  private store: relationalStore.RdbStore | undefined = undefined;
  /** 恢复进来的草稿；保存 / 转正 / 丢弃都以它为准 */
  private draft: DraftEntry | undefined = undefined;
  /**
   * 标题 / 正文用 RichEditor 而非 TextArea：真机实测 TextArea 空态光标是
   * 纺锤形 + 前 ~3s 选择手柄引导（caretColor / caretStyle 均不改形状），
   * RichEditor 空态是标准 2vp 竖线光标（已像素级验证），与 iOS 一致。
   */
  private titleEditor: RichEditorController = new RichEditorController();
  private bodyEditor: RichEditorController = new RichEditorController();
  /** controller 就绪标志：setTypingStyle / addTextSpan 必须在组件绑定后调用 */
  private titleEditorReady: boolean = false;
  private bodyEditorReady: boolean = false;
  /** 草稿文本只注入一次（onReady 与 loadPageData 谁后到谁触发） */
  private draftInjectedTitle: boolean = false;
  private draftInjectedBody: boolean = false;

  aboutToAppear(): void {
    // 键盘避让：压缩页面跟随光标（默认 OFFSET 只保证聚焦输入框可见，
    // 心情/日记本会被键盘盖住；RESIZE_WITH_CARET 让内容收到键盘上方、可滚动）
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.loadPageData(context);
    }
  }

  build() {
    Stack() {
      Column() {
        // 顶栏：左上返回、右上完成（同一种分量；能不能点由 enabled 表达）
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
            // 直接引用 @State bodyText 的表达式（@Prop 依赖分析跟不进方法体），
            // 与 hasContent() 等价：v1 正文就是全部内容
            pressEnabled: this.bodyText.trim().length > 0,
            onTap: (): void => {
              this.saveEntryAndClose();
            }
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: this.safeAreaTopVp + 6, bottom: 6 })

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
                SymbolGlyph($r('sys.symbol.pencil_line'))
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

            // 正文（v1 多行纯文本；占位符与正文同字号，落在光标位置）
            // 初始只占一行，换行 / 写满自动长高，心情与日记本随之依次下移（对齐 iOS 自适应高度）
            RichEditor({ controller: this.bodyEditor })
              .placeholder($r('app.string.s_74bd07ef78'), {
                font: {
                  size: this.theme.bodyFont.size,
                  weight: this.theme.bodyFont.weight,
                  family: this.theme.bodyFont.family
                },
                fontColor: this.theme.textTertiary
              })
              .caretColor(this.theme.accent)
              .backgroundColor(Color.Transparent)
              // 上下内边距：RESIZE_WITH_CARET 只保证光标点进视口，
              // padding(0) 时光标紧贴组件底缘 → 末行下半截留在键盘底下
              // （「颜色在上文字在下」）；左右显式 0 防回退默认缩进
              .padding({ left: 0, right: 0, top: 2, bottom: 4 })
              // 空文档时高度自适应可能塌陷，保底一行（14fp × 1.5）
              .constraintSize({ minHeight: 26 })
              .width('100%')
              .onReady((): void => {
                this.bodyEditorReady = true;
                this.bodyEditor.setTypingStyle(this.bodyTextStyle());
                this.injectDraftIntoEditors();
              })
              .onDidChange((): void => {
                this.bodyText = this.bodyEditor.toStyledString({}).getString();
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
            bottom: this.safeAreaBottomVp + 24
          })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')

      // 返回确认弹窗（挂在最外层，遮罩连顶栏一起盖住）
      if (this.showExitDialog) {
        DraftExitDialog({
          onDiscard: (): void => {
            this.showExitDialog = false;
            this.discardAndClose();
          },
          onSave: (): void => {
            this.showExitDialog = false;
            this.saveDraftAndClose();
          },
          onCancel: (): void => {
            this.showExitDialog = false;
          }
        })
      }

      // 新建日记本弹窗（撞名判定在 createNotebook 里）
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

  // ---- 判定（V1 组件不许用 getter，全部普通方法） ----

  /** 正文有没有内容（✓ 能不能点）。标题不算 —— 只有标题没有正文，✓ 仍不可点 */
  private hasContent(): boolean {
    return this.bodyText.trim().length > 0;
  }

  /** 顶部字数 */
  private charCount(): number {
    return this.bodyText.length;
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

  /** 正文文字样式：14fp × 1.43 ≈ 20fp 行高，理由同上 */
  private bodyTextStyle(): RichEditorTextStyle {
    return {
      fontSize: this.theme.bodyFont.size,
      fontWeight: this.theme.bodyFont.weight,
      fontFamily: this.theme.bodyFont.family,
      fontColor: this.theme.textPrimary,
      lineHeight: 20,
      halfLeading: true
    };
  }

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
   * 草稿文本注入编辑器：onReady 与 loadPageData 谁后到谁触发，各自只注一次。
   * 历史草稿标题可能超 40 / 带换行（旧版本存入），注入前就地清洗。
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
    if (this.bodyEditorReady && !this.draftInjectedBody) {
      this.draftInjectedBody = true;
      if (this.bodyText.length > 0) {
        this.bodyEditor.addTextSpan(this.bodyText, { style: this.bodyTextStyle() });
      }
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
        this.bodyText = bodyTextFromBlocks(draft.contentBlocks);
        this.moodName = draft.mood;
        this.moodColorHex = draft.moodColorHex ?? '';
        const restored = restoredNotebookSelection(draft.tags, []);
        this.selectedNotebookName = restored.length > 0 ? restored[0] : '';
        this.didRestoreDraft = true;
        // RichEditor 不能用 text 参数绑定，草稿文本在 controller 就绪后注入
        this.injectDraftIntoEditors();
      }
      this.moods = await MoodRepository.fetchAllMoods(store);
      this.notebooks = await NotebookRepository.fetchAllNotebooks(store);
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
    this.showExitDialog = true;
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
    const blocks = composeCleanedBlocks(
      [ContentBlock.makeText(generateUuid(), this.bodyText)], generateUuid);
    entry.setContentBlocks(blocks, now); // 唯一写入口：content / wordCount / audioURLs 同步派生
    try {
      await EntryRepository.insertEntry(store, entry);
      if (this.draft !== undefined) {
        await DraftRepository.deleteDraftRecord(store, this.draft.id);
      }
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
    const blocks = composeCleanedBlocks(
      [ContentBlock.makeText(generateUuid(), this.bodyText)], generateUuid);
    draft.setContentBlocks(blocks, now);
    draft.mood = this.moodName;
    draft.moodColorHex = this.moodColorHex.length > 0 ? this.moodColorHex : undefined;
    draft.tags = this.selectedNotebookName.length > 0 ? [this.selectedNotebookName] : [];
    draft.audioURLs = blocksAudioPaths(blocks); // v1 恒为空，录音在 2.7
    try {
      await DraftRepository.saveDraft(store, draft);
      this.draft = draft;
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
