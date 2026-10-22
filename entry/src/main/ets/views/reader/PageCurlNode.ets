/**
 * 仿真翻页绘制层（10_BUILD_MANUAL.md 3.5）。
 * 当前手势统一走 Edge 整页卷曲（2026-10-23 起，对齐 iOS `.pageCurl`；
 * 下方 Corner A-K 实现保留但未启用，避免上下角捏出锥形狗耳朵）：
 *
 * Edge 整页卷曲：
 * - 折缝 = 贯穿全高的竖直直线，跟手 = 拖拽增量半速（CurlMath.foldFromDrag，
 *   页缘起手退化为对折中点）
 * - 折缝一侧是平面页；被卷起的一半用当前页截图逐条 canvas 镜像铺到
 *   折缝另一侧 = 背面（文字镜像），并做轻微圆柱弯曲
 * - 背面整层 92% 不透明：留 8% 让底下的下一页隐约透上来，模拟薄纸
 *   show-through；再叠折缝高光与折缘投影
 * - 透出页上叠纸底暗化（折缝 18/255 黑 → +20px 峰值 24 → +90px 21 →
 *   +150px 13 → +237px 归 0，前浓后缓），文字保持全对比度
 * - backward 是 forward 的镜像：左侧透出上一页，背面带落在右侧
 *
 * Corner 角卷（A-K 模型，华为 hc4 逐行亮度剖面 + 官方仿真翻页样例；未启用）：
 * - pathA = 折痕曲线 C-E-B-A-K-J 这侧的平面页（当前页截图原样）
 * - pathC = 弦 I-D 与折缘间的背面带：clip + 折线反射矩阵（F 恰映到 A）
 *   画当前页截图 = 镜像背面
 * - 背面暗化画在 pathA 之后（B 左侧被 pathA 盖住的楔形区同压暗）：
 *   弦侧 88% → 折缘 ~98%，折缘受光变亮（hc4 白像素剖面实测）
 * - 弦 I-D 上投阴影带到透出页（端点外延盖 I/D 角隙）
 * - 折缘 D-B 短深、B-A 长浅两条软阴影投平面页，A-K 侧无（hc4 实测）
 *
 * 宿主三页 Stack：底层下一页 / 中层当前页（翻页时隐藏，由截图绘制）/
 * 上层上一页（backward 时就位，透出折缝左侧）。
 * 单位全部物理 px（NodeContainer 画布坐标系）。
 */
import { drawing, common2D } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DrawContext, Frame, FrameNode, NodeController, RenderNode, UIContext } from '@kit.ArkUI';
import {
  CURL_EDGE_RATIO,
  CURL_GRADIENT_RATIO,
  CURL_PEAK_RATIO,
  CurlGeometry,
  CurlPoint,
  PageCurlCorner,
  PageCurlDirection,
  PageCurlMode,
  computeCurlGeometry
} from './CurlMath';

/** 角卷：弦 I-D 侧阴影带宽（透出页上的暗化，hc4 实测 88% → 240px 衰减） */
const CORNER_CHORD_SHADOW_RATIO = 0.22;
const CORNER_CHORD_SHADOW_COLOR = 0x1E000000;
/** 角卷：弦影带端点外延（盖住 I/D 角外的透出隙） */
const CORNER_CHORD_EXT_RATIO = 0.06;
/** 角卷：纸背折缘暗化（越靠折缝越深） */
const CORNER_BACK_EDGE_COLOR = 0x26000000;
/** 角卷：折缘 B-A 投平面页软阴影（长浅；A-K 侧无，hc4 实测） */
const CORNER_FOLD_SHADOW_COLOR = 0x14000000;
const CORNER_FOLD_SHADOW_TAIL = 0x05000000;
const CORNER_FOLD_SHADOW_RATIO = 0.12;
/** 角卷：折缘 D-B 投平面页软阴影（短深，hc4 实测） */
const CORNER_DB_SHADOW_COLOR = 0x1E000000;
const CORNER_DB_SHADOW_TAIL = 0x06000000;
const CORNER_DB_SHADOW_RATIO = 0.03;

