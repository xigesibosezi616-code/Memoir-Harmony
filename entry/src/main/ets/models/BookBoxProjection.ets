/**
 * 把拿起的书当成一个**有厚度的长方体**，算出封面、书脊各自的 3D 投影 ——
 * iOS `Shelf/BookBoxProjection.swift`（`BookBox`）的移植。
 *
 * **为什么不直接用 ArkUI 的 rotate3d 一把转**：那只能把一张平面转个角度，
 * 书转过去时看不到厚度，像一张卡片。要看到书脊，书脊得是另一个面，而且必须和
 * 封面绕**同一根轴**转、用**同一个透视**，两个面的交界才对得上。所以这里自己
 * 拼矩阵，所有面共用一套几何。
 *
 * 坐标约定与 CATransform3D 一致：行向量 p' = p·M（平移在末行），x 向右、
 * y 向下、z 朝向观看者；盒子中心在原点。所有面放在同一个左上对齐的容器里：
 * 封面视图 = 整本书的尺寸（含书口），书脊视图 = 厚度 × 书高，都锚在容器左上角。
 *
 * 纯数学，不依赖 ArkUI —— 单测覆盖（静止恒等、交界对齐、可见性、拿起方向）。
 * 视图侧（`ShelfBook3DView`）把这里的行主序 16 数喂给 `matrix4.init`：
 * 它按列主序读 = 行向量矩阵的转置 = 列向量约定，正好接上（见该文件）。
 */

/** 视点到封面的距离（vp）。越小透视越强；520 对手机上一本书比较克制（iOS 同款） */
export const BOOK_BOX_EYE_DISTANCE: number = 520;

/** 盒子的面：封面 / 书脊（封面左边那一面） */
export enum BookBoxFace {
  Cover = 0,
  Spine = 1
}

// ---- 4x4 矩阵（行向量约定，行主序 number[][]） ----

function matMultiply(a: number[][], b: number[][]): number[][] {
  const out: number[][] = [];
  for (let r = 0; r < 4; r++) {
    const row: number[] = [];
    for (let c = 0; c < 4; c++) {
      row.push(a[r][0] * b[0][c] + a[r][1] * b[1][c] + a[r][2] * b[2][c] + a[r][3] * b[3][c]);
    }
    out.push(row);
  }
  return out;
}

function matTranslate(x: number, y: number, z: number): number[][] {
  return [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [x, y, z, 1]];
}

/** 绕 y 轴转（行向量）：x′ = x·cos − z·sin，z′ = x·sin + z·cos。
 *  转向选成：正角度把 z>0（朝观看者）的部分转向 +x —— 书转起来书脊落在书的
 *  左侧（iOS 同款：封面朝人时书脊在左）。spineFaceAngle / bookBoxLiftAngle
 *  都直接读这颗矩阵判断方向，不依赖这里的符号约定。 */
function matRotateY(rad: number): number[][] {
  const cos = Math.cos(rad);
  const sin = Math.sin(rad);
  return [[cos, 0, sin, 0], [0, 1, 0, 0], [-sin, 0, cos, 0], [0, 0, 0, 1]];
}

/** 透视：w' = 1 − z / eyeDistance（CATransform3D 的 m34 = −1/d） */
function matPerspective(eyeDistance: number): number[][] {
  return [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, -1 / eyeDistance], [0, 0, 0, 1]];
}

/**
 * 书脊这一面在盒子上的朝向：法线要指向左边（−x）。
 * 不靠记正负号约定：两个候选里挑转完法线 x 分量为负的那个（iOS 同款做法）。
 */
function spineFaceAngle(): number {
  // 法线 (0,0,1) 转 π/2 后的 x 分量 = 第 3 列 (0, sin, 0) 的 z 贡献 → 矩阵 [2][0]
  return matRotateY(Math.PI / 2)[2][0] < 0 ? Math.PI / 2 : -Math.PI / 2;
}

