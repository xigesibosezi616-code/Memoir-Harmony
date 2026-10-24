#!/usr/bin/env python3
"""生成开场写字的声音 splash_write.wav（2026-10-24）：笔尖在纸上「刷刷刷」写出 m，落句点「咚」。

开场（`SplashView`）在封面中间一笔写出桌面图标上那个手写的「m.」。声音和画面是**同一张时间表**：
`HandwrittenMark.Script`（Swift）里每一段写多久、段内怎么快慢、抬笔多久、何时落点，这里一个不差地照抄。
🔴 改了那边要改这边重跑，否则「刷」和笔画对不上。

照真的笔写在纸上来：
    刷   笔尖和纸的摩擦 —— 宽带噪声（主要在 1–6kHz），被纸面纤维一下下「绊住」所以是沙沙的颗粒，
         响度跟着笔速走：一段里两头慢、中间快，于是每一段都是一声由弱到强再到弱的「刷」，拐角处几乎没声
    起笔 笔尖落到纸上那一下很轻的「嗒」
    砰   句点：写完了，笔头往纸上一按 —— 短促、低沉的「砰」：起头一下很短的闷冲击（低通过的噪声，没有清脆的「嗒」），
         跟着一个往下沉的低音（像按下去那一下桌面被压紧又松开），几十毫秒就收住，不拖尾巴。
         手机外放出不来 200Hz 以下，所以低音上面叠一个 250–300Hz 的泛音，让耳朵「补」出那一声低的。
         三种轻重可选（`DOT_STYLE`），`--preview` 各出一段完整的开场声试听。
         历史：第一版 0.8 毫秒硬撞击 + 1k / 2.3kHz 泛音 + 纸面「嗒」→ 用户嫌脆；
         第二版几个衰减慢的低共振（165–780Hz）→ 用户说像「咚——」拖长了，要的是更低、更短的「砰」

只用标准库（不依赖 numpy），随机数种子固定 —— 每次生成的文件一模一样，改了参数才会变。

用法：
    python3 Scripts/make_splash_sound.py                    生成 App 里用的（落点是 DOT_STYLE 那一种）
    python3 Scripts/make_splash_sound.py --preview <目录>   三种落点各出一段完整的开场声，试听用
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Memoir", "Resources", "Sounds", "splash_write.wav")

# —— 时间表：和 HandwrittenMark.Script 一模一样 ——
SEGMENT_DURATIONS = [0.142, 0.086, 0.113, 0.080]
# 每一段的长度（364 的格子，HandwrittenMark.lengths）：笔速 = 长度 × 段内进度的快慢
SEGMENT_LENGTHS = [148.2, 79.5, 110.6, 72.1]
EASE = 0.85
PEN_LIFT = 0.07
TAIL = 0.20          # 落点之后留的余音（「砰」本身几十毫秒就收住）
# 每一笔的轻重：两笔往下的（第一个尖往下、第二个尖往下带勾）压得重一点
SEGMENT_PRESSURE = [0.80, 1.00, 0.88, 0.95]

SEED = 20261024

# 落点「砰」的三种轻重：低音（起始 Hz → 落到 Hz、滑多久、衰减）、泛音（同上）、起头的闷冲击（低通 Hz、衰减、份量）、整体低通
DOT_STYLE = "peng"
DOT_STYLES = {
    # 砰：低、短，起头有一点冲击感
    "peng": {"body": (150, 100, 0.025, 0.030), "over": (290, 235, 0.020, 0.020, 0.55),
             "punch": (1400, 0.004, 0.40), "lowpass": 1600},
    # 更沉：再低一些、稍厚
    "deep": {"body": (125, 80, 0.030, 0.038), "over": (250, 200, 0.025, 0.024, 0.60),
             "punch": (1000, 0.005, 0.32), "lowpass": 1200},
    # 更短：更干、更利落
    "short": {"body": (170, 115, 0.018, 0.020), "over": (320, 260, 0.014, 0.013, 0.50),
              "punch": (1800, 0.003, 0.45), "lowpass": 2000},
}


def biquad(samples, kind, freq, q=0.707):
    """RBJ cookbook 双二阶滤波：lowpass / highpass / bandpass（峰值 0 dB）—— 和 make_book_sound.py 同一个"""
    w0 = 2 * math.pi * freq / RATE
    cos, alpha = math.cos(w0), math.sin(w0) / (2 * q)
    if kind == "lowpass":
        b0, b1, b2 = (1 - cos) / 2, 1 - cos, (1 - cos) / 2
    elif kind == "highpass":
        b0, b1, b2 = (1 + cos) / 2, -(1 + cos), (1 + cos) / 2
    else:  # bandpass
        b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * cos, 1 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    out = [0.0] * len(samples)
    x1 = x2 = y1 = y2 = 0.0
    for i, x in enumerate(samples):
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        out[i] = y
        x2, x1, y2, y1 = x1, x, y1, y
    return out


def resonate(excitation, freq, decay, n):
    """一个共振：二阶谐振器，冲激响应 ≈ sin(2πft)·e^(−t/decay)"""
    w = 2 * math.pi * freq / RATE
    r = math.exp(-1.0 / (decay * RATE))
    a1, a2, g = 2 * r * math.cos(w), -r * r, math.sin(w)
    y1 = y2 = 0.0
    out = [0.0] * n
    for i in range(n):
        x = excitation[i] if i < len(excitation) else 0.0
        y = a1 * y1 + a2 * y2 + g * x
        out[i] = y
        y2, y1 = y1, y
    return out


def pen_speed(t):
    """t 秒时笔有多快（格子 / 秒）和第几笔。写完之后是 0"""
    start = 0.0
    for k, dur in enumerate(SEGMENT_DURATIONS):
        if t < start + dur:
            tau = (t - start) / dur
            # Swift 那边的进度是 τ − ease·sin(2πτ)/2π，这里是它的导数（÷ 时长 = 这一段每秒走多少）
            return SEGMENT_LENGTHS[k] * (1 - EASE * math.cos(2 * math.pi * tau)) / dur, k
        start += dur
    return 0.0, None


def scratch(n, rng):
    """「刷刷刷」：摩擦噪声 × 纸面颗粒 × 笔速"""
    white = [rng.gauss(0, 1) for _ in range(n)]
    body = biquad(biquad(white, "bandpass", 1500, 1.0), "lowpass", 5000)
    hiss = biquad(biquad([rng.gauss(0, 1) for _ in range(n)], "bandpass", 3800, 0.9), "highpass", 1200)
    air = biquad([rng.gauss(0, 1) for _ in range(n)], "highpass", 6500)
    # 纸面纤维：笔尖一下下被绊住又滑开 —— 一条几百赫兹的随机起伏乘上去，沙沙的颗粒从这里来
    grain = biquad([abs(rng.gauss(0, 1)) for _ in range(n)], "lowpass", 550)
    gmax = max(grain) or 1.0

    speeds = []
    for i in range(n):
        v, k = pen_speed(i / RATE)
        speeds.append(v * (SEGMENT_PRESSURE[k] if k is not None else 0.0))
    vmax = max(speeds) or 1.0
    env = [(v / vmax) ** 1.4 for v in speeds]
    env = biquad(biquad(env, "lowpass", 70), "lowpass", 70)   # 抹掉包络里的锯齿，免得「咔哒」
    out = []
    for i in range(n):
        g = 0.35 + 0.65 * grain[i] / gmax
        out.append((0.55 * body[i] + 1.0 * hiss[i] + 0.25 * air[i]) * g * max(0.0, env[i]))
    return out


def tick(n, at, rng, freq, length, level):
    """很短的一下接触声（起笔落纸）"""
    out = [0.0] * n
    start = int(at * RATE)
    raw = [rng.gauss(0, 1) * math.exp(-i / (length * RATE)) * min(1.0, i / 12) for i in range(int(length * 8 * RATE))]
    for i, v in enumerate(biquad(raw, "bandpass", freq, 1.1)):
        if start + i < n:
            out[start + i] = v * level
    return out


def glide(m, start_hz, end_hz, glide_s, decay):
    """往下沉的一个音：频率在 glide_s 秒内从 start_hz 落到 end_hz，按 decay 秒衰减；起头 0.5ms 淡入免得出爆音"""
    out = [0.0] * m
    phase = 0.0
    for i in range(m):
        t = i / RATE
        u = min(1.0, t / glide_s)
        f = start_hz + (end_hz - start_hz) * (1 - (1 - u) ** 2)
        phase += 2 * math.pi * f / RATE
        out[i] = math.sin(phase) * math.exp(-t / decay) * min(1.0, i / 22)
    return out


def dot(n, at, rng, style=None):
    """「砰」：写完落笔，笔头往纸上一按"""
    spec = DOT_STYLES[style or DOT_STYLE]
    out = [0.0] * n
    start = int(at * RATE)
    m = min(n - start, int(0.25 * RATE))
    s0, s1, sg, sd = spec["body"]
    o0, o1, og, od, oa = spec["over"]
    track = [b + oa * o for b, o in zip(glide(m, s0, s1, sg, sd), glide(m, o0, o1, og, od))]
    # 起头那一下闷的冲击：很短的噪声，低通过，不要清脆的「嗒」
    cut, decay, level = spec["punch"]
    punch = biquad(biquad([rng.gauss(0, 1) * math.exp(-i / (decay * RATE)) * min(1.0, i / 10)
                           for i in range(int(decay * 8 * RATE))], "lowpass", cut), "lowpass", cut)
    pk = max(abs(v) for v in track) or 1.0
    pp = max(abs(v) for v in punch) or 1.0
    for i, v in enumerate(punch):
        if i < m:
            track[i] += level * pk * v / pp
    track = biquad(track, "lowpass", spec["lowpass"])
    pk = max(abs(v) for v in track) or 1.0
    track = [math.tanh(v / pk * 1.6) for v in track]          # 压一下头，短促有劲
    for i, v in enumerate(track):
        out[start + i] = v
    return out


def normalize(track, peak):
    m = max(abs(v) for v in track) or 1.0
    return [v * peak / m for v in track]


def render(style=None):
    rng = random.Random(SEED)
    writing = sum(SEGMENT_DURATIONS)
    dot_at = writing + PEN_LIFT
    n = int((dot_at + TAIL) * RATE)

    track = [0.0] * n
    for piece, peak in [(scratch(n, rng), 0.36),
                        (tick(n, 0.0, rng, 2400, 0.0015, 1.0), 0.10),
                        (dot(n, dot_at, rng, style), 0.50)]:
        for i, v in enumerate(normalize(piece, peak)):
            track[i] += v

    track = biquad(track, "highpass", 70)
    fade = int(0.05 * RATE)
    for i in range(fade):
        track[n - 1 - i] *= i / fade
    return normalize(track, 0.7), writing, dot_at


def write(track, path):
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in track))


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--preview":
        os.makedirs(sys.argv[2], exist_ok=True)
        for style in DOT_STYLES:
            track, _, _ = render(style)
            path = os.path.join(sys.argv[2], f"splash_{style}.wav")
            write(track, path)
            print(path)
        return
    track, writing, dot_at = render()
    write(track, OUT)
    print(f"{os.path.relpath(OUT)}  {len(track) / RATE:.2f}s  写 {writing:.3f}s，{dot_at:.3f}s 落点（{DOT_STYLE}）")


if __name__ == "__main__":
    main()
