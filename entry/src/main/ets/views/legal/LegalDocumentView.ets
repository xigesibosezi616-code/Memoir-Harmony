/**
 * 隐私政策 / 用户协议的阅读页（10_BUILD_MANUAL.md 1.5）。
 * 对应 iOS `Views/Legal/LegalDocumentView.swift`。
 *
 * 内容来自 rawfile 里的 md（见 `LegalDocument`），**不联网** ——
 * 审核时网络不通也一定打得开（R-APP-04）。
 *
 * iOS 用 sheet + NavigationStack 展示（导航栏标题 + 工具栏关闭按钮）；
 * 鸿蒙版没有导航容器可用，作为全屏覆盖层嵌入 LegalConsentView 的 Stack，
 * 自带顶栏：居中标题 + 左上角关闭。
 *
 * 解析结果缓存在 @State：正文数千字，每帧重新解析会掉帧（iOS 同款优化）。
 * 文档或语言变化时整体替换一次。
 */
import { LengthMetrics } from '@kit.ArkUI';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { LegalDocument, legalNavigationTitleRes, loadLegalMarkdown } from './LegalDocument';
import { LegalBlock, LegalBlockKind, LegalInlineSpan, parseLegalMarkdown } from './LegalMarkdown';

@Component
export struct LegalDocumentView {
  document: LegalDocument = LegalDocument.Privacy;
  onClose: () => void = () => {};

  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  // 开着阅读页切语言（1.2 的语言调试页可达）→ 立即按新语言重载
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) @Watch('onLanguageChanged') appLanguage: string = 'en';
  @State blocks: LegalBlock[] = [];

  /** 重载序号：快速连切语言时丢弃过期结果，避免旧语言覆盖新语言 */
  private reloadGeneration: number = 0;

  aboutToAppear(): void {
    this.reloadBlocks();
  }

  private onLanguageChanged(): void {
    this.reloadBlocks();
  }

  private reloadBlocks(): void {
    const generation: number = ++this.reloadGeneration;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    loadLegalMarkdown(context, this.document, this.appLanguage)
      .then((markdown: string) => {
        if (generation === this.reloadGeneration) {
          this.blocks = parseLegalMarkdown(markdown);
        }
      });
  }

  build() {
    Column() {
      this.titleBarBuilder()

      Scroll() {
        Column() {
          ForEach(this.blocks, (block: LegalBlock, index: number) => {
            if (block.kind === LegalBlockKind.Title) {
              Text(block.spans[0].text)
                .fontSize(this.theme.titleFont.size)
                .fontWeight(this.theme.titleFont.weight)
                .fontFamily(this.theme.titleFont.family)
                .fontColor(this.theme.textPrimary)
                .padding({ bottom: 10 })
            } else if (block.kind === LegalBlockKind.Heading) {
              Text(block.spans[0].text)
                .fontSize(this.theme.headingFont.size)
                .fontWeight(this.theme.headingFont.weight)
                .fontFamily(this.theme.headingFont.family)
                .fontColor(this.theme.textPrimary)
                .padding({ top: 22, bottom: 8 })
            } else if (block.kind === LegalBlockKind.Subheading) {
              Text(block.spans[0].text)
                .fontSize(this.theme.bodyFont.size)
                .fontWeight(600)
                .fontFamily(this.theme.bodyFont.family)
                .fontColor(this.theme.textPrimary)
                .padding({ top: 14, bottom: 6 })
            } else if (block.kind === LegalBlockKind.Paragraph) {
              Text() {
                ForEach(block.spans, (span: LegalInlineSpan, sIndex: number) => {
                  Span(span.text)
                    .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
                }, (span: LegalInlineSpan, sIndex: number) => `${index}-${sIndex}-${span.text}`)
              }
              .fontSize(this.theme.bodyFont.size)
              .fontFamily(this.theme.bodyFont.family)
              .fontColor(this.theme.textSecondary)
              .lineSpacing(LengthMetrics.vp(5))
              .padding({ bottom: 12 })
            } else if (block.kind === LegalBlockKind.Bullet) {
              Row({ space: 8 }) {
                // 用圆点而不是 md 原文的「-」：法律文档里连字符
                // 容易和正文里的连接号混淆（iOS 同款）
                Text('•')
                  .fontSize(this.theme.bodyFont.size)
                  .fontFamily(this.theme.bodyFont.family)
                  .fontColor(this.theme.textTertiary)
                Text() {
                  ForEach(block.spans, (span: LegalInlineSpan, sIndex: number) => {
                    Span(span.text)
                      .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
                  }, (span: LegalInlineSpan, sIndex: number) => `${index}-${sIndex}-${span.text}`)
                }
                .fontSize(this.theme.bodyFont.size)
                .fontFamily(this.theme.bodyFont.family)
                .fontColor(this.theme.textSecondary)
                .lineSpacing(LengthMetrics.vp(5))
                .layoutWeight(1)
              }
              .alignItems(VerticalAlign.Top)
              .padding({ bottom: 8 })
            }
          }, (block: LegalBlock, index: number) => `${index}-${block.kind}-${block.spans[0].text}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 16 })
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }

  /** 顶栏：居中标题（系统字体，对齐 iOS 导航栏样式）+ 左上角关闭 */
  @Builder
  private titleBarBuilder() {
    Stack({ alignContent: Alignment.Center }) {
      Text(legalNavigationTitleRes(this.document))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.textPrimary)
        .maxLines(1)
      Row() {
        Text('✕')
          .fontSize(16)
          .fontColor(this.theme.textPrimary)
          .width(44)
          .height(44)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height(44)
  }
}
