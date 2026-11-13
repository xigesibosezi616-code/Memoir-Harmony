/**
 * 会员信纸：一张摊在桌上的信笺（10_BUILD_MANUAL.md 5.7，R-BOX-05「专属信纸」）。
 * 对应 iOS `Views/PostBox/Envelope/LetterStationery.swift`。
 *
 * - 字一行一格落在格线上；四周（素笺 framed 主题）有一圈细框
 * - 正文用 `.lineHeight` 钉死行高（34），格线按同一行高逐行画——
 *   中英混排每行高度一致，格线和字不会错开（iOS 用 TextKit 量基线，
 *   ArkUI `lineHeight` 直接固定行盒，一行都不会错位；首行基线是常数，
 *   `FIRST_RULE_Y` 装机校准）
 * - 正文之后再多画几格空行，信纸不至于写到底就断（iOS blankLines = 2）
 * - 纸纤维（iOS PaperGrain）Canvas 移植：固定种子短纤维线，重绘不闪
 */
import { LetterPalette } from './LetterPalette';

/** '#RRGGBB' + 透明度 → '#AARRGGBB'（不叠 opacity，色值预算成 8 位） */
function withAlpha(hex: string, alpha01: number): string {
  const a = Math.round(Math.max(0, Math.min(1, alpha01)) * 255);
  const s = a.toString(16);
  return `#${s.length < 2 ? '0' : ''}${s}${hex.substring(1)}`;
}

/** 纸纤维固定种子（每次画出来一样，滚动重绘不「闪」——iOS 同款哲学） */
const GRAIN_SEED: number = 20261010;
/** 每 70vp² 一根纤维（iOS 原版；中间试过加密到 45 用户嫌重，回退第一版） */
const GRAIN_AREA_PER_FIBER_VP2: number = 70;

/** 32 位 mulberry32：iOS SplitMix64 要 UInt64 乘法（JS 精度不够），视觉纹理 32 位够用 */
class GrainRandom {
  private state: number;

  constructor(seed: number) {
    this.state = seed >>> 0;
  }

