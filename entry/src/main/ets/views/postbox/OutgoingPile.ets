/**
 * 邮筒页下方那一叠「这次寄出的日记」（10_BUILD_MANUAL.md 5.2）。
 * 对应 iOS `Views/PostBox/Posting/OutgoingPile.swift`。
 *
 * 版式度量（整叠高 / 头行 / 行高 / 渐隐）由 `PostBoxMetrics` 按
 * 机型/形态算好从父组件传入（叠纸 ≈ 窗高 22%，夹在 iOS 绝对值
 * 132~188 之间；高窗时逐字等于 iOS 34/40/188/24），默认值即 iOS
 * 绝对值。visibleRows 3.5 恒定（纸里滚动的判定不随机型变）。
 *
 * 一页信纸上按格线列出日期 + 标题，默认全勾；取消勾选的这次不寄
 * （R-POST-04；勾选状态存在父组件，投信那一刻才快照）。底下垫两张
 * 错开一点的纸，看得出是一叠。纸是「纸」，不跟主题明暗走（同 LetterPalette）。
 *
 * 超过 3.5 行在纸内滚动，最后半行淡下去（渐隐盖在纸上，看得出底下还有）。
 * `interactive == false` 时只是一张画（投信动画 / 服务端拦着时半透明摆着用）。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { OutgoingItem } from '../../models/PostBoxLogic';
import { shortDate } from '../../services/AppDateFormatters';
import { LetterPalette } from './LetterPalette';

/** 纸上看得见的行数（半行露头 = 底下还有） */
const VISIBLE_ROWS: number = 3.5;

/** '#RRGGBB' + 透明度 → '#AARRGGBB'（Rule/墨的半透明都这样算，不叠 opacity） */
function withAlpha(hex: string, alpha01: number): string {
  const a = Math.round(Math.max(0, Math.min(1, alpha01)) * 255);
  const s = a.toString(16);
  return `#${s.length < 2 ? '0' : ''}${s}${hex.substring(1)}`;
}

@Component
export struct OutgoingPile {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  /** 信件用料（跟着主题换） */
  palette: LetterPalette = LetterPalette.bamboo;
  /** 这次要寄的日记（快照，父组件按 R-POST-02/03 算好） */
  @Prop items: OutgoingItem[] = [];
  /** 取消勾选的那几篇的 id（勾选状态归父组件，投信那一刻才算数） */
  @Prop excludedIds: string[] = [];
  /** false = 只是一张画（服务端拦着时半透明摆着） */
  interactive: boolean = true;
  /** 勾 / 取消勾一篇（interactive 才会调） */
  onToggle: (id: string) => void = (_id: string): void => {};
  // ---- 版式度量（PostBoxMetrics 按机型/形态算好传入；默认 = iOS 绝对值） ----
  /** 整叠纸占的高（含垫纸露边 8）；同一形态内恒定（5.3 投信动画依赖） */
  @Prop totalHeightVp: number = 188;
  /** 头一行「这次寄出的日记 N / M」的高 */
  @Prop headerHeightVp: number = 34;
  /** 一行日记的高。超过 VISIBLE_ROWS 行就在纸里滚动 */
  @Prop rowHeightVp: number = 40;
  /** 最后半行渐隐的高（iOS rowHeight × 0.6） */
  @Prop fadeHeightVp: number = 24;

  /** 纸本体的高（整叠高 - 露边） */
  private paperHeightVp(): number {
    return this.totalHeightVp - 8;
  }

  private isExcluded(item: OutgoingItem): boolean {
    return this.excludedIds.indexOf(item.id) >= 0;
  }

  private checkedCount(): number {
    let n = 0;
    for (const item of this.items) {
      if (!this.isExcluded(item)) {
        n++;
      }
    }
    return n;
  }

  private isScrollable(): boolean {
    return this.items.length > VISIBLE_ROWS;
  }

  /** 纸上还空着几行（只画到看得见的那几行为止，像一页没写满的信纸） */
  private blankRowCount(): number {
    return Math.max(0, Math.ceil(VISIBLE_ROWS) - this.items.length);
  }

