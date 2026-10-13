#!/usr/bin/env python3
"""生成投信的音效：Memoir/Resources/Sounds/letter_post_sealed.wav（会员，盖火漆）/ letter_post_plain.wav（免费）

投信是一口气的动作（2026-10-11 产品定），整条时间轴从点下邮筒算起：

    0.00–0.32  那叠日记收拢成一页      纸拢在一起的沙沙声
    0.32–0.95  信纸滑进信封            纸擦纸，中段最响；到底轻轻一「嗒」
    0.95–1.40  封舌合上                翻过来的一点风声，1.40 落下「啪」
    1.46–1.76  会员：火漆压下去        蜡被挤扁的细响，1.70 实实的一下「噗」
               免费：指腹抹平封口      指腹擦过纸
    1.82–2.42  举到投信口              安静
    2.42–2.82  推进投信口              翻板被顶开的一声轻「吱」，纸蹭着铁皮越推越紧
    2.90       翻板落回去              铁皮翻板落下的闷响，邮筒里一点回声

必须和 `LetterPostingTimeline`（动画）、`LetterPostingFeel.swift`（震动）对齐。

只用标准库（不依赖 numpy），随机数种子固定 —— 每次生成的文件一模一样，改了参数才会变。

用法：python3 Scripts/make_post_sound.py
"""
import math
import os
import random
import struct
import wave

RATE = 44100
LENGTH = 3.3
N = int(RATE * LENGTH)

# 时间轴（秒），和 LetterPostingTimeline 一致
GATHER = (0.0, 0.32)
SLIDE = (0.32, 0.95)
FLAP = (0.95, 1.40)
SEAL = (1.46, 1.76)
INSERT = (2.42, 2.82)
CLACK = 2.90


# ---------- 基本零件（和 make_letter_sound.py 同一套） ----------

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


def make(rng):
    def noise(n):
        return [rng.gauss(0, 1) for _ in range(n)]

    def burst(duration, decay, kind, freq, q=0.8):
        """一下短促的声音：一段噪声，指数衰减，再过滤波"""
        n = int(duration * RATE)
        raw = [v * math.exp(-i / (decay * RATE)) for i, v in enumerate(noise(n))]
        for i in range(min(n, 44)):   # 起头 1ms 淡入，免得出「咔」的数码爆音
            raw[i] *= i / 44
        return biquad(raw, kind, freq, q)

    def tone(duration, freq, decay):
        n = int(duration * RATE)
        return [math.sin(2 * math.pi * freq * i / RATE) * math.exp(-i / (decay * RATE)) * min(1, i / 40)
                for i in range(n)]

    def rustle(start, end, envelope, low, high, grain_hz, grain_depth):
        """持续的纸声：带通噪声 × 包络 × 纤维颗粒（随机的快速起伏）"""
        n = int((end - start) * RATE)
        sig = biquad(biquad(noise(n), "highpass", low), "lowpass", high)
        sig = biquad(sig, "highpass", low * 0.8)
        step = max(1, int(RATE / grain_hz))
        level, target = 1.0, 1.0
        out = []
        for i, v in enumerate(sig):
            if i % step == 0:
                target = 1 + grain_depth * rng.uniform(-1, 1)
            level += (target - level) * 0.004
            out.append(v * envelope(i / max(n - 1, 1)) * level)
        return out

    def crinkles(track, start, end, density, amp, density_curve=lambda u: 1.0):
        """纸的细碎脆响：很多 0.5–2ms 的小咔哒，随机落点"""
        t = start
        while t < end:
            u = (t - start) / max(end - start, 1e-6)
            t += rng.expovariate(max(density * density_curve(u), 1e-3))
            if t >= end:
                break
            dur = rng.uniform(0.0006, 0.002)
            click = burst(dur + 0.004, dur, "highpass", rng.uniform(2200, 4200), 0.7)
            add(track, t, click, amp * rng.uniform(0.35, 1.0) * density_curve(u))

    return noise, burst, tone, rustle, crinkles


def add(track, start, piece, gain=1.0):
    i0 = int(start * RATE)
    for i, v in enumerate(piece):
        j = i0 + i
        if 0 <= j < N:
            track[j] += v * gain


def bell(u):
    u = min(max(u, 0.0), 1.0)
    return 4 * u * (1 - u)