  /** 0..<1 */
  next(): number {
    this.state = (this.state + 0x6D2B79F5) >>> 0;
    let t = this.state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
}


/** 正文行高（vp）：格线的间距也用它（用户反馈 34 太松，收紧到 30）。
 *  导出给读信页算「两面同纸」的补齐行数用，别改单边 */
export const LINE_HEIGHT_VP: number = 30;
/** 正文（vp，用户反馈 17 偏大，缩到 15；抬头「致 XXX」22 不动） */
const BODY_FONT_SIZE_VP: number = 15;
/**
 * 首行格线在正文区顶部的位置（vp）。装机像素标定（Mate 80 Pro Max）：
 * 墨迹底 ≈ 行盒顶 + 24vp（衬线 15fp，行高 30 实测），
 * + iOS ruleGap ≈ 1.5vp → 25.5（17fp/34 时是 28.1 + 1.4 = 29.5）
 */
const FIRST_RULE_Y_VP: number = 25.5;
/** 正文之后再多画的空行数默认值（iOS blankLines；空行也占纸高，iOS height(forWidth:) 同款） */
const BLANK_LINES_DEFAULT: number = 2;
/** 素笺细框：外框内缩与线宽（iOS strokeBorder padding 12 / lineWidth 0.8） */
const FRAME_OUTER_INSET_VP: number = 12;
const FRAME_OUTER_WIDTH_VP: number = 0.8;
/** 内框：再进 3vp、线细一半（iOS padding 15 / lineWidth 0.5） */
const FRAME_INNER_INSET_VP: number = 15;
const FRAME_INNER_WIDTH_VP: number = 0.5;

@Component
export struct LetterStationery {
  palette: LetterPalette = LetterPalette.bamboo;
  /** 信头右上角的日期 */
  date: string = '';
  /** 抬头「致 XXX」—— 由调用方给出本地化好的串 */
  salutation: ResourceStr = '';
  /** 正文（已含开头、结尾、签名） */
  content: string = '';
  /** 正文之后再多画的空行数（世界笔友两面同纸时，字少的那面加行补齐，U01「两面一样大」） */
  blankLines: number = BLANK_LINES_DEFAULT;
  /** 要画几条格线（正文实测高度推出来，见 onAreaChange） */
  @State private ruleCount: number = 3;
  /** 纸面实测尺寸（vp）：细框/纤维按它画。实测前不画（首帧不闪框） */
  @State @Watch('onPaperMeasured') private frameWidthVp: number = 0;
  @State @Watch('onPaperMeasured') private frameHeightVp: number = 0;
  /** 纸纤维画笔（Canvas 单位 vp，与组件布局同单位） */
  private grainPainter: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true));

  /** 纸面尺寸变化 → 重画纤维（onReady 在 Canvas 尺寸变化时也会重触发，双保险） */
  private onPaperMeasured(): void {
    this.drawGrain();
  }

  /** 纸纤维：iOS PaperGrain 同款——随机短纤维线，墨色 3%~8% 透明度 */
  private drawGrain(): void {
    const w = this.frameWidthVp;
    const h = this.frameHeightVp;
    if (w <= 0 || h <= 0) {
      return;
    }
    const ctx = this.grainPainter;
    ctx.clearRect(0, 0, w, h);
    const rng = new GrainRandom(GRAIN_SEED);
    const count = Math.floor(w * h / GRAIN_AREA_PER_FIBER_VP2);
    ctx.lineWidth = 0.5;
    for (let i = 0; i < count; i++) {
      const x = rng.next() * w;
      const y = rng.next() * h;
      const length = 1 + rng.next() * 3;
      const angle = rng.next() * Math.PI;
      ctx.strokeStyle = withAlpha(this.palette.ink, 0.03 + rng.next() * 0.05);
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + Math.cos(angle) * length, y + Math.sin(angle) * length);
      ctx.stroke();
    }
  }

  build() {
    // 内容必须钉在左上角（Stack 默认 Center 会把整张字压到纸中间——真机实锤）；
    // 细框用实测尺寸 + position 绝对定位，绝不参与 Stack 自身量高
    //（height('100%') 子节点在无界父容器里会把 Stack 撑大，真机实锤）
    Stack({ alignContent: Alignment.TopStart }) {
      // 纸纤维：垫在最底层（纸色之上、内容之下）；实测尺寸前不占位，
      // 固定尺寸子节点不参与 Stack 量高（不会重蹈 height('100%') 撑大 Stack 的坑）
      Canvas(this.grainPainter)
        .width(this.frameWidthVp)
        .height(this.frameHeightVp)
        .hitTestBehavior(HitTestMode.None)
        .onReady((): void => {
          this.drawGrain();
        })

      Column() {
        // 信头右上角的日期
        Text(this.date)
          .fontSize(13)
          .fontFamily('serif')
          .fontColor(withAlpha(this.palette.ink, 0.5))
          .width('100%')
          .textAlign(TextAlign.RIGHT)
          .margin({ bottom: 22 })

        // 抬头「致 XXX」
        Text(this.salutation)
          .fontSize(22)
          .fontFamily('serif')
          .fontColor(this.palette.ink)
          .margin({ bottom: 6 })

        // 正文：一行一格落在格线上（格线在后面，压着基线画）
        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.ruleIndexes(), (i: number) => {
            Column()
              .width('100%')
              .height(0.7)
              .backgroundColor(this.palette.rule)
              .position({ x: 0, y: FIRST_RULE_Y_VP + i * LINE_HEIGHT_VP })
          }, (i: number): string => `rule:${i}`)

          Text(this.content)
            .fontSize(BODY_FONT_SIZE_VP)
            .fontFamily('serif')
            .fontColor(this.palette.ink)
            .lineHeight(LINE_HEIGHT_VP)
            .width('100%')
            .onAreaChange((_oldArea: Area, newArea: Area): void => {
              // 行高被 lineHeight 钉死，实测高度 ≈ 行数 × 行高，取整防浮点尾差多画一条
              const lines = Math.round(Number(newArea.height) / LINE_HEIGHT_VP);
              const next = lines + this.blankLines;
              if (next !== this.ruleCount) {
                this.ruleCount = next;
              }
            })
        }
        .width('100%')
        .alignContent(Alignment.TopStart)
        // 空白格也是纸的一部分（iOS RuledText 高度 = 文字 + 空行数 × 行高）；
        // 不垫高的话空行格线会溢出纸面、串到落款上（真机实锤）
        .padding({ bottom: this.blankLines * LINE_HEIGHT_VP })

        // 落款一行小字
        Text($r('app.string.s_f29761cd03'))
          .fontSize(10)
          .fontFamily('serif')
          .fontColor(this.palette.rule)
          .letterSpacing(3)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 18 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 28, right: 28, top: 30, bottom: 24 })

      // 四周的细框（素笺八行笺那样，一宽一窄两道；非 framed 主题没有）
      if (this.palette.framed && this.frameWidthVp > 0 && this.frameHeightVp > 0) {
        Column()
          .width(this.frameWidthVp - 2 * FRAME_OUTER_INSET_VP)
          .height(this.frameHeightVp - 2 * FRAME_OUTER_INSET_VP)
          .border({ width: FRAME_OUTER_WIDTH_VP, color: this.palette.rule })
          .position({ x: FRAME_OUTER_INSET_VP, y: FRAME_OUTER_INSET_VP })
          .hitTestBehavior(HitTestMode.None)

        Column()
          .width(this.frameWidthVp - 2 * FRAME_INNER_INSET_VP)
          .height(this.frameHeightVp - 2 * FRAME_INNER_INSET_VP)
          .border({ width: FRAME_INNER_WIDTH_VP, color: this.palette.rule })
          .position({ x: FRAME_INNER_INSET_VP, y: FRAME_INNER_INSET_VP })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .backgroundColor(this.palette.paper)
    .shadow({ radius: 8, color: '#24000000', offsetX: 0, offsetY: 3 })
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const w = Math.round(Number(newArea.width) * 10) / 10;
      const h = Math.round(Number(newArea.height) * 10) / 10;
      if (w !== this.frameWidthVp || h !== this.frameHeightVp) {
        this.frameWidthVp = w;
        this.frameHeightVp = h;
      }
    })
  }

  /** 格线下标：正文行数 + 空行 */
  private ruleIndexes(): number[] {
    const indexes: number[] = [];
    for (let i = 0; i < this.ruleCount; i++) {
      indexes.push(i);
    }
    return indexes;
  }
}
