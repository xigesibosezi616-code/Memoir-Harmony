/**
 * 「有同名的日记本」冲突弹窗（10_BUILD_MANUAL.md 6.4）。
 * 对应 iOS `BackupImportView` 里的 `.alert("有同名的日记本")`。
 *
 * 备份包里和本机同名、且两边都挂着日记的日记本先问用户怎么办再导：
 * 合并到同名日记本 / 作为新日记本导入（名字加序号）/ 取消。
 * iOS 按钮同序；点遮罩 = 取消。改不改名由 BackupImportService.merge 按
 * TagConflictPolicy 决定，这里只管选。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { isChineseLanguage } from '../../services/AppDateFormatters';

@Component
export struct BackupConflictDialog {
  /** 包里冲突日记本的写法（原样展示） */
  names: string[] = [];
  onMerge: () => void = (): void => {};
  onKeepSeparate: () => void = (): void => {};
  onCancel: () => void = (): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'en';

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
        Text($r('app.string.s_6b7fba6ac9'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)

        Text(this.messageText())
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textSecondary)
          .textAlign(TextAlign.Center)

        Column({ space: 12 }) {
          Button({ stateEffect: true }) {
            Text($r('app.string.s_85a35ccdd6'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.cardBackground)
          }
          .width('100%')
          .padding({ top: 11, bottom: 11 })
          .backgroundColor(this.theme.accent)
          .borderRadius(12)
          .onClick((): void => {
            this.onMerge();
          })

          Button({ stateEffect: true }) {
            Text($r('app.string.s_f8778319a6'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.textSecondary)
          }
          .width('100%')
          .padding({ top: 11, bottom: 11 })
          .backgroundColor(this.theme.surfaceBackground)
          .borderRadius(12)
          .border({ width: 0.5, color: this.theme.border })
          .onClick((): void => {
            this.onKeepSeparate();
          })

          Button({ stateEffect: true }) {
            Text($r('app.string.s_4d0b4688c7'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.textSecondary)
          }
          .width('100%')
          .padding({ top: 11, bottom: 11 })
          .backgroundColor(this.theme.surfaceBackground)
          .borderRadius(12)
          .border({ width: 0.5, color: this.theme.border })
          .onClick((): void => {
            this.onCancel();
          })
        }
        .width('100%')
      }
      .padding({ left: 22, right: 22, top: 24, bottom: 24 })
      .constraintSize({ maxWidth: 320 })
      .backgroundColor(this.theme.cardBackground)
      .borderRadius(20)
    }
    .width('100%')
    .height('100%')
  }

  /** 冲突名单按 App 语言连接（中文「、」，其余「, 」；iOS ListFormatter 同观感） */
  private messageText(): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    const joined = this.names.join(isChineseLanguage(this.appLanguage) ? '、' : ', ');
    return context.resourceManager.getStringSync($r('app.string.s_4394cb2863').id, joined);
  }
}
