#!/usr/bin/env python3
"""把邮筒的手绘图拆成两层，给「转得动的邮筒」用（2026-10-20 产品定：邮筒做成 3D，左右拨得转）。

- 筒身层 `Mailbox_<主题>_Body`：原图里会转的部件（投信口、铭牌、筒身上的 m.、小门、帽檐那圈铆钉）抹成纸色，
  剩下轮廓、明暗排线、帽顶、领圈、底座 —— 这些绕竖轴转一圈样子不变，不用动
- 部件层 `Mailbox_<主题>_Parts`：只有那几个部件，透明底。每个像素看成「纸 + 墨 + 一种彩色」按比例混合
  （同 `recolor_ink.py`），墨和彩色的份量就是不透明度 —— 部件转到筒身边上时，底下的排线还透得出来
  铆钉只留正中那一颗（x≈361）当样子，转的时候在着色器里按 20 颗等分绕一圈画（`MailboxSurface.metal`）

四个主题的邮筒是同一张线稿换色，部件的框共用一套。纸、墨、彩色三种颜色每个主题各自从图上取：
纸 = 左上角；墨 = 左轮廓里离纸最远的颜色；彩色 = 投信口里离「纸—墨」那条线最远的颜色。

依赖 ImageMagick（`magick` 命令），只用标准库。

用法：python3 Scripts/make_mailbox_layers.py
"""
import math
import os
import subprocess

ROOT = os.path.join(os.path.dirname(__file__), "..", "Memoir", "Assets.xcassets")
# 新主题：邮筒图放进 `Mailbox_<主题>.imageset` 之后把名字加在这里重跑（不拆也能用，只是邮筒转不动）
THEMES = ["Bamboo", "Leather", "Kent", "Polar"]
W, H = 678, 1498

# 会转的部件在原图上的框：(x0, y0, x1, y1)，含端点。要改就和 MailboxSurface.metal 的几何常数一起看
BOXES = {
    "slot": (182, 254, 500, 352),
    "plate": (204, 421, 477, 657),
    # 2026-10-27 起筒身中间是尺素的 m.（原来是 Sinara 的标志 + 字样两个框，合成这一个；m. 由 make_mailbox_mark.py 写进原图）
    "mark": (212, 694, 469, 886),
    # 下沿不能过 1268：再往下就是底座最上面那圈线
    "door": (178, 942, 506, 1268),
}
# 帽檐那圈铆钉：(圆心 x, 圆心 y)。帽檐是一圈往两边垂下去的弧，两边的铆钉更低
RIVETS = [(137.5, 193.5), (209.5, 186.0), (283.0, 181.5), (361.0, 181.5), (437.0, 183.5), (513.0, 190.0), (565.0, 196.0)]
RIVET_HALF = (14, 15)
# 留在部件层里当样子的那一颗（离正中最近，几乎没有透视压缩）
SAMPLE_RIVET = (361.0, 181.5)


def rivet_box(cx, cy):
    hx, hy = RIVET_HALF
    return (int(cx - hx), int(cy - hy), int(math.ceil(cx + hx)), int(math.ceil(cy + hy)))


def inside(box, x, y):
    x0, y0, x1, y1 = box
    return x0 <= x <= x1 and y0 <= y <= y1


def read_rgb(path):
    raw = subprocess.run(["magick", path, "-alpha", "off", "-depth", "8", "rgb:-"],
                         capture_output=True, check=True).stdout
    assert len(raw) == W * H * 3, path
    return raw


def write(path, data, channels):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fmt = "rgba" if channels == 4 else "rgb"
    subprocess.run(["magick", "-size", f"{W}x{H}", "-depth", "8", f"{fmt}:-", "-strip", path],
                   input=bytes(data), check=True)


def imageset(folder, filename):
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        f.write('{\n  "images" : [\n    {\n      "filename" : "%s",\n      "idiom" : "universal"\n    }\n  ],\n'
                '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' % filename)


def px(raw, x, y):
    i = (y * W + x) * 3
    return raw[i], raw[i + 1], raw[i + 2]


