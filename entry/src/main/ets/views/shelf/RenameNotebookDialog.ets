/**
 * 日记本重命名弹窗（10_BUILD_MANUAL.md 3.3，R-BOOK-03/08）。
 * 对应 iOS `BookDetailView` 的「重命名」alert。结构仿书架「新建日记本」弹窗
 * （BookshelfCreateDialog）：名称 + 撞名当场红字提示 +「保存」置灰；
 * 判重键 = 去首尾空白 + 忽略大小写 + 忽略全半角（nameKey）。
 * 改不改由父组件决定（`onRename` 拿到输入名走库里逻辑）；点遮罩 = 取消。
 */
import { cleanedName, isNameTaken } from '../../models/Notebook';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

@Component
export struct RenameNotebookDialog {
  /** 现有日记本名（撞名判定用；调用方传当次快照） */
  existingNames: string[] = [];
  /** 打开时填进输入框的现名 */
  currentName: string = '';
  onCancel: () => void = (): void => {};
  onRename: (name: string) => void = (_name: string): void => {};
  @State private newName: string = '';
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  aboutToAppear(): void {
    this.newName = this.currentName;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.onCancel();
        })

      Column({ space: 18 }) {
        Text($r('app.string.s_5d527e99c3'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)

        Column({ space: 8 }) {
          Text($r('app.string.s_1be7ae4fc2'))
            .fontSize(13)
            .fontColor(this.theme.textSecondary)
          TextInput({
            placeholder: $r('app.string.s_ae002a8a37'),
            text: this.newName
          })
          .fontSize(this.theme.bodyFont.size)
          .fontColor(this.theme.textPrimary)
          .caretColor(this.theme.textSecondary)
          .backgroundColor(this.theme.surfaceBackground)
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .height(42)
          .defaultFocus(true)
          .onChange((value: string): void => {
            this.newName = value;
          })
          .onSubmit((_enterKey: EnterKeyType, _event: SubmitEvent): void => {
            this.submit();
          })
          // 当场说明为什么「保存」是灰的（R-BOOK-03）
          if (this.isNameTaken()) {
            Text($r('app.string.s_b477b8791b'))
              .fontSize(12)
              .fontColor(this.theme.destructive)
              .opacity(0.8)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Row({ space: 12 }) {
          Button({ stateEffect: true }) {
            Text($r('app.string.s_4d0b4688c7'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.textSecondary)
          }
          .layoutWeight(1)
          .padding({ top: 11, bottom: 11 })
          .backgroundColor(this.theme.surfaceBackground)
          .borderRadius(12)
          .border({ width: 0.5, color: this.theme.border })
          .onClick((): void => {
            this.onCancel();
          })

          Button({ stateEffect: true }) {
            Text($r('app.string.s_fadf24dbc5'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.canRename()
                ? this.theme.cardBackground : this.theme.textTertiary)
          }
          .layoutWeight(1)
          .padding({ top: 11, bottom: 11 })
          .backgroundColor(this.theme.accent)
          .borderRadius(12)
          .enabled(this.canRename())
          .onClick((): void => {
            this.submit();
          })
        }
      }
      .padding({ left: 22, right: 22, top: 24, bottom: 24 })
      .constraintSize({ maxWidth: 320 })
      .backgroundColor(this.theme.cardBackground)
      .borderRadius(20)
    }
    .width('100%')
    .height('100%')
  }

  /** 撞名判定（自己改自己的大小写不算撞名：判定前把现名排除掉） */
  private isNameTaken(): boolean {
    const others: string[] = [];
    const key = this.currentName.length > 0 ? this.currentName : '\u0000';
    for (const name of this.existingNames) {
      if (name !== key) {
        others.push(name);
      }
    }
    return isNameTaken(this.newName, others);
  }

  /** 可保存：非空、去了首尾空白后有变化、且不撞名（与库端 rename 三态对齐） */
  private canRename(): boolean {
    return cleanedName(this.newName).length > 0 && !this.isNameTaken();
  }

  private submit(): void {
    if (!this.canRename()) {
      return;
    }
    this.onRename(cleanedName(this.newName));
  }
}