def build(sealed):
    # 两份用同一个种子（封口之后再重播一次）：除了盖火漆 / 抹封口那一段，其余听起来一模一样
    rng = random.Random(20261011)
    noise, burst, tone, rustle, crinkles = make(rng)
    track = [0.0] * N

    # 1. 收拢：纸拢在一起的沙沙声，几下轻脆
    add(track, 0.01, rustle(0.01, 0.30, lambda u: math.sin(math.pi * u), 1200, 5500, 45, 0.55), 0.08)
    crinkles(track, 0.02, 0.28, 60, 0.07, lambda u: 1 - u * 0.6)

    # 2. 滑进信封：纸擦纸，中段最响；到底轻轻一「嗒」
    add(track, SLIDE[0] + 0.01, rustle(SLIDE[0] + 0.01, SLIDE[1] - 0.03, lambda u: bell(u) ** 0.8, 700, 3800, 28, 0.7), 0.15)
    crinkles(track, SLIDE[0] + 0.06, SLIDE[1] - 0.08, 18, 0.045, bell)
    add(track, SLIDE[1] - 0.03, burst(0.06, 0.012, "bandpass", 700, 0.8), 0.18)

    # 3. 封舌合上：一点翻过来的风声，落下「啪」
    add(track, FLAP[0], rustle(FLAP[0], FLAP[1], lambda u: bell(u) ** 1.4, 300, 1500, 20, 0.3), 0.06)
    add(track, FLAP[1], burst(0.06, 0.010, "bandpass", 900, 0.7), 0.30)
    add(track, FLAP[1], tone(0.05, 160, 0.012), 0.10)

    # 4. 封口
    if sealed:
        # 火漆：蜡被挤扁的细响，压实的一下闷闷的「噗」
        add(track, SEAL[0] + 0.04, rustle(SEAL[0] + 0.04, SEAL[1] - 0.06, lambda u: u ** 1.5, 200, 1200, 30, 0.5), 0.05)
        add(track, SEAL[1] - 0.06, tone(0.09, 118, 0.03), 0.42)
        add(track, SEAL[1] - 0.06, burst(0.08, 0.016, "bandpass", 420, 0.9), 0.38)
        add(track, SEAL[1] - 0.05, burst(0.04, 0.006, "bandpass", 1800, 1.2), 0.08)
    else:
        # 指腹抹平封口：一段很轻的摩擦
        add(track, SEAL[0] + 0.02, rustle(SEAL[0] + 0.02, SEAL[1] - 0.02, lambda u: math.sin(math.pi * u), 1500, 6000, 50, 0.5), 0.05)

    # 封口那段两份消耗的随机数不一样，这里重新播种，后半段两份才一模一样
    rng.seed(20261012)

    # 5. 推进投信口：翻板被顶开的一声轻「吱」，纸蹭着铁皮越推越紧
    add(track, INSERT[0] + 0.03, burst(0.08, 0.02, "bandpass", 2600, 4.0), 0.10)
    add(track, INSERT[0] + 0.03, tone(0.07, 1450, 0.02), 0.025)
    add(track, INSERT[0], rustle(INSERT[0], INSERT[1], lambda u: (0.3 + 0.7 * u) * (1 - max(0, u - 0.88) / 0.12), 900, 4800, 36, 0.8), 0.15)
    # 铁皮的一点泛音，很淡
    scrape = biquad(noise(int((INSERT[1] - INSERT[0]) * RATE)), "bandpass", 3300, 9.0)
    add(track, INSERT[0], [v * (0.3 + 0.7 * i / len(scrape)) for i, v in enumerate(scrape)], 0.03)

    # 6. 翻板落回去：铁皮翻板落下的闷响，邮筒里一点回声
    add(track, CLACK, tone(0.25, 92, 0.055), 0.45)
    add(track, CLACK, tone(0.15, 205, 0.03), 0.20)
    add(track, CLACK, burst(0.10, 0.012, "bandpass", 720, 1.1), 0.55)
    add(track, CLACK, burst(0.05, 0.004, "bandpass", 2400, 1.5), 0.12)
    add(track, CLACK, tone(0.12, 1240, 0.035), 0.035)
    add(track, CLACK, tone(0.10, 2730, 0.025), 0.02)
    # 邮筒是个空铁筒：低低的一点余音
    add(track, CLACK + 0.02, biquad(burst(0.25, 0.07, "lowpass", 380, 0.7), "highpass", 70), 0.10)

    # 去直流、软限幅
    track = biquad(track, "highpass", 50)
    return [math.tanh(v * 1.4) / 1.4 for v in track]


sounds_dir = os.path.join(os.path.dirname(__file__), "..", "Memoir", "Resources", "Sounds")
os.makedirs(sounds_dir, exist_ok=True)
tracks = {"sealed": build(True), "plain": build(False)}
# 两份一起归一，响度一致；和拆信的音效同一个峰值
peak = max(abs(v) for t in tracks.values() for v in t) or 1.0
gain = 0.45 / peak
fade = int(0.02 * RATE)
for name, track in tracks.items():
    for i in range(fade):
        track[len(track) - 1 - i] *= i / fade
    path = os.path.join(sounds_dir, f"letter_post_{name}.wav")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * gain)) * 32767)) for v in track))
    print(f"写好了：{os.path.normpath(path)}（{LENGTH:.2f}s）")