def palette(raw):
    paper = px(raw, 0, 0)
    dist = lambda c, d: sum((c[i] - d[i]) ** 2 for i in range(3))
    # 墨：左轮廓（x 112–132）里离纸最远的颜色
    ink = max((px(raw, x, y) for y in range(500, 900, 3) for x in range(112, 133)), key=lambda c: dist(c, paper))

    # 彩色：投信口里离「纸—墨」那条线最远的颜色
    u = [paper[i] - ink[i] for i in range(3)]
    uu = sum(t * t for t in u)

    def off_line(c):
        d = [c[i] - ink[i] for i in range(3)]
        k = sum(d[i] * u[i] for i in range(3)) / uu
        return sum((d[i] - k * u[i]) ** 2 for i in range(3))

    x0, y0, x1, y1 = BOXES["slot"]
    accent = max((px(raw, x, y) for y in range(y0, y1, 2) for x in range(x0, x1, 2)), key=off_line)
    return paper, ink, accent


def decompose(paper, ink, accent):
    """返回 c → (不透明度, 墨和彩色混出来的颜色)。同 recolor_ink.py 的最小二乘"""
    u = [paper[i] - ink[i] for i in range(3)]
    v = [accent[i] - ink[i] for i in range(3)]
    uu = sum(t * t for t in u); vv = sum(t * t for t in v); uv = sum(u[i] * v[i] for i in range(3))
    det = uu * vv - uv * uv
    cache = {}

    def run(c):
        hit = cache.get(c)
        if hit is not None:
            return hit
        d = [c[i] - ink[i] for i in range(3)]
        du = sum(d[i] * u[i] for i in range(3)); dv = sum(d[i] * v[i] for i in range(3))
        a = (du * vv - dv * uv) / det     # 纸的份量
        b = (dv * uu - du * uv) / det     # 彩色的份量
        a = max(0.0, min(1.0, a)); b = max(0.0, min(1.0 - a, b))
        k = 1.0 - a - b                   # 墨的份量
        alpha = k + b
        if alpha < 0.02:
            hit = (0, (0, 0, 0))
        else:
            hit = (round(alpha * 255), tuple(round((k * ink[i] + b * accent[i]) / alpha) for i in range(3)))
        cache[c] = hit
        return hit

    return run


def main():
    rivet_boxes = [rivet_box(*r) for r in RIVETS]
    sample_box = rivet_box(*SAMPLE_RIVET)
    part_boxes = list(BOXES.values()) + [sample_box]
    erase_boxes = list(BOXES.values()) + rivet_boxes

    for theme in THEMES:
        src = os.path.join(ROOT, f"Mailbox_{theme}.imageset", f"mailbox-{theme.lower()}.png")
        raw = read_rgb(src)
        paper, ink, accent = palette(raw)
        split = decompose(paper, ink, accent)
        print(f"{theme}: 纸 {paper} 墨 {ink} 彩 {accent}")

        body = bytearray(raw)
        parts = bytearray(W * H * 4)
        for y in range(H):
            for x in range(W):
                if any(inside(b, x, y) for b in erase_boxes):
                    i = (y * W + x) * 3
                    body[i:i + 3] = bytes(paper)
                if any(inside(b, x, y) for b in part_boxes):
                    alpha, color = split(px(raw, x, y))
                    if alpha:
                        j = (y * W + x) * 4
                        parts[j:j + 4] = bytes((*color, alpha))

        name = theme.lower()
        body_dir = os.path.join(ROOT, f"Mailbox_{theme}_Body.imageset")
        parts_dir = os.path.join(ROOT, f"Mailbox_{theme}_Parts.imageset")
        imageset(body_dir, f"mailbox-{name}-body.png")
        imageset(parts_dir, f"mailbox-{name}-parts.png")
        write(os.path.join(body_dir, f"mailbox-{name}-body.png"), body, 3)
        write(os.path.join(parts_dir, f"mailbox-{name}-parts.png"), parts, 4)
        print(f"  写好了 Mailbox_{theme}_Body / Mailbox_{theme}_Parts")


if __name__ == "__main__":
    main()
