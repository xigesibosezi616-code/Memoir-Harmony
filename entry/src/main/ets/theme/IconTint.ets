/**
 * 单色 SVG 图标染色矩阵（10_BUILD_MANUAL.md 1.6）。
 *
 * 把任意不透明像素的 RGB 一律替换为目标色、alpha 原样保留（抗锯齿边缘平滑过渡）：
 * R' = 目标 R，G' = 目标 G，B' = 目标 B，A' = A（4×5 矩阵，行优先，值域 0~1）。
 * 配合 `Image` 的 `supportSvg2(true)` + `colorFilter(new ColorFilter(...))` 使用——
 * API 21 起 `colorFilter` 作用于整张 SVG（本工程 targetSdk 26）。
 *
 * 图标 SVG 进 media 前已把 `currentColor` 后处理成 `#000000`，矩阵输入确定。
 * 纯函数，单测覆盖（`IconTint.test.ets`）。
 */
export function tintMatrix(argb: number): number[] {
  const r: number = ((argb >> 16) & 0xFF) / 255;
  const g: number = ((argb >> 8) & 0xFF) / 255;
  const b: number = (argb & 0xFF) / 255;
  return [
    0, 0, 0, 0, r,
    0, 0, 0, 0, g,
    0, 0, 0, 0, b,
    0, 0, 0, 1, 0
  ];
}