/** 这个面此刻是否朝向观看者（背过去的面不画）。法线 (0,0,1) 转过去后 z 分量 > 0.01 */
export function bookBoxFaceVisible(face: BookBoxFace, angle: number): boolean {
  const faceAngle = face === BookBoxFace.Cover ? 0 : spineFaceAngle();
  const r = matMultiply(matRotateY(faceAngle), matRotateY(angle));
  return r[2][2] > 0.01;
}

/**
 * 某个面要用的投影，行主序平铺成 16 个数（行向量；喂给 `matrix4.init` 前别转置）。
 *
 * - face: 哪个面
 * - angle: 整本书绕竖轴转的角度（弧度），0 = 正面
 * - coverWidth / coverHeight: 封面（盒子正面，不含书口）的宽高
 * - depth: 书的厚度
 */
export function bookBoxFaceMatrix(face: BookBoxFace, angle: number,
  coverWidth: number, coverHeight: number, depth: number): number[] {
  const faceAngle = face === BookBoxFace.Cover ? 0 : spineFaceAngle();
  const offsetX = face === BookBoxFace.Cover ? 0 : -coverWidth / 2;
  const offsetZ = face === BookBoxFace.Cover ? depth / 2 : 0;
  const faceCenterX = face === BookBoxFace.Cover ? coverWidth / 2 : depth / 2;
  const boxCenterX = coverWidth / 2;
  const boxCenterY = coverHeight / 2;

  // 面视图 → 以它自己的中心为原点 → 转到它在盒子上的朝向、放到它在盒子上的位置
  let t = matTranslate(-faceCenterX, -boxCenterY, 0);
  t = matMultiply(t, matRotateY(faceAngle));
  t = matMultiply(t, matTranslate(offsetX, 0, offsetZ));
  // 整本书绕中心竖轴转
  t = matMultiply(t, matRotateY(angle));
  // 把封面所在的平面挪回 z = 0：不转的时候投影出来和平面的书一样大，拿起那一下不会「跳」
  t = matMultiply(t, matTranslate(0, 0, -depth / 2));
  t = matMultiply(t, matPerspective(BOOK_BOX_EYE_DISTANCE));
  // 盒子中心放回面视图里该在的位置（两个面里是同一个点）
  t = matMultiply(t, matTranslate(boxCenterX, boxCenterY, 0));
  // z′ 行清零：投影只消费 x′/y′/w′，但整颗矩阵会交给 ArkUI —— 透视平移会在
  // z′ 行留下正比于 x/y 的垃圾深度（静息角点能到 −27），命中测试 / 深度排序
  // 都可能被带偏。清零后静止时矩阵对平面输入（z 恒 0）严格等於恒等。
  t[2] = [0, 0, 1, 0];
  return flattenRowMajor(t);
}

function flattenRowMajor(m: number[][]): number[] {
  const out: number[] = [];
  for (let r = 0; r < 4; r++) {
    for (let c = 0; c < 4; c++) {
      out.push(m[r][c]);
    }
  }
  return out;
}

/**
 * 拿起时转到的角度（弧度）：朝露出书脊的那个方向转 `degrees` 度（iOS `liftAngle`）。
 * 方向不靠记正负号约定，直接用可见性判断挑 —— 哪个方向能看见书脊，就往哪个方向转。
 */
export function bookBoxLiftAngle(degrees: number): number {
  const radians = degrees * Math.PI / 180;
  return bookBoxFaceVisible(BookBoxFace.Spine, radians) ? radians : -radians;
}

/** 投影一个点（主要给单测用）：行主序 16 矩阵作用在 (x, y, z, 1) 上再除以 w */
export function bookBoxProjectPoint(matrix: number[], x: number, y: number,
  z: number): number[] {
  const nx = x * matrix[0] + y * matrix[4] + z * matrix[8] + matrix[12];
  const ny = x * matrix[1] + y * matrix[5] + z * matrix[9] + matrix[13];
  const nw = x * matrix[3] + y * matrix[7] + z * matrix[11] + matrix[15];
  return [nx / nw, ny / nw];
}
