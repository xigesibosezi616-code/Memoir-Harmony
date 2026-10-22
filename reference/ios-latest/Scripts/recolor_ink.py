#!/usr/bin/env python3
"""给手绘插画换色（邮筒这种墨线有浓有淡、带排线的图）。2026-10-17 做极夜时写的：肯特的邮筒换成黑底浅灰线条。

每个像素看成「纸 + 墨 + 一种彩色」按比例混合（最小二乘求三者的份量），再用新的三种颜色按同样份量混回去 ——
浓淡、排线都保住；投信口那抹彩色保持原色。

依赖 ImageMagick（`magick` 命令）。

用法：python3 Scripts/recolor_ink.py 输入.png 输出.png "#纸旧=#纸新" "#墨旧=#墨新" "#彩旧=#彩新"
例（极夜邮筒）：
    python3 Scripts/recolor_ink.py Memoir/Assets.xcassets/Mailbox_Kent.imageset/mailbox-kent.png mailbox-polar.png \
        "#FFFFFF=#000000" "#1A1A1A=#BDBDC2" "#8FA8BF=#8FA8BF"
"""
import subprocess, sys

src, dst, *pairs = sys.argv[1:]
def hexrgb(h):
    h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
(W, W2), (K, K2), (B, B2) = [(hexrgb(p.split("=")[0]), hexrgb(p.split("=")[1])) for p in pairs]

w, h = map(int, subprocess.run(["magick", "identify", "-format", "%w %h", src], capture_output=True, text=True).stdout.split())
raw = subprocess.run(["magick", src, "-alpha", "off", "-depth", "8", "rgb:-"], capture_output=True).stdout

u = [W[i] - K[i] for i in range(3)]   # 纸 - 墨
v = [B[i] - K[i] for i in range(3)]   # 彩 - 墨
uu = sum(x * x for x in u); vv = sum(x * x for x in v); uv = sum(u[i] * v[i] for i in range(3))
det = uu * vv - uv * uv

cache = {}
out = bytearray(len(raw))
for p in range(0, len(raw), 3):
    px = (raw[p], raw[p + 1], raw[p + 2])
    hit = cache.get(px)
    if hit is None:
        d = [px[i] - K[i] for i in range(3)]
        du = sum(d[i] * u[i] for i in range(3)); dv = sum(d[i] * v[i] for i in range(3))
        a = (du * vv - dv * uv) / det      # 纸的份量
        b = (dv * uu - du * uv) / det      # 彩色的份量
        a = max(0.0, min(1.0, a)); b = max(0.0, min(1.0 - a, b))
        k = 1.0 - a - b
        hit = tuple(int(round(max(0, min(255, W2[i] * a + B2[i] * b + K2[i] * k)))) for i in range(3))
        cache[px] = hit
    out[p:p + 3] = bytes(hit)

subprocess.run(["magick", "-size", f"{w}x{h}", "-depth", "8", "rgb:-", "-define", "png:color-type=2", dst], input=bytes(out), check=True)
print("写好了", dst, f"{w}x{h}，{len(cache)} 种颜色")
