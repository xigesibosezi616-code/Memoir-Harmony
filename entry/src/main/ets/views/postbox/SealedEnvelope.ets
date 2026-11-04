/**
 * 火漆封口的信封，背面（封舌那一面）朝上。
 * 对应 iOS `Views/PostBox/Envelope/SealedEnvelope.swift`。
 *
 * `progress` 0 = 封着，1 = 信纸已经抽出来（投信时从 1 收到 0）。
 * 抽出来的信纸会超出信封的上沿，外面要留出约 0.8 个信封高的空间。
 *
 * 多边形用 Polygon/Polyline（正规 ArkTS 绘制组件，坐标 vp；
 * 🔴 不用 Path.commands——真机上 commands 坐标按物理像素渲染，见
 * OutgoingPile 勾选框的排雷记录）。
 */
import { LetterPostingTimeline } from '../../models/LetterPostingTimeline';
import { ENVELOPE_ASPECT } from '../../models/LetterPostingFlightGeometry';
import { LetterPalette } from './LetterPalette';
import { WaxSeal } from './WaxSeal';

/** 封舌尖落在信封高度的哪里 */
const FLAP_DEPTH: number = 0.58;
/** 口袋上沿 V 口的深度（比封舌浅一点，封舌才盖得住） */
const NOTCH_DEPTH: number = 0.5;
/** 火漆裂开的位置（占印框高的比例，iOS SealCrack 锯齿线的中线） */
const SEAL_CUT: number = 0.54;
/** 半块火漆的裁剪容器比印框大一圈（溢开的蜡边和影子不被裁平） */
const SEAL_PIECE_MARGIN: number = 0.1;
/** 火漆裂缝的锯齿（iOS SealCrack 的 crack 数组，[x, y] 占印框宽高比例） */
const SEAL_CRACK_ZIGZAG: number[][] = [
  [0.02, 0.54], [0.14, 0.50], [0.27, 0.57], [0.40, 0.51],
  [0.52, 0.58], [0.63, 0.52], [0.76, 0.57], [0.88, 0.51], [0.98, 0.55]
];

/** '#RRGGBB' + 透明度 → '#AARRGGBB'（不叠 opacity，色值预算成 8 位） */
function withAlpha(hex: string, alpha01: number): string {
  const a = Math.round(Math.max(0, Math.min(1, alpha01)) * 255);
  const s = a.toString(16);
  return `#${s.length < 2 ? '0' : ''}${s}${hex.substring(1)}`;
}

/** 封舌轮廓：上面的倒三角，尖儿磨圆（iOS FlapShape 的 addArc 切圆，r = 0.05w） */
function flapPoints(w: number, h: number): number[][] {
  const tipX = w / 2;
  const tipY = h * FLAP_DEPTH;
  const half = w / 2;
  const edge = Math.sqrt(half * half + tipY * tipY);
  const sinHalfAngle = half / edge;
  const r = w * 0.05;
  // 尖角内切圆：圆心在尖的正上方，切点在两条斜边上
  const cy = tipY - r / sinHalfAngle;
  const d = r * (tipY / edge) / sinHalfAngle;
  const t1x = tipX + d * half / edge;
  const t1y = tipY - d * tipY / edge;
  const t2x = tipX - d * half / edge;
  const a0 = Math.atan2(t1y - cy, t1x - tipX);
  const a1 = Math.atan2(t1y - cy, t2x - tipX);
  const points: number[][] = [[0, 0], [w, 0], [t1x, t1y]];
  const samples = 6;
  for (let i = 1; i < samples; i++) {
    const a = a0 + (a1 - a0) * i / samples;
    points.push([tipX + r * Math.cos(a), cy + r * Math.sin(a)]);
  }
  points.push([t2x, t1y]);
  return points;
}

/** 封舌内面贴的那层内衬：四周留一圈信封纸（iOS 0.9x / 0.86y 缩放） */
function innerFlapPoints(w: number, h: number): number[][] {
  const base = flapPoints(w, h);
  const points: number[][] = [];
  for (const p of base) {
    points.push([w / 2 + (p[0] - w / 2) * 0.9, p[1] * 0.86]);
  }
  return points;
}

/** 口袋：整张信封减去上面的 V 口 */
function pocketPoints(w: number, h: number): number[][] {
  return [[0, 0], [w * 0.5, h * NOTCH_DEPTH], [w, 0], [w, h], [0, h]];
}

