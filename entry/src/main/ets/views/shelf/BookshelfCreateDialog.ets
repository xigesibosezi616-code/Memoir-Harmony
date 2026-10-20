/**
 * 书架「新建日记本」弹窗（10_BUILD_MANUAL.md 3.1，R-BOOK-03）。
 * 对应 iOS `BookshelfView.swift` 的 `CreateTagSheet`（本卡只取名称 + 撞名提示，
 * 封面定制是 3.4 的 `BookCustomizerView`）。
 *
 * - 撞名当场提示「已有同名的日记本」（红字），「创建」同时置灰——
 *   当场说明为什么创建是灰的，不等人点了才报错
 * - 判重键 = 去首尾空白 + 忽略大小写 + 忽略全半角（nameKey，大小写 / 全角
 *   「Travel」「Ｔｒａｖｅｌ」各算同一个）；存库只去首尾空白，大小写原样保留
 * - 建不建由父组件决定（`onCreate` 拿到输入名后走库里逻辑）；点遮罩 = 取消
 */
import { cleanedName, isNameTaken } from '../../models/Notebook';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

@Component
export struct BookshelfCreateDialog {
  /** 现有日记本名（撞名判定用；弹窗每次条件挂载，拿当次快照即可） */
  existingNames: string[] = [];
  onCancel: () => void = (): void => {};
  onCreate: (name: string) => void = (_name: string): void => {};
  @State private newName: string = '';
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

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
        Text($r('app.string.s_c7a3044d8f'))
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
          // 当场说明为什么「创建」是灰的（R-BOOK-03）
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
            Text($r('app.string.s_fcbd093292'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.canCreate()
                ? this.theme.cardBackground : this.theme.textTertiary)
          }
          .layoutWeight(1)
          .padding({ top: 11, bottom: 11 })
          .backgroundColor(this.theme.accent)
          .borderRadius(12)
          .enabled(this.canCreate())
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

  /** 撞名判定（判重键见 nameKey：忽略大小写 / 全半角） */
  private isNameTaken(): boolean {
    return isNameTaken(this.newName, this.existingNames);
  }

  /** 创建可用：名字非空（去首尾空白后）且不撞名 */
  private canCreate(): boolean {
    return cleanedName(this.newName).length > 0 && !this.isNameTaken();
  }

  private submit(): void {
    if (!this.canCreate()) {
      return;
    }
    this.onCreate(cleanedName(this.newName));
  }
}
