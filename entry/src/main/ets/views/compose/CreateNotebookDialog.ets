/**
 * 「新建日记本」弹窗（10_BUILD_MANUAL.md 2.1，R-ENTRY-10）。对应 iOS `TagSelector`
 * 里的 `.alert("新建日记本", isPresented: $showAddTag)`。
 *
 * 建不建、撞不撞名由父组件决定（`onCreate` 回调拿到输入名后走库里逻辑）；
 * 这里只管输入和两个按钮。点遮罩 = 取消。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

@Component
export struct CreateNotebookDialog {
  onCancel: () => void = (): void => {};
  onCreate: (name: string) => void = (_name: string): void => {};
  @State newNotebookName: string = '';
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

        TextInput({
          placeholder: $r('app.string.s_ae002a8a37'),
          text: this.newNotebookName
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
          this.newNotebookName = value;
        })
        .onSubmit((_enterKey: EnterKeyType, _event: SubmitEvent): void => {
          this.submit();
        })

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
              .fontColor(this.theme.cardBackground)
          }
          .layoutWeight(1)
          .padding({ top: 11, bottom: 11 })
          .backgroundColor(this.theme.accent)
          .borderRadius(12)
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

  private submit(): void {
    this.onCreate(this.newNotebookName);
  }
}
