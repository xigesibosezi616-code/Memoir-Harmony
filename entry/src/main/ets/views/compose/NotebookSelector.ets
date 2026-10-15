/**
 * 「收进日记本」单选 + 当场新建（10_BUILD_MANUAL.md 2.1，R-ENTRY-10）。
 * 对应 iOS `Views/Compose/TagSelector.swift`（数据上日记本就是 `tags` 里的名字）。
 *
 * - 按书架顺序列出全部日记本，**单选**：点另一本 = 换，点已选 = 取消
 * - 一本都不选 = 只在「全部日记」里（不需要写任何东西，下面那行提示只把这件事告诉用户）
 * - 当场新建的弹窗由父组件（ComposeView）渲染 —— 弹窗要盖满全屏，
 *   留在本组件里只能盖住横滑区
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { bookColorHex, isLightBookColor, Notebook } from '../../models/Notebook';

@Component
export struct NotebookSelector {
  @Prop notebooks: Notebook[] = [];
  @Prop selectedNotebookName: string = '';
  onToggle: (name: string) => void = (_name: string): void => {};
  onCreateTap: () => void = (): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.notebooks, (notebook: Notebook) => {
          this.notebookChip(notebook)
        }, (notebook: Notebook): string => notebook.id)

        // 「新建」：虚线描边的轻入口
        Row({ space: 2 }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textTertiary])
          Text($r('app.string.s_0cda8d1c71'))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textTertiary)
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(13)
        .border({
          width: 0.5,
          color: this.theme.border,
          style: BorderStyle.Dashed
        })
        .onClick((): void => {
          this.onCreateTap();
        })
      }
      .padding({ top: 2, bottom: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.Start)
  }

  /** 单个日记本胶囊：封面色小书脊 + 名字。选中 = accent 底 */
  @Builder
  private notebookChip(notebook: Notebook) {
    Row({ space: 5 }) {
      // 封面色小书脊：让用户一眼对上书架上的那本
      Column()
        .width(7)
        .height(11)
        .borderRadius(1.5)
        .backgroundColor(bookColorHex(notebook.bookColor))
        .border({
          width: 0.5,
          color: isLightBookColor(notebook.bookColor) ? '#26000000' : Color.Transparent
        })
      // 名字是用户数据，不查翻译表（R-LANG-10）
      Text(notebook.name)
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.isSelected(notebook) ? this.theme.cardBackground : this.theme.textSecondary)
    }
    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
    .backgroundColor(this.isSelected(notebook) ? this.theme.accent : Color.Transparent)
    .borderRadius(13)
    .border({
      width: 0.5,
      color: this.isSelected(notebook) ? this.theme.accent : this.theme.border
    })
    .scale({ x: this.isSelected(notebook) ? 1.05 : 1.0, y: this.isSelected(notebook) ? 1.05 : 1.0 })
    .onClick((): void => {
      // 单选：点已选 = 取消，点另一本 = 换过去（R-ENTRY-10）
      this.onToggle(notebook.name);
    })
  }

  private isSelected(notebook: Notebook): boolean {
    return this.selectedNotebookName === notebook.name;
  }
}
