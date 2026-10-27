#!/usr/bin/env python3
"""把邮筒筒身中间的「Sinara」标志和字样换成尺素的手写「m.」（2026-10-27 产品定：简洁明了）。

- 改的是四张邮筒原图 `Mailbox_<主题>.imageset/mailbox-<主题>.png`：标志和字样那一块（`make_mailbox_layers.BOXES["mark"]`）
  先抹成纸色，再用桌面图标同一份 m. 字形（`make_app_icon.coverage`）按这张图的墨色写上去
- 那一块周围本来就是素纸（排线在两边更远的地方），抹掉不伤别的
- 跑完要再跑一次拆层，m. 才会跟着邮筒一起转：
      ~/miniforge3/bin/python3 Scripts/make_mailbox_mark.py
      python3 Scripts/make_mailbox_layers.py
- 重跑没关系：同一块先抹成纸色再写同一个 m.，结果一样

依赖 numpy 和 ImageMagick（同 make_app_icon.py，用 miniforge 的 python3）。
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_app_icon as icon  # noqa: E402
import make_mailbox_layers as layers  # noqa: E402

# m. 写多宽（原图像素，含句点）、写在哪：筒身中线（着色器的 kBodyX = 339），铭牌下沿和小门上沿之间偏上一点
MARK_WIDTH = 168
CENTER = (339, 792)
# 先在多大的方块里写（比字大一圈，抗锯齿用 4 倍超采样）
CANVAS = 256


def main():
    x0, y0, x1, y1 = layers.BOXES["mark"]
    cov = icon.coverage(CANVAS, supersample=4, fit_width=MARK_WIDTH / CANVAS)
    ox, oy = CENTER[0] - CANVAS // 2, CENTER[1] - CANVAS // 2
    # 字必须整个落在 mark 框里：框外的部分不会进部件层，转起来会留在原地
    ys, xs = np.nonzero(cov > 0.002)
    assert ys.size, "字是空的"
    assert x0 <= ox + xs.min() and ox + xs.max() <= x1 and y0 <= oy + ys.min() and oy + ys.max() <= y1, \
        f"m. 出了 mark 框：x {ox + xs.min()}–{ox + xs.max()}，y {oy + ys.min()}–{oy + ys.max()}"

    for theme in layers.THEMES:
        src = os.path.join(layers.ROOT, f"Mailbox_{theme}.imageset", f"mailbox-{theme.lower()}.png")
        raw = layers.read_rgb(src)
        paper, ink, _ = layers.palette(raw)
        img = np.frombuffer(raw, np.uint8).reshape(layers.H, layers.W, 3).astype(np.float64) / 255
        paper_c = np.array(paper) / 255
        ink_c = np.array(ink) / 255

        img[y0:y1 + 1, x0:x1 + 1] = paper_c
        a = cov[..., None]
        region = img[oy:oy + CANVAS, ox:ox + CANVAS]
        img[oy:oy + CANVAS, ox:ox + CANVAS] = region * (1 - a) + ink_c * a

        icon.write_png(src, img)
        print(f"Mailbox_{theme}：纸 {paper}  墨 {ink}  m. 宽 {MARK_WIDTH}px，中心 {CENTER}")


if __name__ == "__main__":
    main()