const DOMAIN = 0x0000;
const TAG = 'PageCurlNode';

/** 一次翻页的绘制状态（宿主逐帧更新；CurlRenderNode.draw 读取） */
export class CurlPaintState {
  /** 截图源：两向都是当前页；背面由绘制层逐条 canvas 镜像 */
  pixelMap: image.PixelMap | undefined = undefined;
  /** 绘制区宽高（px = 页槽物理像素） */
  viewWidth: number = 1;
  viewHeight: number = 1;
  /** 折缝 x（px；宿主用 CurlMath.foldFromDrag 从拖拽增量算好喂入） */
  positionX: number = 0;
  /** 翻页方向（宿主逻辑用：autoFlip 端点 / 提交判定；绘制两向同构） */
  direction: PageCurlDirection = PageCurlDirection.Forward;
  /** 翻页模式：Edge 边折（竖直折缝）/ Corner 角卷（A-K 模型） */
  mode: PageCurlMode = PageCurlMode.Edge;
  /** 角卷抓取角（mode = Corner 时有效） */
  corner: PageCurlCorner = PageCurlCorner.TopRight;
  /** 角卷触点 A（px；宿主 constrainTouchPoint 约束后喂入） */
  touchX: number = 0;
  touchY: number = 0;
  /** 首尾页越界：只画浅折缝，不画背面带（没有目标页可透出） */
  boundary: boolean = false;
  /** 纸背颜色（主题 background；翻页时纸背不是镜像文字，是浅色纸） */
  paperColor: number = 0xFFFAF7F2;
}

function clampValue(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(v, lo), hi);
}

/** 整页截图原样铺进画布（px verts）。drawPixelMapMesh 只认 brush 不认 pen，必须先 attachBrush。 */
function drawMesh(canvas: drawing.Canvas, pm: image.PixelMap, w: number, h: number): void {
  const verts: number[] = [0, 0, w, 0, 0, h, w, h];
  const brush = new drawing.Brush();
  canvas.attachBrush(brush);
  canvas.drawPixelMapMesh(pm, 1, 1, verts, 0, null, 0);
  canvas.detachBrush();
}

/**
 * 竖直渐变带：[x0, x1] 上水平线性渐变，铺满全高。
 * colors/pos 为多段梯度（pos 为 0-1 位置数组，null 则均布）。
 */
function drawBand(canvas: drawing.Canvas, x0: number, x1: number,
  colors: number[], pos: number[] | null, h: number): void {
  if (x1 - x0 < 0.5) {
    return;
  }
  const start: common2D.Point = { x: x0, y: 0 };
  const end: common2D.Point = { x: x1, y: 0 };
  const shader = drawing.ShaderEffect.createLinearGradient(start, end,
    colors, drawing.TileMode.CLAMP, pos);
  const brush = new drawing.Brush();
  brush.setShaderEffect(shader);
  canvas.attachBrush(brush);
  canvas.drawRect(x0, 0, x1, h);
  canvas.detachBrush();
}

/**
 * 沿线段 p1p2 的软阴影带：向背离 awayFrom 的一侧延展 width，
 * 线段处 deepColor → 带尾 tailColor。平行四边形 + 垂直线性渐变，不旋转画布。
 */
function drawEdgeShadowBand(canvas: drawing.Canvas, p1: CurlPoint, p2: CurlPoint,
  awayFrom: CurlPoint, width: number, deepColor: number, tailColor: number = 0x00000000): void {
  const dx = p2.x - p1.x;
  const dy = p2.y - p1.y;
  const len = Math.hypot(dx, dy);
  if (len < 1 || width <= 0) {
    return;
  }
  let nx = -dy / len;
  let ny = dx / len;
  const midX = (p1.x + p2.x) / 2;
  const midY = (p1.y + p2.y) / 2;
  if (nx * (midX - awayFrom.x) + ny * (midY - awayFrom.y) < 0) {
    nx = -nx;
    ny = -ny;
  }
  const path = new drawing.Path();
  path.moveTo(p1.x, p1.y);
  path.lineTo(p2.x, p2.y);
  path.lineTo(p2.x + nx * width, p2.y + ny * width);
  path.lineTo(p1.x + nx * width, p1.y + ny * width);
  path.close();
  const start: common2D.Point = { x: midX, y: midY };
  const end: common2D.Point = { x: midX + nx * width, y: midY + ny * width };
  const shader = drawing.ShaderEffect.createLinearGradient(start, end,
    [deepColor, tailColor], drawing.TileMode.CLAMP, null);
  const brush = new drawing.Brush();
  brush.setShaderEffect(shader);
  canvas.attachBrush(brush);
  canvas.drawPath(path);
  canvas.detachBrush();
}

