/**
 * 翻页纯逻辑单测（10_BUILD_MANUAL.md 3.5）。
 * 不变量来自华为阅读真机实测（1080px 屏，Mate X6）+ 官方仿真翻页样例：
 * - 边折：折缝从平出发按拖拽增量半速跟随（foldFromDrag）；
 *   页缘起手退化为对折中点（forward (W + fingerX)/2、backward fingerX/2），
 *   永远夹在 [0, W]，随手指单调移动；中间起手不跳变（从平开始）
 * - 角卷：起手角落区 = 距屏角双轴 0.25 屏宽（(1050,120)=角、(1000,2000)=边）；
 *   触点约束 0.7 屏宽圆；A-K 全点 = 官方 calcPointsXY 同式；
 *   反射矩阵把 F 精确映到 A（折线反射，四角通用）
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  BOUNDARY_MAX_RATIO,
  CORNER_ZONE_RATIO,
  CURL_EDGE_RATIO,
  CURL_GRADIENT_RATIO,
  CURL_PEAK_RATIO,
  CurlPoint,
  PageCurlCorner,
  PageCurlDirection,
  boundaryFold,
  boundaryOverscroll,
  computeCurlGeometry,
  constrainTouchPoint,
  cornerAtStart,
  cornerPoint,
  cornerProgress,
  easeInOutCubic,
  easeOutCubic,
  flipDurationMs,
  foldFromDrag,
  reflectionMatrixValues
} from '../../main/ets/views/reader/CurlMath';

const W = 1080;
const H = 2440;

function assertNear(actual: number, expected: number, tol: number): void {
  expect(Math.abs(actual - expected) <= tol).assertTrue();
}

export default function curlMathTest() {
  describe('CurlMath', () => {
    it('forward_edge_start_reduces_to_measured_midpoint', 0, () => {
      // 页缘起手（startX = W）退化为华为实测「对折中点」：
      // 手指 526、屏宽 1080 → 折缝 803
      expect(foldFromDrag(PageCurlDirection.Forward, 1080, 1080, 526)).assertEqual(803);
      expect(foldFromDrag(PageCurlDirection.Forward, 1000, 1000, 0)).assertEqual(500);
      expect(foldFromDrag(PageCurlDirection.Forward, 1000, 1000, 400)).assertEqual(700);
    });

    it('forward_finger_at_right_edge_is_unflipped', 0, () => {
      expect(foldFromDrag(PageCurlDirection.Forward, 1000, 1000, 1000)).assertEqual(1000);
      expect(foldFromDrag(PageCurlDirection.Forward, 1000, 1000, 999)).assertEqual(999.5);
    });

    it('backward_edge_start_reduces_to_half_of_finger', 0, () => {
      expect(foldFromDrag(PageCurlDirection.Backward, 1000, 0, 0)).assertEqual(0);
      expect(foldFromDrag(PageCurlDirection.Backward, 1000, 0, 500)).assertEqual(250);
      expect(foldFromDrag(PageCurlDirection.Backward, 1000, 0, 1000)).assertEqual(500);
    });

    it('mid_page_start_begins_flat_no_jump', 0, () => {
      // 中间起手（用户报「无法翻页」根因）：起手时折缝 = 平，不瞬间跳到半翻
      expect(foldFromDrag(PageCurlDirection.Forward, 1000, 500, 500)).assertEqual(1000);
      expect(foldFromDrag(PageCurlDirection.Forward, 1000, 500, 480)).assertEqual(990);
      // 按增量半速跟随：手指从中间拖到 0 只走 1/4 页
      expect(foldFromDrag(PageCurlDirection.Forward, 1000, 500, 0)).assertEqual(750);
      // 左缘起手：原地 / 反向（右移）都保持平
      expect(foldFromDrag(PageCurlDirection.Forward, 1000, 0, 0)).assertEqual(1000);
      expect(foldFromDrag(PageCurlDirection.Forward, 1000, 0, 1000)).assertEqual(1000);
      // backward 中间起手同理
      expect(foldFromDrag(PageCurlDirection.Backward, 1000, 600, 600)).assertEqual(0);
      expect(foldFromDrag(PageCurlDirection.Backward, 1000, 600, 1000)).assertEqual(200);
    });

    it('fold_clamped_into_view', 0, () => {
      expect(foldFromDrag(PageCurlDirection.Forward, 1000, 1000, -100)).assertEqual(450);
      expect(foldFromDrag(PageCurlDirection.Forward, 1000, 1000, 2000)).assertEqual(1000);
      expect(foldFromDrag(PageCurlDirection.Backward, 1000, 0, -50)).assertEqual(0);
      expect(foldFromDrag(PageCurlDirection.Backward, 1000, 0, 3000)).assertEqual(1000);
    });

    it('invalid_width_falls_back_to_one', 0, () => {
      // viewWidth 非法按 1 处理：折缝夹在 [0,1] 内不越界
      expect(foldFromDrag(PageCurlDirection.Forward, 0, 10, 5)).assertEqual(0);
      expect(foldFromDrag(PageCurlDirection.Backward, -5, 10, 20)).assertEqual(1);
    });

    it('fold_follows_finger_monotonically', 0, () => {
      // forward 左滑：手指 1000 → 0，折缝 1000 → 500 单调减
      let prev = foldFromDrag(PageCurlDirection.Forward, 1080, 1080, 1000);
      for (let fx = 980; fx >= 0; fx -= 100) {
        const fold = foldFromDrag(PageCurlDirection.Forward, 1080, 1080, fx);
        expect(fold < prev).assertTrue();
        prev = fold;
      }
      // backward 右滑：手指 0 → 1000，折缝 0 → 500 单调增
      prev = foldFromDrag(PageCurlDirection.Backward, 1080, 0, 0);
      for (let fx = 100; fx <= 1000; fx += 100) {
        const fold = foldFromDrag(PageCurlDirection.Backward, 1080, 0, fx);
        expect(fold > prev).assertTrue();
        prev = fold;
      }
    });

    it('huawei_measured_gradient_ratios', 0, () => {
      // 1080px 实测：峰值 20px、总宽 237px、微暗缘 6px
      expect(Math.round(CURL_PEAK_RATIO * 1080)).assertEqual(20);
      expect(Math.round(CURL_GRADIENT_RATIO * 1080)).assertEqual(237);
      expect(Math.round(CURL_EDGE_RATIO * 1080)).assertEqual(6);
    });

    it('direction_enum_values', 0, () => {
      expect(PageCurlDirection.Forward).assertEqual('forward');
      expect(PageCurlDirection.Backward).assertEqual('backward');
    });

    // ---- 角卷 ----

    it('corner_point_coordinates', 0, () => {
      expect(cornerPoint(PageCurlCorner.TopRight, W, H).x).assertEqual(W);
      expect(cornerPoint(PageCurlCorner.TopRight, W, H).y).assertEqual(0);
      expect(cornerPoint(PageCurlCorner.BottomRight, W, H).x).assertEqual(W);
      expect(cornerPoint(PageCurlCorner.BottomRight, W, H).y).assertEqual(H);
      expect(cornerPoint(PageCurlCorner.TopLeft, W, H).x).assertEqual(0);
      expect(cornerPoint(PageCurlCorner.TopLeft, W, H).y).assertEqual(0);
      expect(cornerPoint(PageCurlCorner.BottomLeft, W, H).x).assertEqual(0);
      expect(cornerPoint(PageCurlCorner.BottomLeft, W, H).y).assertEqual(H);
    });

    it('corner_at_start_matches_huawei_calibration', 0, () => {
      // 实测校准（Mate X6，1080×2440，zone = 0.25×1080 = 270）
      expect(Math.round(CORNER_ZONE_RATIO * W)).assertEqual(270);
      // (1050,120) 右上角、(1000,2000) 边缘、(1050,1200) 边缘
      expect(cornerAtStart(true, 1050, 120, W, H)).assertEqual(PageCurlCorner.TopRight);
      expect(cornerAtStart(true, 1000, 2000, W, H)).assertUndefined();
      expect(cornerAtStart(true, 1050, 1200, W, H)).assertUndefined();
      // 右下角
      expect(cornerAtStart(true, 1050, 2300, W, H)).assertEqual(PageCurlCorner.BottomRight);
      // 左角只认 backward
      expect(cornerAtStart(false, 30, 100, W, H)).assertEqual(PageCurlCorner.TopLeft);
      expect(cornerAtStart(false, 30, 2380, W, H)).assertEqual(PageCurlCorner.BottomLeft);
      expect(cornerAtStart(true, 30, 100, W, H)).assertUndefined();
      expect(cornerAtStart(false, 1050, 120, W, H)).assertUndefined();
      // 角落区外（x 过深 / y 居中）
      expect(cornerAtStart(false, 400, 100, W, H)).assertUndefined();
      expect(cornerAtStart(true, 1050, 1201, W, H)).assertUndefined();
    });

    it('constrain_touch_point_to_circle', 0, () => {
      // TopRight：r = 756，圆心 (324, 0)；触点 (600,700) 圆内原样保留（华为跟手）
      const a = constrainTouchPoint(PageCurlCorner.TopRight, 600, 700, W, H);
      expect(a.x).assertEqual(600);
      expect(a.y).assertEqual(700);
      // 贴角触点不出 NaN
      const b = constrainTouchPoint(PageCurlCorner.TopRight, 1080, 0, W, H);
      expect(b.x).assertEqual(1080);
      expect(b.y).assertEqual(0);
      // 左角镜像：圆心 (756, 0)，深触点夹回弧上
      const c = constrainTouchPoint(PageCurlCorner.TopLeft, 100, 500, W, H);
      assertNear(c.x, 100, 0.01);
      assertNear(c.y, 375.8, 0.5);
      // 底角：圆内原样保留
      const d = constrainTouchPoint(PageCurlCorner.BottomRight, 600, 1800, W, H);
      expect(d.x).assertEqual(600);
      expect(d.y).assertEqual(1800);
      // 触点圆内原样保留
      const e = constrainTouchPoint(PageCurlCorner.TopRight, 1000, 200, W, H);
      expect(e.x).assertEqual(1000);
      expect(e.y).assertEqual(200);
    });

    it('curl_geometry_matches_official_formula', 0, () => {
      // 官方 calcPointsXY 手算基准（TopRight，A=(600,700)，见 3.5 任务卡）
      const geo = computeCurlGeometry(PageCurlCorner.TopRight, new CurlPoint(600, 700), W, H);
      assertNear(geo.E.x, 329.58, 0.5);
      expect(geo.E.y).assertEqual(0);
      expect(geo.H.x).assertEqual(W);
      assertNear(geo.H.y, 514.57, 0.5);
      assertNear(geo.C.x, -45.63, 0.5);
      expect(geo.C.y).assertEqual(0);
      expect(geo.J.x).assertEqual(W);
      assertNear(geo.J.y, 771.86, 0.5);
      assertNear(geo.B.x, 464.79, 1);
      assertNear(geo.B.y, 350, 1);
      assertNear(geo.K.x, 840, 1);
      assertNear(geo.K.y, 607.3, 1);
      assertNear(geo.D.x, 269.58, 1);
      assertNear(geo.D.y, 87.5, 1);
      assertNear(geo.I.x, 1020, 1);
      assertNear(geo.I.y, 602.1, 1);
      assertNear(geo.aToF, 848.5, 1);
    });

    it('reflection_maps_F_to_A_all_corners', 0, () => {
      // 折线反射：M·(F-E)+E = A（四角通用，容差 1px）
      const cases: PageCurlCorner[] = [
        PageCurlCorner.TopRight, PageCurlCorner.BottomRight,
        PageCurlCorner.TopLeft, PageCurlCorner.BottomLeft
      ];
      const touches: CurlPoint[] = [
        new CurlPoint(600, 700), new CurlPoint(600, 1800),
        new CurlPoint(400, 500), new CurlPoint(400, 2000)
      ];
      for (let i = 0; i < cases.length; i++) {
        const geo = computeCurlGeometry(cases[i], touches[i], W, H);
        const m = reflectionMatrixValues(geo);
        const fx = geo.F.x - geo.E.x;
        const fy = geo.F.y - geo.E.y;
        const rx = m[0] * fx + m[1] * fy + m[2] + geo.E.x;
        const ry = m[3] * fx + m[4] * fy + m[5] + geo.E.y;
        assertNear(rx, touches[i].x, 1);
        assertNear(ry, touches[i].y, 1);
      }
    });

    it('curl_geometry_no_nan_when_A_on_corner_axis', 0, () => {
      // A 与 F 同轴 / 重合：微扰保护，全点有限
      const probes: CurlPoint[] = [
        new CurlPoint(1080, 1), new CurlPoint(1080, 0), new CurlPoint(1079, 0),
        new CurlPoint(0, 2440), new CurlPoint(1, 2440), new CurlPoint(0, 2439)
      ];
      const corners: PageCurlCorner[] = [
        PageCurlCorner.TopRight, PageCurlCorner.TopRight, PageCurlCorner.TopRight,
        PageCurlCorner.BottomLeft, PageCurlCorner.BottomLeft, PageCurlCorner.BottomLeft
      ];
      for (let i = 0; i < probes.length; i++) {
        const geo = computeCurlGeometry(corners[i], probes[i], W, H);
        const pts: CurlPoint[] = [geo.A, geo.F, geo.B, geo.C, geo.D, geo.E, geo.H, geo.I, geo.J, geo.K];
        for (let j = 0; j < pts.length; j++) {
          expect(Number.isFinite(pts[j].x)).assertTrue();
          expect(Number.isFinite(pts[j].y)).assertTrue();
        }
      }
    });

    it('corner_progress_zero_at_rest_full_at_diagonal', 0, () => {
      // A 贴 F：0；A 到对角：1
      const rest = cornerProgress(PageCurlCorner.TopRight,
        new CurlPoint(W, 0), W, H);
      expect(rest).assertEqual(0);
      const full = cornerProgress(PageCurlCorner.TopRight,
        new CurlPoint(0, H), W, H);
      assertNear(full, 1, 1e-9);
      // 实测基准：A=(600,700) → |A-F|/对角线 ≈ 0.318
      const mid = cornerProgress(PageCurlCorner.TopRight,
        new CurlPoint(600, 700), W, H);
      assertNear(mid, 0.318, 0.01);
    });

    it('constrain_touch_point_no_nan_out_of_domain', 0, () => {
      // 触点甩出屏外：夹回不出 NaN
      const out1 = constrainTouchPoint(PageCurlCorner.TopRight, -500, 300, W, H);
      expect(Number.isFinite(out1.x)).assertTrue();
      expect(Number.isFinite(out1.y)).assertTrue();
      expect(out1.x >= 0).assertTrue();
      const out2 = constrainTouchPoint(PageCurlCorner.BottomLeft, 2000, -100, W, H);
      expect(Number.isFinite(out2.x)).assertTrue();
      expect(Number.isFinite(out2.y)).assertTrue();
      expect(out2.x <= W).assertTrue();
    });

    // ---- 首尾页橡皮筋 / 时间基缓动 ----

    it('boundary_overscroll_starts_linear_and_saturates', 0, () => {
      expect(boundaryOverscroll(0, W)).assertEqual(0);
      const light = boundaryOverscroll(10, W);
      expect(light > 9).assertTrue();  // 起步接近 1:1 跟手
      expect(light < 10).assertTrue(); // 但已经开始变沉
      const heavy = boundaryOverscroll(300, W);
      expect(heavy > light).assertTrue();
      const cap = boundaryOverscroll(100000, W);
      expect(cap > BOUNDARY_MAX_RATIO * W * 0.999).assertTrue();
      expect(cap <= BOUNDARY_MAX_RATIO * W).assertTrue();
    });

    it('boundary_fold_folds_from_the_correct_edge', 0, () => {
      // 末页 forward：起手 1000，往左拖 200 → 折缝从 W 往左挪一点
      const fwd = boundaryFold(true, W, 1000, 800);
      expect(fwd < W).assertTrue();
      expect(fwd > W - BOUNDARY_MAX_RATIO * W).assertTrue();
      // 首页 backward：起手 0，往右拖 200 → 折缝从左缘往右挪一点
      const back = boundaryFold(false, W, 0, 200);
      expect(back > 0).assertTrue();
      expect(back < BOUNDARY_MAX_RATIO * W).assertTrue();
      // 反方向拖 / 没过起点：夹在页缘
      expect(boundaryFold(true, W, 1000, 1200)).assertEqual(W);
      expect(boundaryFold(false, W, 0, -200)).assertEqual(0);
    });

    it('easing_endpoints_and_monotonic', 0, () => {
      expect(easeOutCubic(0)).assertEqual(0);
      expect(easeOutCubic(1)).assertEqual(1);
      expect(easeInOutCubic(0)).assertEqual(0);
      expect(easeInOutCubic(0.5)).assertEqual(0.5);
      expect(easeInOutCubic(1)).assertEqual(1);
      let prev = 0;
      for (let i = 1; i <= 20; i++) {
        const v = easeOutCubic(i / 20);
        expect(v >= prev).assertTrue();
        prev = v;
      }
    });

    it('flip_duration_is_clamped_and_velocity_aware', 0, () => {
      const slow = flipDurationMs(W * 0.5, W, 0, true);
      const fast = flipDurationMs(W * 0.5, W, W * 3, true);
      expect(fast < slow).assertTrue();
      expect(slow >= 140).assertTrue();
      expect(slow <= 420).assertTrue();
      expect(flipDurationMs(0, W, 0, false) >= 140).assertTrue();
      expect(flipDurationMs(100000, W, 100000, true) <= 420).assertTrue();
    });
  });
}