/** 口袋 V 口的两道边 */
function notchEdgePoints(w: number, h: number): number[][] {
  return [[0, 0], [w * 0.5, h * NOTCH_DEPTH], [w, 0]];
}

/** 底下那片折边：从两个下角往中间收，顶上是一道缓弧（二次贝塞尔采样） */
function bottomFlapPoints(w: number, h: number): number[][] {
  const points: number[][] = [];
  const cx = w * 0.5;
  const cy = h * 0.18;
  for (let i = 0; i <= 12; i++) {
    const t = i / 12;
    const u = 1 - t;
    points.push([2 * u * t * cx + t * t * w, u * u * h + 2 * u * t * cy + t * t * h]);
  }
  return points;
}

/**
 * 火漆的一半（iOS SealCrack）：裂缝大致沿封舌的边横穿中间偏下。
 * 上半块跟封舌走，下半块粘在口袋上。裁剪用容器边界 clip(true)，
 * 容器比印框大一圈，溢开的蜡边和影子不被裁平
 */
@Component
struct SealPiece {
  sizeVp: number = 64;
  mark: string = '素';
  /** true = 裂缝上半块（跟封舌走）；false = 下半块（粘在口袋上） */
  upper: boolean = true;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      WaxSeal({ sizeVp: this.sizeVp, mark: this.mark })
        .position({
          x: this.sizeVp * SEAL_PIECE_MARGIN,
          y: this.upper ? this.sizeVp * SEAL_PIECE_MARGIN : -this.sizeVp * SEAL_CUT
        })
    }
    .width(this.sizeVp * (1 + 2 * SEAL_PIECE_MARGIN))
    .height(this.upper
      ? this.sizeVp * (SEAL_CUT + SEAL_PIECE_MARGIN)
      : this.sizeVp * (1 - SEAL_CUT + SEAL_PIECE_MARGIN))
    .clip(true)
  }
}

@Component
export struct SealedEnvelope {
  palette: LetterPalette = LetterPalette.bamboo;
  /** 火漆上压的字（「素」兜底） */
  mark: string = '素';
  /** 有没有火漆。免费用户寄出去的信封只是普通封口（投信时用） */
  hasSeal: boolean = true;
  /** 拆信进度：0 = 封着，1 = 信纸已经抽出来（投信时从 1 收到 0） */
  @Prop progress: number = 0;
  /** 火漆按下去到哪：0 = 还没盖，1 = 盖好了 */
  @Prop sealPress: number = 1;
  /** 信封宽（高 = 宽 / 1.56） */
  @Prop widthVp: number = 120;
  /** 信封背面下方的一行小字（「来自 青鸟」）；空 = 不显示（iOS sender） */
  sender: ResourceStr = '';

  private heightVp(): number {
    return this.widthVp / ENVELOPE_ASPECT;
  }

  private sealSize(): number {
    return this.widthVp * 0.2;
  }

  /** 火漆中心（印面压在封舌尖上，iOS sealCenter） */
  private sealCenterY(): number {
    return this.heightVp() * FLAP_DEPTH - this.sealSize() * 0.12;
  }

  /** 火漆沿封舌边裂开的程度（0 = 完好，1 = 裂到底） */
  private crack(): number {
    return LetterPostingTimeline.envelopeCrack(this.progress);
  }

  /** 半块火漆（裁剪容器）左上角的 x：容器中心水平对齐火漆中心 */
  private sealPieceX(): number {
    return this.widthVp / 2 - this.sealSize() * (1 + 2 * SEAL_PIECE_MARGIN) / 2;
  }

  /** 半块火漆（裁剪容器）左上角的 y：容器上沿在印框上沿外一圈 */
  private sealPieceY(): number {
    return this.sealCenterY() - this.sealSize() * (0.5 + SEAL_PIECE_MARGIN);
  }

  /** 下半块火漆（裁剪容器）左上角的 y：容器上沿贴着裂缝线（sealPieceY +
   *  裂缝高度 + 外圈留白）。曾直接复用 sealPieceY 导致下半块整体画高
   *  0.64s、叠在上半块上，印章被压成上下缺口的扁块（真机红印宽高比
   *  0.63 ≈ 0.54+0.10 实证） */
  private sealPieceLowerY(): number {
    return this.sealPieceY() + this.sealSize() * (SEAL_CUT + SEAL_PIECE_MARGIN);
  }

  /** 盖火漆：蜡从上方落下、压平 —— 一路缩到原大，没有回弹 */
  private sealScale(): number {
    return 1 + 0.3 * (1 - LetterPostingTimeline.smooth(this.sealPress, 0, 1));
  }

