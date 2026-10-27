#!/usr/bin/env python3
"""出四套主题的 App 图标：纸色底 + 一笔手写「m.」（2026-10-24 产品定）。

- 字形照用户自己写的那张 m.（364×364 的小图）拟合出来：四段三次贝塞尔当中线（尖角处断开），
  沿中线盖圆，圆的半径按弧长插值 —— 就是一支圆头笔写出来的样子。坐标都在 364 的格子里，见 `STROKE`
- 笔画整体加粗到 1.35 倍（`WEIGHT`，用户在原粗细和加粗里挑了加粗）
- 颜色严格等于主题列表的两个色块（`ThemePickerView.swatch`）：底色 = 纸，第二个色 = 字
- 🔴 **平时不要一点玻璃**：图标是 Icon Composer 的分层文件（`.icon`），字那一层关掉玻璃、高光、投影。
  iOS 26 起老式单张 PNG 图标会被系统自动套玻璃，字色被冲灰、边发虚（2026-10-24 模拟器实测），所以不用 PNG。
  用户切到「清透」外观时，系统拿字的形状自己做透明玻璃，不带我们的颜色 —— 这正是要的
- iOS 18 用的静态图、深色 / 着色版都由 Xcode（actool）从 `.icon` 自动生成

产出：
- `Memoir/AppIcons/<名字>.icon`：`AppIcon`（素笺，主图标）、`LeatherIcon`、`KentIcon`、`PolarIcon`
- `Memoir/Assets.xcassets/AppIconPreview_<主题>.imageset/`：设置页里的 192px 预览（`AppIconOption.previewAsset`）

依赖 numpy 和 ImageMagick（`magick` 命令）。这台 Mac 上系统自带的 python3 没有 numpy，用 miniforge 的：
    ~/miniforge3/bin/python3 Scripts/make_app_icon.py                          重出四套图标和预览
    ~/miniforge3/bin/python3 Scripts/make_app_icon.py --export 4096 <文件.png>   出一张素笺主图标的大图（方形、不带圆角，宣传 / 素材用）
    ~/miniforge3/bin/python3 Scripts/make_app_icon.py --avatar 4096 <文件.png>   官方账号头像：字居中、四周留宽边（会被裁成圆）
"""
import json
import os
import shutil
import subprocess
import sys

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Memoir")
ICON_DIR = os.path.join(ROOT, "AppIcons")
ASSETS = os.path.join(ROOT, "Assets.xcassets")

# (图标名, 预览图名, 底色, 字色)。新主题：照 ThemePickerView 的两个色块加一行，
# 再按 AppIconOption 顶部的说明登记备用图标名
THEMES = [
    ("AppIcon", "AppIconPreview_Bamboo", "#FAF7F2", "#8B7E6A"),
    ("LeatherIcon", "AppIconPreview_Leather", "#1C1410", "#C8A87C"),
    ("KentIcon", "AppIconPreview_Kent", "#FFFFFF", "#1A1A1A"),
    ("PolarIcon", "AppIconPreview_Polar", "#000000", "#8FA8BF"),
]

GRID = 364          # 字形坐标的格子（用户原图的边长），出图时按比例放大
WEIGHT = 1.35
SIZE = 1024         # 字那一层的边长
SUPERSAMPLE = 2
PREVIEW = 192

# 中线：起笔 S → 第一个尖 K1 → 底下的折角 V → 第二个尖 K2 → 收笔的小勾 E；A/B 是每段的两个控制点
STROKE = {
    "pts": {
        "S": (66.25, 241.5), "A1": (89.25, 211.38), "B1": (136.0, 154.5), "K1": (174.62, 143.12),
        "A2": (175.31, 166.25), "B2": (161.25, 205.62), "V": (163.56, 221.62),
        "A3": (194.69, 195.25), "B3": (219.94, 161.25), "K2": (248.38, 151.75),
        "A4": (249.44, 202.19), "B4": (249.0, 219.5), "E": (257.19, 221.31),
    },
    # 节点处的半径，和每段中点的半径（段内按弧长线性插值）
    "r": {"S": 6.975, "K1": 8.934, "V": 10.55, "K2": 10.066, "E": 10.297},
    "rmid": (8.2, 10.091, 8.553, 10.288),
    "dot": (305.375, 228.75, 12.2),   # 句点：圆心 x, y, 半径
}
SEGMENTS = [("S", "A1", "B1", "K1"), ("K1", "A2", "B2", "V"), ("V", "A3", "B3", "K2"), ("K2", "A4", "B4", "E")]
KNOTS = ["S", "K1", "V", "K2", "E"]