  build() {
    Stack() {
      // 垫在下面的两张：错开一点点，不晃
      this.backingSheet(-1.6, -3, 5, 0.75)
      this.backingSheet(1.1, 4, 3, 0.9)

      // 主纸：头一行 + 日记行（放不下在纸里滚动）
      Column() {
        this.header()
        Stack({ alignContent: Alignment.BottomStart }) {
          Scroll() {
            Column() {
              ForEach(this.items, (item: OutgoingItem) => {
                this.row(item)
              }, (item: OutgoingItem): string => `${item.id}:${item.title}`)
              ForEach(this.blankRowCount() === 0 ? [] : this.blankRowIndexes(),
                (index: number) => {
                  Column() {
                    Column()
                      .width('100%')
                      .height(this.rowHeightVp)
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .overlay(this.rule(), { align: Alignment.Bottom })
                }, (index: number): string => `blank:${index}`)
            }
            .width('100%')
          }
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .edgeEffect(this.interactive && this.isScrollable()
            ? EdgeEffect.Spring : EdgeEffect.None)
          .width('100%')
          .layoutWeight(1)

          // 放不下时最后半行淡下去，看得出底下还有（渐隐盖在纸上）
          if (this.isScrollable()) {
            Column()
              .width('100%')
              .height(this.fadeHeightVp)
              .linearGradient({
                angle: 270,
                colors: [[this.palette.paper, 0], [Color.Transparent, 1]]
              })
              .hitTestBehavior(HitTestMode.None)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height(this.paperHeightVp())
      .backgroundColor(this.palette.paper)
      .shadow({ radius: 2, color: '#1F000000', offsetX: 0, offsetY: 1 })
    }
    .width('100%')
    .height(this.totalHeightVp)
  }

  /** 垫纸（主纸后面错开的那两张，纯画） */
  @Builder
  private backingSheet(angleDeg: number, dxVp: number, dyVp: number, opacity01: number) {
    Column()
      .width('100%')
      .height(this.paperHeightVp())
      .backgroundColor(this.palette.paper)
      .shadow({ radius: 2, color: '#1F000000', offsetX: 0, offsetY: 1 })
      .rotate({ z: 1, angle: angleDeg })
      .offset({ x: dxVp, y: dyVp })
      .opacity(opacity01)
  }

  /** 头一行：这次寄出的日记 + 「勾上几篇 / 一共几篇」（不写成「N 篇」，免得七种语言各配一套单复数） */
  @Builder
  private header() {
    Column() {
      Row() {
        Text($r('app.string.s_9e19a026db'))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontStyle(FontStyle.Italic)
          .fontColor(withAlpha(this.palette.ink, 0.55))
          .layoutWeight(1)
        Text(`${this.checkedCount()} / ${this.items.length}`)
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontStyle(FontStyle.Italic)
          .fontColor(withAlpha(this.palette.ink, 0.55))
      }
      .width('100%')
      .height(this.headerHeightVp)
      .padding({ left: 18, right: 18 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .overlay(this.rule(), { align: Alignment.Bottom })
  }

  /** 一行日记：勾选框 + 日期 + 标题（没标题的用正文第一行，都没有「无题」） */
  @Builder
  private row(item: OutgoingItem) {
    Column() {
      Row({ space: 12 }) {
        this.checkMark(!this.isExcluded(item))
        Text(shortDate(new Date(item.date), this.appLanguage))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(withAlpha(this.palette.ink, 0.55))
          .constraintSize({ minWidth: 52 })
        if (item.title.length === 0) {
          Text($r('app.string.s_6a576f3bf9'))
            .fontSize(this.theme.bodyFont.size)
            .fontWeight(this.theme.bodyFont.weight)
            .fontFamily(this.theme.bodyFont.family)
            .fontColor(this.palette.ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        } else {
          Text(item.title)
            .fontSize(this.theme.bodyFont.size)
            .fontWeight(this.theme.bodyFont.weight)
            .fontFamily(this.theme.bodyFont.family)
            .fontColor(this.palette.ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height(this.rowHeightVp)
      .padding({ left: 18, right: 18 })
      .alignItems(VerticalAlign.Center)
      .opacity(this.isExcluded(item) ? 0.38 : 1)
      .onClick((): void => {
        if (this.interactive) {
          this.onToggle(item.id);
        }
      })
    }
    .width('100%')
    .overlay(this.rule(), { align: Alignment.Bottom })
  }

  /** 勾选框：手画似的小方框，勾上了是一笔红（跟着信封内衬的颜色） */
  @Builder
  private checkMark(checked: boolean) {
    Stack() {
      Column()
        .width(15)
        .height(15)
        .borderRadius(2.5)
        .border({ width: 1, color: this.palette.ink })
        .opacity(0.45)
      if (checked) {
        // 手画的勾：短撇接长捺（iOS TickShape 的三端点，圆头相接）。
        // 🔴 不用 Path.commands：真机上 commands 坐标按物理像素渲染（约缩小 3 倍
        // 缩在框角，2026-10-27 真机像素扫描确认）；Line 的端点坐标是 vp，跨设备一致
        Stack() {
          Line({ width: 13, height: 11 })
            .startPoint([0, 5.55])
            .endPoint([4.68, 11])
            .stroke(this.palette.liner)
            .strokeWidth(1.8)
            .strokeLineCap(LineCapStyle.Round)
          Line({ width: 13, height: 11 })
            .startPoint([4.68, 11])
            .endPoint([13, 0])
            .stroke(this.palette.liner)
            .strokeWidth(1.8)
            .strokeLineCap(LineCapStyle.Round)
        }
        .width(13)
        .height(11)
        .offset({ x: 1.5, y: -1.5 })
      }
    }
    .width(18)
    .height(18)
  }

  /** 信纸上的格线 */
  @Builder
  private rule() {
    Column()
      .height(0.6)
      .backgroundColor(this.palette.rule)
      .margin({ left: 12, right: 12 })
  }

  private blankRowIndexes(): number[] {
    const indexes: number[] = [];
    for (let i = 0; i < this.blankRowCount(); i++) {
      indexes.push(i);
    }
    return indexes;
  }
}