  private sealOpacity(): number {
    return Math.min(1, this.sealPress / 0.4);
  }

  /** 裂缝锯齿线（Polyline 点，印框坐标） */
  private sealCrackPoints(): number[][] {
    const s = this.sealSize();
    const points: number[][] = [];
    for (const z of SEAL_CRACK_ZIGZAG) {
      points.push([z[0] * s, z[1] * s]);
    }
    return points;
  }

  /** 封舌翻起的角度（绕上沿，度） */
  private flapAngle(): number {
    return LetterPostingTimeline.envelopeLift(this.progress) * 180;
  }

  private letterSlide(): number {
    return LetterPostingTimeline.envelopeSlide(this.progress);
  }

  private ruleIndexes(): number[] {
    return [1, 2, 3, 4, 5, 6];
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. 信封里面：内衬，越往下越暗（影子跟着信封大小走）
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(3)
        .backgroundColor(this.palette.liner)
        .linearGradient({
          angle: 180,
          colors: [['#00000000', 0], ['#47000000', 0.5]]
        })
        .shadow({ radius: this.widthVp * 0.03, color: '#29000000', offsetX: 0, offsetY: this.widthVp * 0.018 })

      // 2. 翻过去的封舌，露出内衬那一面
      if (this.flapAngle() > 90) {
        this.flapInside()
      }

      // 3. 信纸
      FoldedLetter({
        palette: this.palette,
        widthVp: this.widthVp * 0.9,
        heightVp: this.heightVp() * 0.9
      })
        .position({
          x: this.widthVp * 0.05,
          y: this.heightVp() * 0.05 - this.letterSlide() * this.heightVp() * 0.8
        })

      // 4. 口袋（两侧和底下的折边）
      this.pocket()

      // 5. 还没翻过 90° 的封舌
      if (this.flapAngle() <= 90) {
        this.flapOutside()
      }

      // 6. 下半块火漆粘在口袋上，不跟封舌走；裂开时往下掉一点点，露出锯齿缝
      if (this.hasSeal) {
        SealPiece({ sizeVp: this.sealSize(), mark: this.mark, upper: false })
          .position({
            x: this.sealPieceX(),
            y: this.sealPieceLowerY() + this.crack() * this.widthVp * 0.005
          })
          .scale({ x: this.sealScale(), y: this.sealScale() })
          .opacity(this.sealOpacity())
        // 裂缝的锯齿线：真裁剪是直的，线画在缝上读作裂开的茬口（iOS SealCrack）
        Polyline({ width: this.sealSize(), height: this.sealSize() })
          .points(this.sealCrackPoints())
          .fill(Color.Transparent)
          .stroke(withAlpha('#4A1612', 0.9))
          .strokeWidth(0.9)
          .opacity(this.crack() * this.sealOpacity())
          .position({
            x: this.widthVp / 2 - this.sealSize() / 2,
            y: this.sealCenterY() - this.sealSize() / 2 + this.crack() * this.widthVp * 0.005
          })
      }
    }
    .width(this.widthVp)
    .height(this.heightVp())
  }

  /** 翻过去的封舌（> 90°）：信封纸的边 + 缩进去一圈的内衬，压一层暗 */
  @Builder
  private flapInside() {
    Stack({ alignContent: Alignment.TopStart }) {
      Polygon({ width: this.widthVp, height: this.heightVp() })
        .points(flapPoints(this.widthVp, this.heightVp()))
        .fill(this.palette.envelope)
      Polygon({ width: this.widthVp, height: this.heightVp() })
        .points(innerFlapPoints(this.widthVp, this.heightVp()))
        .fill(this.palette.liner)
      Polygon({ width: this.widthVp, height: this.heightVp() })
        .points(innerFlapPoints(this.widthVp, this.heightVp()))
        .fill('#1F000000')
    }
    .width(this.widthVp)
    .height(this.heightVp())
    .rotate({
      x: 1, y: 0, z: 0,
      angle: this.flapAngle(),
      centerX: '50%', centerY: '0%',
      perspective: 0.35
    })
  }

  /** 还没翻过去的封舌（≤ 90°）：信封纸 + 一道很淡的边，带影子；火漆上半块跟着封舌 */
  @Builder
  private flapOutside() {
    Stack({ alignContent: Alignment.TopStart }) {
      Polygon({ width: this.widthVp, height: this.heightVp() })
        .points(flapPoints(this.widthVp, this.heightVp()))
        .fill(this.palette.envelope)
        .shadow({ radius: 1.5, color: '#24000000', offsetX: 0, offsetY: 1 })
      Polygon({ width: this.widthVp, height: this.heightVp() })
        .points(flapPoints(this.widthVp, this.heightVp()))
        .fill(Color.Transparent)
        .stroke(withAlpha(this.palette.envelopeEdge, 0.35))
        .strokeWidth(0.6)
      // 火漆上半块：裂开时绕印心歪 -1.2°（iOS 同款），封舌翻起时跟着走
      if (this.hasSeal) {
        SealPiece({ sizeVp: this.sealSize(), mark: this.mark, upper: true })
          .position({ x: this.sealPieceX(), y: this.sealPieceY() })
          .rotate({ x: 0, y: 0, z: 1, angle: -this.crack() * 1.2 })
          .scale({ x: this.sealScale(), y: this.sealScale() })
          .opacity(this.sealOpacity())
      }
    }
    .width(this.widthVp)
    .height(this.heightVp())
    .rotate({
      x: 1, y: 0, z: 0,
      angle: this.flapAngle(),
      centerX: '50%', centerY: '0%',
      perspective: 0.35
    })
  }

  /** 口袋：V 口的边 + 底下那片折边（折边压在两侧上面，带一道很淡的影子） */
  @Builder
  private pocket() {
    Stack({ alignContent: Alignment.TopStart }) {
      Polygon({ width: this.widthVp, height: this.heightVp() })
        .points(pocketPoints(this.widthVp, this.heightVp()))
        .fill(this.palette.envelope)
      Polyline({ width: this.widthVp, height: this.heightVp() })
        .points(notchEdgePoints(this.widthVp, this.heightVp()))
        .fill(Color.Transparent)
        .stroke(withAlpha(this.palette.envelopeEdge, 0.55))
        .strokeWidth(0.7)
      Polygon({ width: this.widthVp, height: this.heightVp() })
        .points(bottomFlapPoints(this.widthVp, this.heightVp()))
        .fill(this.palette.envelope)
        .shadow({ radius: 1.5, color: '#1A000000', offsetX: 0, offsetY: -1 })
      Polygon({ width: this.widthVp, height: this.heightVp() })
        .points(bottomFlapPoints(this.widthVp, this.heightVp()))
        .fill(Color.Transparent)
        .stroke(withAlpha(this.palette.envelopeEdge, 0.45))
        .strokeWidth(0.7)
      // 信封背面下方的一行小字（「来自 青鸟」）：iOS Georgia 斜体，
      // Harmony serif 同位置同大小（max(11, w*0.036)）
      if (!(typeof this.sender === 'string' && this.sender.length === 0)) {
        Text(this.sender)
          .fontSize(Math.max(11, this.widthVp * 0.036))
          .fontStyle(FontStyle.Italic)
          .fontFamily('serif')
          .fontColor(this.palette.envelopeEdge)
          .width('100%')
          .textAlign(TextAlign.Center)
          .position({ x: 0, y: this.heightVp() * 0.8 })
      }
    }
    .width(this.widthVp)
    .height(this.heightVp())
  }
}