/** 角卷 pathA：折痕曲线这侧的平面页（官方 TopRight/BottomRight 同式，
 * 左角为镜像推广；四角起止点不同，曲线段 C-E-B-A-K-J 一致） */
function buildCornerPathA(corner: PageCurlCorner, geo: CurlGeometry,
  W: number, H: number): drawing.Path {
  const path = new drawing.Path();
  if (corner === PageCurlCorner.TopRight) {
    path.moveTo(0, 0);
  } else if (corner === PageCurlCorner.BottomRight) {
    path.moveTo(0, 0);
    path.lineTo(0, H);
  } else if (corner === PageCurlCorner.TopLeft) {
    path.moveTo(W, 0);
  } else {
    path.moveTo(W, 0);
    path.lineTo(W, H);
  }
  path.lineTo(geo.C.x, geo.C.y);
  path.quadTo(geo.E.x, geo.E.y, geo.B.x, geo.B.y);
  path.lineTo(geo.A.x, geo.A.y);
  path.lineTo(geo.K.x, geo.K.y);
  path.quadTo(geo.H.x, geo.H.y, geo.J.x, geo.J.y);
  if (corner === PageCurlCorner.TopRight) {
    path.lineTo(W, H);
    path.lineTo(0, H);
  } else if (corner === PageCurlCorner.BottomRight) {
    path.lineTo(W, 0);
  } else if (corner === PageCurlCorner.TopLeft) {
    path.lineTo(0, H);
    path.lineTo(W, H);
  } else {
    path.lineTo(0, 0);
  }
  path.close();
  return path;
}

/** 角卷 pathC：弦 I-D 与折缘间的背面带（四角同构直线五边形，官方同式） */
function buildCornerPathC(geo: CurlGeometry): drawing.Path {
  const path = new drawing.Path();
  path.moveTo(geo.I.x, geo.I.y);
  // 自由边 I→D 不是直尺：向背离折点 A 的方向鼓一条弧，纸背才有卷曲感
  const mx = (geo.I.x + geo.D.x) / 2;
  const my = (geo.I.y + geo.D.y) / 2;
  const vx = mx - geo.A.x;
  const vy = my - geo.A.y;
  const len = Math.hypot(vx, vy);
  const chord = Math.hypot(geo.D.x - geo.I.x, geo.D.y - geo.I.y);
  if (len > 1) {
    const bow = Math.min(160, chord * 0.22);
    path.quadTo(mx + vx / len * bow, my + vy / len * bow, geo.D.x, geo.D.y);
  } else {
    path.lineTo(geo.D.x, geo.D.y);
  }
  path.lineTo(geo.B.x, geo.B.y);
  path.lineTo(geo.A.x, geo.A.y);
  path.lineTo(geo.K.x, geo.K.y);
  path.close();
  return path;
}

/** 单帧绘制节点（官方样例同款：每帧 new 一个换进 NodeContainer 触发重绘） */
export class CurlRenderNode extends RenderNode {
  private readonly paintState: CurlPaintState;

  constructor(paintState: CurlPaintState) {
    super();
    this.paintState = paintState;
    const frame: Frame = {
      x: 0,
      y: 0,
      width: paintState.viewWidth,
      height: paintState.viewHeight
    };
    this.frame = frame;
  }

