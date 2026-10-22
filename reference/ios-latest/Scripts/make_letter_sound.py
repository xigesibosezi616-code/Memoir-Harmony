#!/usr/bin/env python3
"""生成拆火漆信的纸张音效：Memoir/Resources/Sounds/letter_open_1.wav / _2 / _3

拆信是三下（2026-10-11 产品定）：第一下打碎火漆、第二下打开信封、第三下抽出信纸，
每一步一个音效文件，时间都从这一下点下去算起。下面的时刻是「一口气拆完」时的整条时间轴，
写文件时减去各步的起点：

    第 1 步  0.00–0.36s  火漆裂开      动画 progress 0–0.14
    第 2 步  0.36–1.43s  封舌翻起      progress 0.14–0.55，0.87s 翻过 90°
    第 3 步  1.43–2.60s  信纸抽出      progress 0.55–1.0，2.0s 最快
             2.60–3.15s  摊开成信纸    0.55s 淡入（并在第 3 步的文件里）

必须和 `LetterOpeningFeel.swift`（震动、各步起点）、`SealedEnvelope.swift`（动画）对齐。

只用标准库（不依赖 numpy），随机数种子固定 —— 每次生成的文件一模一样，改了参数才会变。

用法：python3 Scripts/make_letter_sound.py
"""
import math
import os
import random
import struct
import wave

RATE = 44100
LENGTH = 3.35
N = int(RATE * LENGTH)
rng = random.Random(20261011)

# 三步各自的起点（整条时间轴上的秒数），和 LetterOpeningFeel.stageStarts 一致
STAGE_STARTS = [0.0, 0.364, 1.43]
STAGE_ENDS = [0.5, 1.47, 3.2]

# 动画时间轴（秒）。火漆比原来提前 0.04s：现在它是对「点一下」的直接回应，要跟手
CRACK = 0.03
LIFT_START, LIFT_END, FLAP_OVER = 0.312, 1.43, 0.871
SLIDE_START, SLIDE_END = 1.43, 2.60
SETTLE = 3.05


# ---------- 基本零件 ----------

def biquad(samples, kind, freq, q=0.707):
    """RBJ cookbook 双二阶滤波：lowpass / highpass / bandpass（峰值 0 dB）"""
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


def noise(n):
    return [rng.gauss(0, 1) for _ in range(n)]


def add(track, start, piece, gain=1.0):
    i0 = int(start * RATE)
    for i, v in enumerate(piece):
        j = i0 + i
        if 0 <= j < N:
            track[j] += v * gain


def burst(duration, decay, kind, freq, q=0.8):
    """一下短促的声音：一段噪声，指数衰减，再过滤波"""
    n = int(duration * RATE)
    raw = [v * math.exp(-i / (decay * RATE)) for i, v in enumerate(noise(n))]
    # 起头 1ms 淡入，免得出「咔」的数码爆音
    for i in range(min(n, 44)):
        raw[i] *= i / 44
    return biquad(raw, kind, freq, q)


def tone(duration, freq, decay):
    n = int(duration * RATE)
    return [math.sin(2 * math.pi * freq * i / RATE) * math.exp(-i / (decay * RATE)) * min(1, i / 40)
            for i in range(n)]


def crinkles(track, start, end, density, amp, density_curve=lambda u: 1.0):
    """纸的细碎脆响：很多 0.5–2ms 的小咔哒，随机落点"""
    t = start
    while t < end:
        u = (t - start) / max(end - start, 1e-6)
        rate = max(density * density_curve(u), 1e-3)
        t += rng.expovariate(rate)
        if t >= end:
            break
        dur = rng.uniform(0.0006, 0.002)
        click = burst(dur + 0.004, dur, "highpass", rng.uniform(2200, 4200), 0.7)
        add(track, t, click, amp * rng.uniform(0.35, 1.0) * density_curve(u))


def rustle(start, end, envelope, low, high, grain_hz, grain_depth):
    """持续的纸声：带通噪声 × 包络 × 纤维颗粒（随机的快速起伏）"""
    n = int((end - start) * RATE)
    sig = biquad(biquad(noise(n), "highpass", low), "lowpass", high)
    sig = biquad(sig, "highpass", low * 0.8)
    # 颗粒：每 1/grain_hz 秒换一个随机目标，平滑过去
    step = max(1, int(RATE / grain_hz))
    level, target = 1.0, 1.0
    out = []
    for i, v in enumerate(sig):
        if i % step == 0:
            target = 1 + grain_depth * rng.uniform(-1, 1)
        level += (target - level) * 0.004
        u = i / max(n - 1, 1)
        out.append(v * envelope(u) * level)
    return out


