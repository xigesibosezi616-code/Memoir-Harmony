#!/usr/bin/env python3
"""给主题素材换色（平涂的图：图标、启动封面）。2026-10-17 做极夜时写的：肯特的图标、启动封面逐像素换成黑底配色。

图里只有几种颜色（图标就五种：底、线框、书签、内框、影子）。每个像素拆成「调色板里某两种颜色按 t 混合」，
再用新调色板按同样的 t 混回去 —— 边缘的抗锯齿原样保住，不会出锯齿和杂色。

依赖 ImageMagick（`magick` 命令）读写 PNG；输出不带透明通道（App 图标要求）。

用法：python3 Scripts/recolor_palette.py 输入.png 输出.png "#旧1=#新1" "#旧2=#新2" ...
例（极夜图标）：
    python3 Scripts/recolor_palette.py Memoir/Assets.xcassets/KentIcon.appiconset/kent-icon-1024.png polar-icon-1024.png \
        "#FFFFFF=#000000" "#1A1A1A=#AEAEB2" "#B4C7D8=#B4C7D8" "#8FA8BF=#8FA8BF" "#CBDAE6=#1F262E"
先用 `magick 图.png -format %c histogram:info:- | sort -rn | head` 看图里有哪几种颜色。
"""
import subprocess, sys, struct

src, dst, *pairs = sys.argv[1:]
def hexrgb(h):
    h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
old = [hexrgb(p.split("=")[0]) for p in pairs]
new = [hexrgb(p.split("=")[1]) for p in pairs]

size = subprocess.run(["magick", "identify", "-format", "%w %h", src], capture_output=True, text=True).stdout.split()
w, h = int(size[0]), int(size[1])
raw = subprocess.run(["magick", src, "-alpha", "off", "-depth", "8", "rgb:-"], capture_output=True).stdout
n = len(old)
pairs_idx = [(i, j) for i in range(n) for j in range(i + 1, n)]
pre = {}
for i, j in pairs_idx:
    d = tuple(old[i][k] - old[j][k] for k in range(3))
    pre[(i, j)] = (d, sum(x * x for x in d) or 1)

out = bytearray(len(raw))
cache = {}
for p in range(0, len(raw), 3):
    px = (raw[p], raw[p + 1], raw[p + 2])
    hit = cache.get(px)
    if hit is None:
        # 先看是不是正好某个颜色
        best = None
        for i, c in enumerate(old):
            e = sum((px[k] - c[k]) ** 2 for k in range(3))
            if best is None or e < best[0]:
                best = (e, i)
        if best[0] <= 12:
            hit = new[best[1]]
        else:
            # 两两混合里挑残差最小的
            winner = None
            for (i, j) in pairs_idx:
                d, dd = pre[(i, j)]
                t = sum((px[k] - old[j][k]) * d[k] for k in range(3)) / dd
                t = max(0.0, min(1.0, t))
                e = sum((px[k] - (old[j][k] + t * d[k])) ** 2 for k in range(3))
                if winner is None or e < winner[0]:
                    winner = (e, i, j, t)
            _, i, j, t = winner
            hit = tuple(int(round(new[j][k] + t * (new[i][k] - new[j][k]))) for k in range(3))
        cache[px] = hit
    out[p:p + 3] = bytes(hit)

subprocess.run(["magick", "-size", f"{w}x{h}", "-depth", "8", "rgb:-", "-define", "png:color-type=2", dst], input=bytes(out), check=True)
print("写好了", dst, f"{w}x{h}，{len(cache)} 种颜色")