/**
 * 信封里的信纸（折好的，只露上半截）。投信动画收拢那一下也用它。
 * 对应 iOS `SealedEnvelope.swift` 里的 `FoldedLetter`。
 */
@Component
export struct FoldedLetter {
  palette: LetterPalette = LetterPalette.bamboo;
  @Prop widthVp: number = 100;
  @Prop heightVp: number = 100;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.paper)
      // 几道格线，抽出来时看得出是信纸
      ForEach(this.ruleIndexes(), (i: number) => {
        Column()
          .width(this.widthVp * 0.84)
          .height(0.6)
          .backgroundColor(this.palette.rule)
          .position({ x: this.widthVp * 0.08, y: this.heightVp * (0.16 + i * 0.11) })
      }, (i: number): string => `rule:${i}`)
      // 对折的折痕
      Column()
        .width('100%')
        .height(6)
        .linearGradient({
          angle: 180,
          colors: [['#00000000', 0], ['#12000000', 0.5], ['#00000000', 1]]
        })
        .position({ x: 0, y: this.heightVp * 0.5 - 3 })
    }
    .width(this.widthVp)
    .height(this.heightVp)
    .shadow({ radius: 1.5, color: '#1F000000', offsetX: 0, offsetY: 0.5 })
  }

  private ruleIndexes(): number[] {
    return [1, 2, 3, 4, 5, 6];
  }
}