  draw(context: DrawContext): void {
    const state = this.paintState;
    const pm = state.pixelMap;
    if (pm === undefined) {
      return;
    }
    const W = Math.max(1, state.viewWidth);
    const H = Math.max(1, state.viewHeight);
    const canvas = context.canvas;
    if (state.mode === PageCurlMode.Corner) {
      this.drawCornerCurl(canvas, pm, W, H);
      return;
    }
    const fold = clampValue(state.positionX, 0, W);
    // 非越界翻页还没起卷：中层页已藏，画布整页原样兜底（不闪目标页）。
    // 越界翻页（boundary）中层不藏，不需要兜底
    if (!state.boundary && fold > W - 2) {
      drawMesh(canvas, pm, W, H);
      return;
    }
    if (fold > W - 2 || fold < 2) {
      return; // 越界翻页未起卷 / 已翻尽（透出目标页）
    }
    if (state.boundary) {
      this.drawBoundaryCurl(canvas, pm, W, H, fold);
      return;
    }
    this.drawEdgeCurl(canvas, pm, W, H, fold);
  }

  /** 首尾页越界：只画浅折缝 + 纸底暗化，不画背面（没有目标页可透出） */
  private drawBoundaryCurl(canvas: drawing.Canvas, pm: image.PixelMap,
    W: number, H: number, fold: number): void {
    const state = this.paintState;
    canvas.save();
    const leftClip = new drawing.Path();
    leftClip.moveTo(0, 0);
    leftClip.lineTo(fold, 0);
    leftClip.lineTo(fold, H);
    leftClip.lineTo(0, H);
    leftClip.close();
    canvas.clipPath(leftClip);
    drawMesh(canvas, pm, W, H);
    canvas.restore();

    const edgeW = CURL_EDGE_RATIO * W;
    const gradW = CURL_GRADIENT_RATIO * W;
    if (state.direction === PageCurlDirection.Forward) {
      drawBand(canvas, fold - edgeW, fold, [0x00000000, 0x03000000], null, H);
      drawBand(canvas, fold, fold + gradW,
        [0x12000000, 0x18000000, 0x15000000, 0x0D000000, 0x00000000],
        [0, (CURL_PEAK_RATIO * W) / gradW, 90 / 237, 150 / 237, 1], H);
    } else {
      drawBand(canvas, fold, fold + edgeW, [0x03000000, 0x00000000], null, H);
      drawBand(canvas, fold - gradW, fold,
        [0x00000000, 0x0D000000, 0x15000000, 0x18000000, 0x12000000],
        [0, 87 / 237, 147 / 237, 1 - (CURL_PEAK_RATIO * W) / gradW, 1], H);
    }
  }