def centerline(per_seg=320):
    """中线上一串圆：(圆心 Nx2, 半径 N)，单位是 GRID 格子"""
    P = {k: np.array(v, float) for k, v in STROKE["pts"].items()}
    centers, radii = [], []
    for i, (a, b, c, d) in enumerate(SEGMENTS):
        t = np.linspace(0, 1, per_seg)[:, None]
        pts = (1 - t) ** 3 * P[a] + 3 * (1 - t) ** 2 * t * P[b] + 3 * (1 - t) * t * t * P[c] + t ** 3 * P[d]
        u = np.r_[0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
        u /= u[-1]
        r0, rm, r1 = STROKE["r"][KNOTS[i]], STROKE["rmid"][i], STROKE["r"][KNOTS[i + 1]]
        rr = np.where(u < 0.5, r0 + (rm - r0) * u / 0.5, rm + (r1 - rm) * (u - 0.5) / 0.5)
        centers.append(pts); radii.append(rr)
    return np.concatenate(centers), np.concatenate(radii) * WEIGHT


def coverage(size=SIZE, supersample=SUPERSAMPLE, fit_width=None):
    """字的覆盖率（0…1），size×size：先在 supersample 倍上按到每个圆的距离算抗锯齿，再缩回来。
    fit_width 为 None 时照图标的构图（字在 GRID 格子里的原位）；给了比例就把整个字（含句点）挪到正中、宽度占画面这么多"""
    n = size * supersample
    C, R = centerline()
    dx, dy, dr = STROKE["dot"]
    circles = list(zip(C, R)) + [(np.array([dx, dy]), dr * WEIGHT)]
    if fit_width is None:
        k, shift = n / GRID, np.zeros(2)
    else:
        lo = np.min([c - r for c, r in circles], axis=0)
        hi = np.max([c + r for c, r in circles], axis=0)
        k = fit_width * n / (hi[0] - lo[0])
        shift = n / 2 - (lo + hi) / 2 * k
    circles = [(c * k + shift, r * k) for c, r in circles]
    field = np.full((n, n), -1e4, np.float32)
    for (cx, cy), rr in circles:
        x0, x1 = int(max(0, cx - rr - 3)), int(min(n, cx + rr + 4))
        y0, y1 = int(max(0, cy - rr - 3)), int(min(n, cy + rr + 4))
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        d = rr - np.sqrt((xx + 0.5 - cx) ** 2 + (yy + 0.5 - cy) ** 2)
        np.maximum(field[y0:y1, x0:x1], d, out=field[y0:y1, x0:x1])
    cov = np.clip(field + 0.5, 0, 1)
    return cov.reshape(size, supersample, size, supersample).mean(axis=(1, 3))


def rgb(hex_color):
    h = hex_color.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def write_png(path, pixels, size=None):
    """pixels: (h, w, 3 或 4)，0…1。经 ImageMagick 存 8 位 PNG，可顺手缩到 size"""
    h, w, c = pixels.shape
    raw = (np.clip(pixels, 0, 1) * 65535 + 0.5).astype(">u2").tobytes()
    args = ["magick", "-size", f"{w}x{h}", "-endian", "MSB", "-depth", "16", ("rgba:-" if c == 4 else "rgb:-")]
    if size:
        args += ["-filter", "Lanczos", "-resize", f"{size}x{size}"]
    args += ["-depth", "8", "-define", "png:color-type=" + ("6" if c == 4 else "2"), "-strip", path]
    subprocess.run(args, input=raw, check=True)


def srgb_token(hex_color):
    r, g, b = rgb(hex_color)
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def write_icon(name, background, ink, alpha):
    icon = os.path.join(ICON_DIR, f"{name}.icon")
    shutil.rmtree(icon, ignore_errors=True)
    os.makedirs(os.path.join(icon, "Assets"))
    layer = np.dstack([np.broadcast_to(rgb(ink), alpha.shape + (3,)), alpha])
    write_png(os.path.join(icon, "Assets", "m.png"), layer)
    doc = {
        "fill": {"solid": srgb_token(background)},
        "groups": [{
            "layers": [{"glass": False, "image-name": "m.png", "name": "m"}],
            "shadow": {"kind": "none", "opacity": 0},
            "specular": False,
            "translucency": {"enabled": False, "value": 0.5},
        }],
        "supported-platforms": {"squares": ["iOS"]},
    }
    with open(os.path.join(icon, "icon.json"), "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")


def write_preview(name, background, ink, alpha):
    a = alpha[..., None]
    flat = rgb(background) * (1 - a) + rgb(ink) * a
    folder = os.path.join(ASSETS, f"{name}.imageset")
    for old in os.listdir(folder):
        if old != "Contents.json":
            os.remove(os.path.join(folder, old))
    write_png(os.path.join(folder, f"{name}.png"), flat, size=PREVIEW)
    contents = {
        "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"},
                   {"idiom": "universal", "scale": "2x"},
                   {"idiom": "universal", "scale": "3x"}],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")


def export_flat(size, path):
    """素笺主图标的大图：底色 + 字合成好的方图（不带圆角 —— 圆角由系统 / 用的地方自己加）"""
    _, _, background, ink = THEMES[0]
    a = coverage(size, supersample=1)[..., None]   # 大图上按距离算的抗锯齿已经够细，不用再超采样
    write_png(path, rgb(background) * (1 - a) + rgb(ink) * a)
    print(f"{path}  {size}×{size}  底 {background}  字 {ink}")


def export_avatar(size, path, fit_width=0.6):
    """官方账号头像：字挪到正中、宽度占六成 —— 各平台会把头像裁成圆，四周得留够边（2026-10-24 用户要）"""
    _, _, background, ink = THEMES[0]
    a = coverage(size, supersample=1, fit_width=fit_width)[..., None]
    write_png(path, rgb(background) * (1 - a) + rgb(ink) * a)
    print(f"{path}  {size}×{size}  字宽占 {fit_width:.0%}，居中")


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--export":
        export_flat(int(sys.argv[2]), sys.argv[3])
        return
    if len(sys.argv) == 4 and sys.argv[1] == "--avatar":
        export_avatar(int(sys.argv[2]), sys.argv[3])
        return
    alpha = coverage()
    os.makedirs(ICON_DIR, exist_ok=True)
    for name, preview, background, ink in THEMES:
        write_icon(name, background, ink, alpha)
        write_preview(preview, background, ink, alpha)
        print(f"{name}.icon / {preview}  底 {background}  字 {ink}")


if __name__ == "__main__":
    main()
