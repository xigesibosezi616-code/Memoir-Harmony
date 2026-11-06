/**
 * 首次启动的隐私告知与同意页（10_BUILD_MANUAL.md 1.5）。
 * 对应 iOS `Views/Legal/LegalConsentView.swift`。
 *
 * **为什么必须有**：《个人信息保护法》要求在处理个人信息前以显著方式告知并取得同意；
 * 应用商店审核会实际检查这一步。在用户点「同意并继续」之前，
 * 尺素不发起任何网络请求、不申请任何系统权限（R-APP-01）。
 *
 * **为什么「暂不使用」不退出 App**：程序化退出违反平台审核指南。
 * 这里的做法是**停在这一屏**——不同意就过不去（R-APP-03），
 * 只提示一句原因（不用全局错误条：这不是失败，是合规告知）。
 *
 * 背景**就是当前主题的底色**（刚装好时是素笺 #FAF7F2；老用户因协议改版
 * 重新同意时是他自己的主题色），卡片**居中**（U04：骑士递信给信鸽的
 * 背景画已删，不再需要给画面让位）。卡片样式不变，影子减淡（黑 10%、
 * 半径 20、下移 6），加一圈 0.5 的细边（黑 6%）。
 */
import { LengthMetrics } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { LegalDocument } from './LegalDocument';
import { LegalInlineSpan, parseInlineBold } from './LegalMarkdown';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { LegalDocumentView } from './LegalDocumentView';

@Component
export struct LegalConsentView {
  /** 用户点了同意：调用方写版本号（R-APP-02） */
  onAccept: () => void = () => {};

  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'en';
  /** 当前打开的协议全文（privacy / terms），undefined = 没开 */
  @State presentedDocument: LegalDocument | undefined = undefined;

  /** 同意页正文五段（资源带 `**加粗**` 的整句，渲染前解析成 span 序列） */
  private bodyParagraphs(): LegalInlineSpan[][] {
    const texts: string[] = [];
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      try {
        const manager = context.resourceManager;
        // 用 `.id` 走数字重载：`getStringSync(resource: Resource)` 已弃用（API 20）
        texts.push(
          manager.getStringSync($r('app.string.s_487942b7ff').id),
          manager.getStringSync($r('app.string.s_df5dc2b3c5').id),
          manager.getStringSync($r('app.string.s_3e81ed47a5').id),
          manager.getStringSync($r('app.string.s_4c25fbcd78').id),
          manager.getStringSync($r('app.string.s_778db1c262').id)
        );
      } catch (err) {
        hilog.error(0x0000, 'LegalConsent', 'read consent body failed: %{public}s', JSON.stringify(err));
      }
    }
    const paragraphs: LegalInlineSpan[][] = [];
    for (const text of texts) {
      paragraphs.push(parseInlineBold(text));
    }
    return paragraphs;
  }

  /** 「暂不使用」→ 停在同意页，说明一句原因（不退出，R-APP-03） */
  private showDeclineDialog(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.s_f72b6c2eb7'),
      message: $r('app.string.s_cb399ce358'),
      autoCancel: false,
      buttons: [
        {
          value: $r('app.string.s_6a7c90ae15'),
          action: () => {}
        }
      ]
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 背景只是当前主题的底色（U04：背景画已删）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme.background)

      this.cardBuilder()

      // 协议全文必须在同意**之前**就能读到 ——「先同意才能看」不合规。
      // 整页覆盖在同意卡片之上，读完关闭回到同意页
      if (this.presentedDocument !== undefined) {
        LegalDocumentView({
          document: this.presentedDocument,
          onClose: () => {
            this.presentedDocument = undefined;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private documentLinkBuilder(doc: LegalDocument, label: Resource) {
    Text(label)
      .fontSize(13)
      .fontColor(0xFF404040)
      .decoration({ type: TextDecorationType.Underline })
      .maxLines(1)
      .onClick(() => {
        this.presentedDocument = doc;
      })
  }

  // MARK: - 卡片

  @Builder
  private cardBuilder() {
    Column() {
      Text($r('app.string.s_2e813d55e6'))
        .fontSize(19)
        .fontWeight(600)
        .fontColor(0xFF1A1A1A)
        .padding({ top: 26, bottom: 16 })

      // 正文可滚动。**不要改成固定高度的 Text** —— 七种语言里
      // 德法西的行长差异很大，写死高度必然有语言被截断
      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.bodyParagraphs(), (spans: LegalInlineSpan[], pIndex: number) => {
            Text() {
              ForEach(spans, (span: LegalInlineSpan, sIndex: number) => {
                Span(span.text)
                  .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
              }, (span: LegalInlineSpan, sIndex: number) => `${pIndex}-${sIndex}-${span.text}`)
            }
            .fontSize(14)
            .fontColor(0xFF525252)
            .lineSpacing(LengthMetrics.vp(5))
            .alignSelf(ItemAlign.Start)
          }, (spans: LegalInlineSpan[], pIndex: number) => `${pIndex}-${spans[0].text}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 22, right: 22, bottom: 14 })
      }
      .constraintSize({ maxHeight: 230 })
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      // 一行放不下就自动折行（法语的 «Politique de confidentialité» 一个词
      // 就顶掉半行，硬排一行会折行并和另一个链接叠在一起）
      Flex({
        wrap: FlexWrap.Wrap,
        justifyContent: FlexAlign.Center,
        alignItems: ItemAlign.Center,
        space: { main: LengthMetrics.vp(14), cross: LengthMetrics.vp(7) }
      }) {
        this.documentLinkBuilder(LegalDocument.Privacy, $r('app.string.s_a09ce12ef3'))
        this.documentLinkBuilder(LegalDocument.Terms, $r('app.string.s_8f31a480bd'))
      }
      .width('100%')
      .padding({ left: 22, right: 22, bottom: 18 })

      Row({ space: 12 }) {
        Text($r('app.string.s_514dbb7b7e'))
          .fontSize(15)
          .fontColor(0xFF1F1F1F)
          .maxLines(1)
          .minFontSize(11.25)
          .maxFontSize(15)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .padding({ top: 13, bottom: 13 })
          .border({ width: 1, color: 0xFF1F1F1F })
          .borderRadius(3)
          .onClick(() => {
            this.showDeclineDialog();
          })

        Text($r('app.string.s_1c5dfb22c6'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(0xFFFFFFFF)
          .maxLines(1)
          .minFontSize(11.25)
          .maxFontSize(15)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .padding({ top: 13, bottom: 13 })
          .backgroundColor(0xFF1F1F1F)
          .borderRadius(3)
          .onClick(() => {
            this.onAccept();
          })
      }
      .width('100%')
      .padding({ left: 22, right: 22, bottom: 24 })
    }
    .backgroundColor(0xFFFCFCFC)
    .borderRadius(4)
    .border({ width: 0.5, color: 0x0F000000 })
    // 影子减淡（U04：黑 10%、半径 20、下移 6）；
    // margin 在底色之外，只挪位置不撑卡片（iOS 同款：外层 padding 30）
    .shadow({ radius: 20, color: 0x1A000000, offsetX: 0, offsetY: 6 })
    .margin({ left: 30, right: 30 })
  }
}