  /**
   * 边折（iOS `.pageCurl` 的纸感近似）：平面页 + 折起的**背面带**。
   * - forward：平面页留在折缝左侧；右侧被翻起的部分镜像到左侧当背面，
   *   下一页从折缝右侧透出
   * - backward：平面页留在折缝右侧；左侧被翻起的部分镜像到右侧当背面，
   *   上一页从折缝左侧透出
   * 背面用 32 段网格沿折线做轻微圆柱弯曲（中间鼓、两端收），再叠
   * 折缝高光与纸底投影 —— 不再是无背面的竖直切缝。
   */
  private drawEdgeCurl(canvas: drawing.Canvas, pm: image.PixelMap,
    W: number, H: number, fold: number): void {
    const state = this.paintState;
    const forward = state.direction === PageCurlDirection.Forward;
    const edgeW = CURL_EDGE_RATIO * W;
    const gradW = CURL_GRADIENT_RATIO * W;

    // 1) 平面页：折缝一侧的正面（未翻起的部分）
    canvas.save();
    const front = new drawing.Path();
    if (forward) {
      front.moveTo(0, 0);
      front.lineTo(fold, 0);
      front.lineTo(fold, H);
      front.lineTo(0, H);
    } else {
      front.moveTo(fold, 0);
      front.lineTo(W, 0);
      front.lineTo(W, H);
      front.lineTo(fold, H);
    }
    front.close();
    canvas.clipPath(front);
    drawMesh(canvas, pm, W, H);
    canvas.restore();

    // 2) 背面带：源页被折起的那一半，逐条 canvas 镜像铺到折线另一侧
    //    （forward 源 [f,W] → 折缝左侧；backward 源 [0,f] → 折缝右侧），
    //    每条做轻微圆柱弯曲（中间鼓、两端收）
    const bandLeft = forward ? 2 * fold - W : fold;
    const bandRight = forward ? fold : 2 * fold;
    const x0 = Math.max(0, bandLeft);
    const x1 = Math.min(W, bandRight);
    const freeEdge = forward ? x0 : x1;
    const edgeAmp = 0.07 * Math.max(1, x1 - x0);
    const freeAt = (y: number): number => {
      const bulge = edgeAmp * Math.sin(Math.PI * Math.min(1, Math.max(0, y / H)));
      return forward ? freeEdge - bulge : freeEdge + bulge;
    };
    if (x1 - x0 > 0.5) {
      canvas.save();
      // 自由边不是直尺：中段向外鼓一点，纸卷才有厚度感
      const clip = new drawing.Path();
      if (forward) {
        clip.moveTo(freeAt(0), 0);
        clip.lineTo(fold, 0);
        clip.lineTo(fold, H);
        clip.lineTo(freeAt(H), H);
        for (let i = 1; i <= 12; i++) {
          const y = H - H * i / 12;
          clip.lineTo(freeAt(y), y);
        }
      } else {
        clip.moveTo(fold, 0);
        clip.lineTo(freeAt(0), 0);
        for (let i = 1; i <= 12; i++) {
          const y = H * i / 12;
          clip.lineTo(freeAt(y), y);
        }
        clip.lineTo(fold, H);
      }
      clip.close();
      canvas.clipPath(clip);
      // 背面 = 当前页关于折缝的镜像 + 竖向分条做圆柱弯曲：
      // 反射矩阵保证文字真镜像；每条源/目标同宽，但目标按 sin 弧平移，
      // 让背面文字越靠自由边越被压缩，读起来是卷起的纸而不是平板反射。
      // 不做 saveLayer 半透（2% 透出不可感知，全屏离屏层是卡顿主因之二）
      const mirror = new drawing.Matrix();
      mirror.setMatrix([-1, 0, 2 * fold, 0, 1, 0, 0, 0, 1]);
      canvas.concatMatrix(mirror);
      const strips = 12;
      const bandW = forward ? W - fold : fold;
      const cy = H / 2;
      for (let k = 0; k < strips; k++) {
        const t0 = k / strips;
        const t1 = (k + 1) / strips;
        const sx0 = forward ? fold + bandW * t0 : bandW * t0;
        const sx1 = forward ? fold + bandW * t1 : bandW * t1;
        const curve0 = 0.10 * bandW * Math.sin(Math.PI * t0);
        const curve1 = 0.10 * bandW * Math.sin(Math.PI * t1);
        const scale = 1 + 0.06 * Math.sin(Math.PI * (t0 + t1) / 2);
        const src: common2D.Rect = { left: sx0, top: 0, right: sx1, bottom: H };
        const dst: common2D.Rect = {
          left: sx0 + curve0,
          top: cy - cy * scale,
          right: sx1 + curve1,
          bottom: cy + cy * scale
        };
        canvas.drawImageRectWithSrc(pm, src, dst);
      }
      canvas.restore(); // clip（矩阵/裁剪一并回退）

      // 背面暗化：折缝受光（0x04）→ 自由边更暗（0x1E）
      if (forward) {
        drawBand(canvas, x0, x1,
          [0x33000000, 0x28000000, 0x14000000, 0x05000000], [0, 0.35, 0.75, 1], H);
      } else {
        drawBand(canvas, x0, x1,
          [0x05000000, 0x14000000, 0x28000000, 0x33000000], [0, 0.25, 0.65, 1], H);
      }
      canvas.restore(); // clip

      // 2b) 自由边：投在平面页上的窄影（让“切口”读成纸边）
      const edgeShadowW = 0.05 * W;
      if (forward) {
        drawBand(canvas, freeEdge - edgeShadowW, freeEdge, [0x00000000, 0x40000000], null, H);
        drawBand(canvas, freeEdge - 1.5, freeEdge + 1.5,
          [0x00000000, 0x3AFFFFFF], null, H);
      } else {
        drawBand(canvas, freeEdge, freeEdge + edgeShadowW, [0x40000000, 0x00000000], null, H);
        drawBand(canvas, freeEdge - 1.5, freeEdge + 1.5,
          [0x3AFFFFFF, 0x00000000], null, H);
      }
    }

    // 3) 折缝暗缘 + 投在透出页上的暗化（方向镜像：阴影永远落在透出页）
    if (forward) {
      drawBand(canvas, fold - edgeW, fold, [0x00000000, 0x03000000], null, H);
      drawBand(canvas, fold, fold + gradW,
        [0x12000000, 0x18000000, 0x15000000, 0x0D000000, 0x00000000],
        [0, (CURL_PEAK_RATIO * W) / gradW, 90 / 237, 150 / 237, 1], H);
    } else {
      drawBand(canvas, fold, fold + edgeW, [0x03000000, 0x00000000], null, H);
      drawBand(canvas, fold - gradW, fold,
        [0x00000000, 0x0D000000, 0x15000000, 0x18000000, 0x12000000],
        [0, 87 / 237, 147 / 237, 1 - (CURL_PEAK_RATIO * W) / gradW, 1], H);
    }

    // 4) 折缝高光：纸被折起的受光棱
    drawBand(canvas, fold - 1.5, fold + 1.5, [0x18FFFFFF, 0x00FFFFFF], null, H);
  }

