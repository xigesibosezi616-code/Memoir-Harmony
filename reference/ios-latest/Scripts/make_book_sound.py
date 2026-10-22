#!/usr/bin/env python3
"""生成日记本的两种木头声（2026-10-17）：
    book_knock_1.wav … book_knock_3.wav  写日记前选本子，每转到一本「笃」一声
    shelf_drop.wav                      书架上拖着换位置，书落进新位置那一下「咚」

写日记之前选写在哪一本里（`NotebookPicker`），书一本本转过去，每到一本响一声木头声。

2026-10-17 第二版。第一版是一根往下滑的正弦波「嘭」，更像电子鼓，产品听了说难听。
这一版照真的敲木头来：一下很短的撞击（指节、书角碰上去那一两毫秒），激起木头里几个**衰减得很快**的共振 ——
木头损耗大，响不长，也没有哪一根「音」在唱：

    撞击  半个正弦的力脉冲，碰得越久越闷（`contact`）；再掺一点点粗糙的摩擦声
    共振  几个二阶谐振器：频率不成谐波（木板、木块的振型本来就不成倍数），越高衰减越快
    最后  低通压掉脆的那点，去直流

三种可选（`STYLE`），2026-10-17 产品听了三段试听，定 block：
    desk   指节敲木桌：「咚」，木头味最足
    block  小木块轻叩：「笃」，短、清（用的是这个）
    shelf  书搁到木架上：「噗咚」，最闷（手机外放出不来低音，听着会轻）

三份略有不同（共振频率差一两个百分点、噪声不同），`NotebookPickerFeel` 轮着放：连着转过去是「咚咚咚」，不是同一下复读。
三份差得很小 —— 差多了（第一版差 3.5%）会听成一段小曲调。

只用标准库（不依赖 numpy），随机数种子固定 —— 每次生成的文件一模一样，改了参数才会变。

书架那一声「咚」是选本子的**第一版**：一根往下沉的低音（像精装书的书板磕在木头书架上）+ 几个泛音 + 接触声。
放在转盘上一本接一本地响嫌闷、像电子鼓，产品否了；但书落回书架上就这一下，正合适（产品定，`thud()`，参数没动过）。

用法：
    python3 Scripts/make_book_sound.py                    生成 App 里用的全部（转盘那三份是 STYLE 那一种）
    python3 Scripts/make_book_sound.py --preview <目录>   转盘的三种各渲染一段「甩一下、越转越慢」的连响，试听用
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 44100
LENGTH = 0.22
STYLE = "block"

# 每种：撞击多久（秒）、粗糙声多少、共振（频率 Hz、衰减时间秒、振幅）、低通、额外的布面 / 纸声
STYLES = {
    "desk": {
        "contact": 0.0009,
        "roughness": 0.10,
        "modes": [(205, 0.038, 0.80), (437, 0.024, 1.00), (712, 0.015, 0.75),
                  (1046, 0.009, 0.50), (1453, 0.006, 0.32), (2020, 0.0035, 0.20)],
        "lowpass": 3200,
        "cloth": 0.0,
    },
    "block": {
        "contact": 0.0005,
        "roughness": 0.08,
        "modes": [(512, 0.030, 1.00), (1180, 0.012, 0.60), (1890, 0.006, 0.35), (2750, 0.003, 0.20)],
        "lowpass": 4500,
        "cloth": 0.0,
    },
    "shelf": {
        "contact": 0.0018,
        "roughness": 0.06,
        "modes": [(168, 0.045, 0.90), (356, 0.026, 1.00), (590, 0.015, 0.60),
                  (880, 0.009, 0.35), (1250, 0.005, 0.20)],
        "lowpass": 2200,
        "cloth": 0.25,
    },
}

# 三份的差别：共振频率的倍数、噪声种子
VARIANTS = [(1.000, 20261017), (0.986, 20261018), (1.011, 20261019)]


def biquad(samples, kind, freq, q=0.707):
    """RBJ cookbook 双二阶滤波：lowpass / highpass / bandpass（峰值 0 dB）—— 和 make_post_sound.py 同一个"""
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
    """木头的一个共振：二阶谐振器，冲激响应 ≈ sin(2πft)·e^(−t/decay)，振幅归一到 1"""
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


def knock(style, detune, seed):
    spec = STYLES[style]
    rng = random.Random(seed)
    n = int(LENGTH * RATE)

    # 撞击：半个正弦的力脉冲，面积归一（碰得越久，高频越少 —— 「闷」从这里来）
    width = max(2, int(spec["contact"] * RATE))
    pulse = [math.sin(math.pi * (i + 0.5) / width) for i in range(width)]
    area = sum(pulse)
    excitation = [v / area for v in pulse] + [0.0] * int(0.004 * RATE)
    # 表面粗糙：一点点很短的高频噪声，填上脉冲频谱的凹口，听着才不像电子合成
    rough = biquad([rng.gauss(0, 1) * math.exp(-i / (0.0004 * RATE)) for i in range(len(excitation))], "highpass", 900)
    peak = max(abs(v) for v in excitation)
    excitation = [e + spec["roughness"] * peak * r for e, r in zip(excitation, rough)]

    track = [0.0] * n
    for freq, decay, amp in spec["modes"]:
        jitter = 1 + rng.uniform(-0.08, 0.08)   # 每一份各个共振的轻重略有不同
        for i, v in enumerate(resonate(excitation, freq * detune, decay, n)):
            track[i] += v * amp * jitter

    # 书的布面 / 纸碰上去那一下「噗」（只有 shelf 有）
    if spec["cloth"] > 0:
        cloth = biquad([rng.gauss(0, 1) * math.exp(-i / (0.004 * RATE)) * min(1.0, i / 40) for i in range(int(0.03 * RATE))],
                       "lowpass", 1200)
        level = max(abs(v) for v in track) * spec["cloth"] / (max(abs(v) for v in cloth) or 1)
        for i, v in enumerate(cloth):
            track[i] += v * level

    track = biquad(track, "lowpass", spec["lowpass"])
    track = biquad(track, "highpass", 70)
    fade = int(0.04 * RATE)
    for i in range(fade):
        track[n - 1 - i] *= i / fade
    return track


def speaker_rms(track):
    """手机外放听得到的那部分有多响：滤掉 300Hz 以下（外放出不来），取前 60 毫秒的均方根"""
    heard = biquad(biquad(track, "highpass", 300), "highpass", 300)[: int(0.06 * RATE)]
    return math.sqrt(sum(v * v for v in heard) / len(heard))


def render(style):
    """三份，按外放听到的响度归一（三种风格互相比较时也一样响，和第一版差不多响）；峰值不超过 0.6"""
    tracks = [knock(style, detune, seed) for detune, seed in VARIANTS]
    gain = 0.045 / (sum(speaker_rms(t) for t in tracks) / len(tracks))
    peak = max(abs(v) for t in tracks for v in t) * gain
    if peak > 0.6:
        gain *= 0.6 / peak
    return [[v * gain for v in t] for t in tracks]


def write(track, path):
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in track))


# ---------- 书架换位落定的「咚」（选本子第一版，原样保留） ----------

THUD_LENGTH = 0.24


def mode(n, start_hz, end_hz, glide, decay):
    """一个衰减的正弦：音高在 glide 秒内从 start_hz 滑到 end_hz（敲下去那一下木头被压紧，音略高，随后回落）"""
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        u = min(1.0, t / glide) if glide > 0 else 1.0
        f = start_hz + (end_hz - start_hz) * (1 - (1 - u) ** 2)
        phase += 2 * math.pi * f / RATE
        attack = min(1.0, i / 30)   # 起头 0.7ms 淡入，免得出数码爆音
        out.append(math.sin(phase) * math.exp(-t / decay) * attack)
    return out


def thud(seed, pitch):
    """书板磕在木头书架上：150→128Hz 的低音往下沉一点（「咚」主要是它）+ 260 / 400 / 690Hz 几个泛音 + 很短的接触声，
    整体低通 1.5kHz（闷，不脆）。260 那个泛音给得重：手机外放出不来 200Hz 以下，靠它让耳朵「补」出那一声低的"""
    rng = random.Random(seed)
    n = int(THUD_LENGTH * RATE)
    track = [0.0] * n

    def add(piece, gain):
        for i, v in enumerate(piece[:n]):
            track[i] += v * gain

    add(mode(n, 152 * pitch, 128 * pitch, 0.04, 0.05), 0.55)
    add(mode(n, 266 * pitch, 254 * pitch, 0.02, 0.034), 0.34)
    add(mode(n, 405 * pitch, 398 * pitch, 0.01, 0.020), 0.17)
    add(mode(n, 690 * pitch, 686 * pitch, 0.0, 0.011), 0.07)

    contact_n = int(0.03 * RATE)
    raw = [rng.gauss(0, 1) * math.exp(-i / (0.005 * RATE)) * min(1.0, i / 22) for i in range(contact_n)]
    add(biquad(raw, "bandpass", 620 * pitch, 0.9), 0.42)
    add(biquad(raw, "bandpass", 1700 * pitch, 1.2), 0.05)

    track = biquad(track, "lowpass", 1500)
    track = biquad(track, "highpass", 55)
    track = [math.tanh(v * 1.3) / 1.3 for v in track]
    fade = int(0.03 * RATE)
    for i in range(fade):
        track[n - 1 - i] *= i / fade
    return track


def shelf_drop():
    """第一版是三份一起归一到峰值 0.45、轮着放；书架上只用第一份 —— 照原来的算法算三份、一起归一，取第一份，和当时那一声一模一样"""
    tracks = [thud(20261017, 1.0), thud(20261018, 0.965), thud(20261019, 1.035)]
    peak = max(abs(v) for t in tracks for v in t) or 1.0
    return [v * 0.45 / peak for v in tracks[0]]


# ---------- 试听 ----------

def glide_ticks(v0=10.0):
    """「甩一下」时每到一本的时刻和速度：和 App 里 `CarouselMotion.Glide` 同一套摩擦（τ=1.3、a=1.8）、同一套判断"""
    tau, friction = 1.3, 1.8
    c = friction * tau
    duration = tau * math.log(1 + v0 / c)
    distance = tau * v0 - c * duration
    target = round(distance)
    k = distance / target
    duration /= k
    ticks, last, t = [], 0, 0.0
    while t <= duration:
        s = t * k
        p = tau * (v0 + c) * (1 - math.exp(-s / tau)) - c * s
        p /= k
        if t >= duration:
            p = target
        if p >= last + 1 - 0.02:
            last = math.floor(p + 0.02)
            speed = max(0.0, (v0 + c) * math.exp(-s / tau) - c)
            if not ticks or t - ticks[-1][0] >= 0.045:
                ticks.append((t, speed))
        t += 1 / 240
    return ticks


def preview(directory):
    """每种一段：先单独敲两下，再「甩一下、越转越慢」—— 音量规则同 `NotebookPickerFeel`（快时轻、慢下来重）"""
    os.makedirs(directory, exist_ok=True)
    for style in STYLES:
        knocks = render(style)
        hits = [(0.15, 0.0), (0.75, 0.0)] + [(1.5 + t, speed) for t, speed in glide_ticks()]
        out = [0.0] * int((hits[-1][0] + 0.6) * RATE)
        for index, (at, speed) in enumerate(hits):
            volume = 0.8 - 0.25 * min(1.0, speed / 12)
            for i, v in enumerate(knocks[index % 3]):
                j = int(at * RATE) + i
                if j < len(out):
                    out[j] += v * volume
        path = os.path.join(directory, f"试听_{style}.wav")
        write(out, path)
        print(f"写好了：{path}（{len(out) / RATE:.1f}s，{len(hits)} 声）")


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--preview":
        preview(sys.argv[2])
    else:
        sounds_dir = os.path.join(os.path.dirname(__file__), "..", "Memoir", "Resources", "Sounds")
        os.makedirs(sounds_dir, exist_ok=True)
        for index, track in enumerate(render(STYLE), start=1):
            path = os.path.join(sounds_dir, f"book_knock_{index}.wav")
            write(track, path)
            print(f"写好了：{os.path.normpath(path)}（{STYLE}，{len(track) / RATE:.2f}s）")
        path = os.path.join(sounds_dir, "shelf_drop.wav")
        write(shelf_drop(), path)
        print(f"写好了：{os.path.normpath(path)}（书架落定的「咚」，{THUD_LENGTH:.2f}s）")