def bell(u):
    """smoothstep 的速度曲线 6u(1-u)，归一到峰值 1"""
    u = min(max(u, 0.0), 1.0)
    return 4 * u * (1 - u)


# ---------- 按时间轴拼起来 ----------

track = [0.0] * N

# 1. 火漆裂开：一声闷闷的「嗒」+ 脆裂，跟着几下细小的裂声
add(track, CRACK, tone(0.06, 185, 0.018), 0.30)
add(track, CRACK, burst(0.03, 0.004, "bandpass", 2600, 0.9), 0.95)
for t, a in [(0.078, 0.50), (0.122, 0.34), (0.186, 0.22)]:
    add(track, t, burst(0.025, 0.003, "bandpass", rng.uniform(2200, 3400), 0.9), a)
    add(track, t, tone(0.03, rng.uniform(210, 260), 0.010), a * 0.25)
crinkles(track, 0.02, 0.26, 55, 0.10, lambda u: 1 - u * 0.7)

# 2. 封舌：先是从封口撕开的一小段脆响（点下去就响），然后随翻起的速度沙沙响，翻过头顶时「噗」一下
crinkles(track, 0.37, 0.58, 85, 0.13, lambda u: 1 - u)
add(track, 0.37, rustle(0.37, 0.52, lambda u: math.sin(math.pi * u), 3000, 7000, 60, 0.6), 0.07)
add(track, 0.36, rustle(0.36, LIFT_END, lambda u: bell(u) ** 1.2, 900, 4500, 35, 0.45), 0.11)
add(track, FLAP_OVER + 0.01, burst(0.07, 0.016, "bandpass", 620, 0.7), 0.28)

# 3. 信纸抽出：纸擦纸，中段最快最响，带纤维的颗粒感；离开信封时轻轻一「嘶」
add(track, SLIDE_START + 0.02,
    rustle(SLIDE_START + 0.02, SLIDE_END - 0.04, lambda u: bell(u) ** 0.8, 700, 3800, 28, 0.75), 0.16)
crinkles(track, SLIDE_START + 0.1, SLIDE_END - 0.1, 22, 0.05, lambda u: bell(u))
add(track, SLIDE_END - 0.06, burst(0.09, 0.028, "bandpass", 1900, 0.6), 0.11)

# 4. 摊开：展开的几下脆响，最后轻轻落在桌上
crinkles(track, 2.70, 2.95, 70, 0.09, lambda u: math.sin(math.pi * u))
add(track, 2.70, rustle(2.70, 2.98, lambda u: math.sin(math.pi * u), 1000, 5000, 40, 0.5), 0.06)
add(track, SETTLE, burst(0.09, 0.022, "bandpass", 340, 0.8), 0.32)
add(track, SETTLE, tone(0.06, 118, 0.02), 0.08)

# ---------- 收尾：去直流、软限幅、归一（整条一起归一，三段之间响度一致），切成三段 ----------

track = biquad(track, "highpass", 60)
track = [math.tanh(v * 1.4) / 1.4 for v in track]
peak = max(abs(v) for v in track) or 1.0
gain = 0.45 / peak

sounds_dir = os.path.join(os.path.dirname(__file__), "..", "Memoir", "Resources", "Sounds")
os.makedirs(sounds_dir, exist_ok=True)
old = os.path.join(sounds_dir, "letter_open.wav")
if os.path.exists(old):
    os.remove(old)
fade = int(0.02 * RATE)
for index, (start, end) in enumerate(zip(STAGE_STARTS, STAGE_ENDS), 1):
    piece = track[int(start * RATE):int(end * RATE)]
    for i in range(min(fade, len(piece))):
        piece[len(piece) - 1 - i] *= i / fade
    path = os.path.join(sounds_dir, f"letter_open_{index}.wav")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * gain)) * 32767)) for v in piece))
    print(f"写好了：{os.path.normpath(path)}（{end - start:.2f}s）")