  /**
   * 角卷（A-K 模型，华为 hc4 逐行剖面 + 官方样例）绘制序：
   * 1) 弦 I-D 阴影带：投在透出的目标页上（端点外延盖 I/D 角隙）
   * 2) 背面带 pathC：clip + 折线反射（F 映到 A）画当前页截图
   * 3) 平面页 pathA：折痕曲线这侧的当前页原样
   * 4) 背面暗化：弦侧 → 折缘渐变，画在 pathA 之后（楔形区同压暗）
   * 5) 折缘软阴影：D-B 短深、B-A 长浅投在平面页上（A-K 侧无）
   */
  private drawCornerCurl(canvas: drawing.Canvas, pm: image.PixelMap,
    W: number, H: number): void {
    const state = this.paintState;
    const A = new CurlPoint(state.touchX, state.touchY);
    const geo = computeCurlGeometry(state.corner, A, W, H);
    if (geo.aToF < 2) {
      return; // 触点还贴着抓取角：未起卷
    }
    const chordMid = new CurlPoint((geo.I.x + geo.D.x) / 2, (geo.I.y + geo.D.y) / 2);
    // 1) 弦影带（透出的目标页上，hc4 实测弦侧暗化）
    const cdx = geo.D.x - geo.I.x;
    const cdy = geo.D.y - geo.I.y;
    const chordLen = Math.max(1, Math.hypot(cdx, cdy));
    const chordExt = CORNER_CHORD_EXT_RATIO * W;
    drawEdgeShadowBand(canvas,
      new CurlPoint(geo.I.x - cdx / chordLen * chordExt, geo.I.y - cdy / chordLen * chordExt),
      new CurlPoint(geo.D.x + cdx / chordLen * chordExt, geo.D.y + cdy / chordLen * chordExt),
      geo.A, CORNER_CHORD_SHADOW_RATIO * W, CORNER_CHORD_SHADOW_COLOR);
    // 2) 平面页（先画：B 左侧被 pathC 覆盖成背面带，hc4 逐行剖面）
    const pathA = buildCornerPathA(state.corner, geo, W, H);
    canvas.save();
    canvas.clipPath(pathA);
    drawMesh(canvas, pm, W, H);
    canvas.restore();
    // 3) 背面带：华为阅读同款「纸背」——不是镜像文字，而是一张浅色纸。
    //    pathC 仍用官方五边形 + 折线几何；里面填主题纸色，再叠折缝方向暗化，
    //    这样翻起来是纸的背面，不会出现两面文字重影。
    const pathC = buildCornerPathC(geo);
    // 纸背投在平面页/下一页上的软影（三层偏移叠出模糊边）
    const shadowBrush = new drawing.Brush();
    shadowBrush.setShaderEffect(drawing.ShaderEffect.createColorShader(0x0A000000));
    for (let i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(-3 * (i + 1), 2 * (i + 1));
      canvas.attachBrush(shadowBrush);
      canvas.drawPath(pathC);
      canvas.detachBrush();
      canvas.restore();
    }
    canvas.save();
    canvas.clipPath(pathC);
    const paperBrush = new drawing.Brush();
    paperBrush.setShaderEffect(drawing.ShaderEffect.createColorShader(state.paperColor));
    canvas.attachBrush(paperBrush);
    canvas.drawPath(pathC);
    canvas.detachBrush();
    // 4) 纸背曲面暗化：弦侧透明 → 折缘更深（纸卷向光/背光）
    const backStart: common2D.Point = { x: chordMid.x, y: chordMid.y };
    const backEnd: common2D.Point = { x: geo.A.x, y: geo.A.y };
    const backShader = drawing.ShaderEffect.createLinearGradient(backStart, backEnd,
      [0x1AFFFFFF, 0x00000000, CORNER_BACK_EDGE_COLOR],
      drawing.TileMode.CLAMP, [0, 0.30, 1]);
    const backBrush = new drawing.Brush();
    backBrush.setShaderEffect(backShader);
    canvas.attachBrush(backBrush);
    canvas.drawPath(pathC);
    canvas.detachBrush();
    canvas.restore(); // clip
    // 4b) 折缘受光：沿 B-A 一条很淡的高光（纸被折起的棱）
    drawEdgeShadowBand(canvas, geo.B, geo.A, chordMid,
      0.025 * W, 0x1AFFFFFF, 0x00FFFFFF);
    // 5) 折缘软阴影（平面页侧，hc4 实测：D-B 短深、B-A 长浅、A-K 无）
    drawEdgeShadowBand(canvas, geo.D, geo.B, chordMid,
      CORNER_DB_SHADOW_RATIO * W, CORNER_DB_SHADOW_COLOR, CORNER_DB_SHADOW_TAIL);
    drawEdgeShadowBand(canvas, geo.B, geo.A, chordMid,
      CORNER_FOLD_SHADOW_RATIO * W, CORNER_FOLD_SHADOW_COLOR, CORNER_FOLD_SHADOW_TAIL);
  }
}

