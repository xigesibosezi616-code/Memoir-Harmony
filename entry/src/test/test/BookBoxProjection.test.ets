/**
 * 书的立体投影纯数学单测（10_BUILD_MANUAL.md 3.2）。对应 iOS
 * `Shelf/BookBoxProjection.swift`。覆盖：静止恒等（拿起那一下不「跳」）、
 * 封面 / 书脊交界在任意转角下对齐、书脊静止时侧立不可见、拿起方向朝露出
 * 书脊的一侧、转过头封面隐藏。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  BOOK_BOX_EYE_DISTANCE,
  BookBoxFace,
  bookBoxFaceMatrix,
  bookBoxFaceVisible,
  bookBoxLiftAngle,
  bookBoxProjectPoint
} from '../../main/ets/models/BookBoxProjection';

export default function bookBoxProjectionTest() {
  describe('BookBoxProjectionTest', () => {
    const COVER_W = 100;
    const COVER_H = 137; // ≈ 100 / 0.73
    const DEPTH = 14;

    it('eyeDistanceMatchesIos', 0, () => {
      expect(BOOK_BOX_EYE_DISTANCE).assertEqual(520);
    })

    it('coverMatrixIsIdentityAtRest', 0, () => {
      // 不转的时候投影出来和平面的书一模一样（拿起那一下不会「跳」）。
      // 面视图是平面（输入 z 恒 0），所以断言的是对平面输入的完整行为：
      // x′/y′ 行 = 恒等（无缩放 / 剪切 / 平移），w′ 行不依赖 x/y 且基值 1，
      // z′ 行清零（交给 ArkUI 的矩阵不出 bogus 深度，角点 z 不再偏到 −27）。
      const m = bookBoxFaceMatrix(BookBoxFace.Cover, 0, COVER_W, COVER_H, DEPTH);
      expect(m.length).assertEqual(16);
      expect(m[0]).assertClose(1, 0.0001);
      expect(m[1]).assertClose(0, 0.0001);
      expect(m[2]).assertClose(0, 0.0001);
      expect(m[3]).assertClose(0, 0.0001);
      expect(m[4]).assertClose(0, 0.0001);
      expect(m[5]).assertClose(1, 0.0001);
      expect(m[6]).assertClose(0, 0.0001);
      expect(m[7]).assertClose(0, 0.0001);
      expect(m[8]).assertClose(0, 0.0001);
      expect(m[9]).assertClose(0, 0.0001);
      expect(m[10]).assertClose(1, 0.0001);
      expect(m[11]).assertClose(0, 0.0001);
      expect(m[12]).assertClose(0, 0.0001);
      expect(m[13]).assertClose(0, 0.0001);
      expect(m[14]).assertClose(0, 0.0001);
      expect(m[15]).assertClose(1, 0.0001);
    })

    it('coverCornersStayPutAtRest', 0, () => {
      const m = bookBoxFaceMatrix(BookBoxFace.Cover, 0, COVER_W, COVER_H, DEPTH);
      const topLeft = bookBoxProjectPoint(m, 0, 0, 0);
      expect(topLeft[0]).assertClose(0, 0.0001);
      expect(topLeft[1]).assertClose(0, 0.0001);
      const bottomRight = bookBoxProjectPoint(m, COVER_W, COVER_H, 0);
      expect(bottomRight[0]).assertClose(COVER_W, 0.0001);
      expect(bottomRight[1]).assertClose(COVER_H, 0.0001);
    })

    it('spineHiddenAtRestCoverVisible', 0, () => {
      expect(bookBoxFaceVisible(BookBoxFace.Spine, 0)).assertFalse();
      expect(bookBoxFaceVisible(BookBoxFace.Cover, 0)).assertTrue();
    })

    it('spineNearlyCollapsesEdgeOnAtRest', 0, () => {
      // 静止时书脊侧立、不可见。针孔相机在盒子中心轴上，书脊平面相对相机轴
      // 偏了 −cw/2，所以背面那条边投影不在缝上，而是被透视拉近了一点：
      // 缝 = 书脊视图的右缘（x = depth，挨着封面左缘那条）投影严格 x = 0；
      // 后缘（视图 x = 0）投影 x = cw·d / (2·(e+d)) ≈ 1.31vp —— 一条细缝，
      // 视觉上塌成线，而且面本身这时是隐藏的（上面的可见性测试）。
      const m = bookBoxFaceMatrix(BookBoxFace.Spine, 0, COVER_W, COVER_H, DEPTH);
      const seam = bookBoxProjectPoint(m, DEPTH, 0, 0);
      expect(Math.abs(seam[0])).assertLess(0.0001);
      const back = bookBoxProjectPoint(m, 0, 0, 0);
      const expected = COVER_W * DEPTH / (2 * (BOOK_BOX_EYE_DISTANCE + DEPTH));
      expect(back[0]).assertClose(expected, 0.0001);
      expect(expected).assertLess(2);
    })

    it('liftAngleTurnsTowardVisibleSpine', 0, () => {
      const lift = bookBoxLiftAngle(32);
      expect(Math.abs(lift)).assertClose(32 * Math.PI / 180, 0.0001);
      // 拿起方向上书脊可见、封面也可见
      expect(bookBoxFaceVisible(BookBoxFace.Spine, lift)).assertTrue();
      expect(bookBoxFaceVisible(BookBoxFace.Cover, lift)).assertTrue();
      // 反方向书脊转背过去（负角度隐藏 → liftAngle 不会选它）
      expect(bookBoxFaceVisible(BookBoxFace.Spine, -lift)).assertFalse();
    })

    it('spineAndCoverShareSeamWhileLifted', 0, () => {
      // 交界对齐：封面的左边缘和书脊的右边缘是同一个物理边，
      // 任意转角下投影必须重合，不然面会「裂缝」
      const angle = bookBoxLiftAngle(32);
      const cover = bookBoxFaceMatrix(BookBoxFace.Cover, angle, COVER_W, COVER_H, DEPTH);
      const spine = bookBoxFaceMatrix(BookBoxFace.Spine, angle, COVER_W, COVER_H, DEPTH);
      // 顶角：封面 (0,0) vs 书脊 (DEPTH, 0)
      const coverTop = bookBoxProjectPoint(cover, 0, 0, 0);
      const spineTop = bookBoxProjectPoint(spine, DEPTH, 0, 0);
      expect(spineTop[0]).assertClose(coverTop[0], 0.01);
      expect(spineTop[1]).assertClose(coverTop[1], 0.01);
      // 底角：封面 (0, COVER_H) vs 书脊 (DEPTH, COVER_H)
      const coverBottom = bookBoxProjectPoint(cover, 0, COVER_H, 0);
      const spineBottom = bookBoxProjectPoint(spine, DEPTH, COVER_H, 0);
      expect(spineBottom[0]).assertClose(coverBottom[0], 0.01);
      expect(spineBottom[1]).assertClose(coverBottom[1], 0.01);
    })

    it('seamStaysAlignedMidTurn', 0, () => {
      // 转到一半（16°）交界也要对齐 —— 转动全程都不能裂缝
      const half = bookBoxLiftAngle(16);
      const cover = bookBoxFaceMatrix(BookBoxFace.Cover, half, COVER_W, COVER_H, DEPTH);
      const spine = bookBoxFaceMatrix(BookBoxFace.Spine, half, COVER_W, COVER_H, DEPTH);
      const coverTop = bookBoxProjectPoint(cover, 0, 0, 0);
      const spineTop = bookBoxProjectPoint(spine, DEPTH, 0, 0);
      expect(spineTop[0]).assertClose(coverTop[0], 0.01);
      expect(spineTop[1]).assertClose(coverTop[1], 0.01);
    })

    it('coverHiddenWhenTurnedAway', 0, () => {
      expect(bookBoxFaceVisible(BookBoxFace.Cover, Math.PI)).assertFalse();
      expect(bookBoxFaceVisible(BookBoxFace.Cover, Math.PI / 2)).assertFalse();
    })

    it('perspectiveMakesNearEdgeLarger', 0, () => {
      // 转过去时朝向观看者的那一边应该被透视放大（w < 1），不是等距投影
      const angle = bookBoxLiftAngle(32);
      const m = bookBoxFaceMatrix(BookBoxFace.Cover, angle, COVER_W, COVER_H, DEPTH);
      const backEdge = bookBoxProjectPoint(m, COVER_W, 0, 0);  // 转动时背离观看者的边
      const nearEdge = bookBoxProjectPoint(m, 0, 0, 0);        // 转动时朝向观看者的边
      // 静止时两点相距 COVER_W；转 32° 后投影距离应小于它（面斜过去了），
      // 又要略大于等距投影的 COVER_W·cos(32°)（透视把近边放大了）
      const projectedWidth = Math.abs(backEdge[0] - nearEdge[0]);
      expect(projectedWidth).assertLess(COVER_W);
      expect(projectedWidth).assertLarger(COVER_W * Math.cos(32 * Math.PI / 180) - 0.5);
    })
  })
}