/** NodeContainer 控制器：持一个根 FrameNode 和一个**持久** CurlRenderNode。
 *  逐帧只改共享 paint 状态 + invalidate() 标脏（vsync 对齐重绘）；
 *  不再每帧 new 节点 remove/append —— 那会触发 NodeContainer 重排，
 *  是翻页卡顿的主因之一 */
export class CurlNodeController extends NodeController {
  private rootNode: FrameNode | null = null;
  private holder: RenderNode | null = null;
  private node: CurlRenderNode | null = null;

  makeNode(uiContext: UIContext): FrameNode | null {
    if (this.rootNode === null) {
      this.rootNode = new FrameNode(uiContext);
      this.holder = this.rootNode.getRenderNode();
    }
    return this.rootNode;
  }

  /** 标脏重绘：节点不存在时挂一个（状态是共享引用，draw 时读最新值） */
  updateFrame(state: CurlPaintState): void {
    const holder = this.holder;
    if (holder === null) {
      hilog.warn(DOMAIN, TAG, 'updateFrame before makeNode');
      return;
    }
    try {
      if (this.node === null) {
        this.node = new CurlRenderNode(state);
        holder.appendChild(this.node);
      }
      this.node.invalidate();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'updateFrame failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 翻页结束：撤掉绘制节点（下次翻页按新尺寸重建） */
  clearNode(): void {
    const holder = this.holder;
    try {
      if (holder !== null && this.node !== null) {
        holder.removeChild(this.node);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clearNode failed: %{public}s', JSON.stringify(err));
    }
    this.node = null;
  }
}
