#!/usr/bin/env python3
"""生成投信的音效：Memoir/Resources/Sounds/letter_post_sealed.wav（会员，盖火漆）/ letter_post_plain.wav（免费），
以及戳邮筒的一声：mailbox_poke.wav（2026-10-16）

投信是一口气的动作（2026-10-11 产品定），整条时间轴从点下邮筒算起：

    0.00–0.24  那叠日记收拢成一页      纸拢在一起的沙沙声
    0.24–0.56  信纸滑进信封            纸擦纸，中段最响；到底轻轻一「嗒」
    0.48–0.86  封舌合上（和上一段叠着）翻过来的一点风声，0.86 落下「啪」
    0.90–1.20  会员：火漆压下去        蜡被挤扁的细响，1.14 实实的一下「噗」
               免费：指腹抹平封口      指腹擦过纸
    1.20–1.75  举到投信口              安静
    1.75–2.15  推进投信口              纸顺着投信口的唇边滑进去，越推越深，进了筒里声音闷下去
    2.21       信落进邮筒              软软的一下「噗」+ 空铁筒里低低一声「咚」+ 纸摞上的一点细响

2026-10-20 真机上嫌「装进信封慢、封舌合上那一下生硬」：收拢、装信加快，封舌提前合（和装信叠着），整段 2.95 → 2.28 秒。

必须和 `LetterPostingTimeline`（动画）、`LetterPostingFeel.swift`（震动）对齐。

🔴 2026-10-20 产品定：**铁皮声只留给戳邮筒**（没信可寄时戳着玩），寄信换成上面那个「落信」声 ——
原来投信最后也是翻板落回来的「哐」，推进投信口时还有铁皮的「吱」和泛音，都去掉了。

戳邮筒（邮筒这会儿不收信、或者只是想听那一声）：手指把投信口的翻板顶进去一点（0.00 一声轻「吱」），
翻板落回来（0.07「哐」）。`LetterPostingFeel.pokeClack` 要和 POKE_CLACK 一致。

往投信口推信的那一路（2026-10-20，见 `LetterLiftFeel.swift`）—— 信封跟着手装，推到哪装到哪：
    letter_pick_up      拿起来：纸被拈起来的一点沙沙
    letter_lift_loop    往上推的一路：纸在空中走的风声，6 秒一轮、首尾接得上（循环放，响度和音高在 App 里跟着手调）
    letter_tuck         信纸装到信封底：轻轻一「嗒」（和整段里 SLIDE 末尾那一下同一个声）
    letter_flap         封舌合上：「啪」（和整段里 FLAP 末尾那一下同一个声）
    letter_settle       没推到就松手：信落回桌上的「噗」
    letter_post_tail_*  松手寄出后的后半截：整段从 TAIL（封舌落定之后）切开的后面那截 —— 封口、推进投信口、落信

只用标准库（不依赖 numpy），随机数种子固定 —— 每次生成的文件一模一样，改了参数才会变。

用法：python3 Scripts/make_post_sound.py
"""
import math
import os
import random
import struct
import wave

RATE = 44100
LENGTH = 2.65
N = int(RATE * LENGTH)

# 时间轴（秒），和 LetterPostingTimeline 一致
GATHER = (0.0, 0.24)
SLIDE = (0.24, 0.56)
FLAP = (0.48, 0.86)
SEAL = (0.90, 1.20)
INSERT = (1.75, 2.15)
LAND = 2.21
# 推着寄时松手后只放这之后的一截（封舌落定之后一点），和 LetterPostingFeel.tailStart 一致
TAIL = 0.88
# 往投信口推信那一路的循环声多长
LIFT_LOOP = 6.0
# 戳邮筒
POKE_LENGTH = 0.6
POKE_CLACK = 0.07


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
        if 0 <= j < len(track):
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
    add(track, GATHER[0] + 0.01, rustle(GATHER[0] + 0.01, GATHER[1] - 0.02, lambda u: math.sin(math.pi * u), 1200, 5500, 45, 0.55), 0.08)
    crinkles(track, GATHER[0] + 0.02, GATHER[1] - 0.04, 60, 0.07, lambda u: 1 - u * 0.6)

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

    # 5. 推进投信口：纸顺着投信口的唇边滑进去，越推越深（不再有铁皮的「吱」和泛音）
    add(track, INSERT[0], rustle(INSERT[0], INSERT[1], lambda u: (0.3 + 0.7 * u) * (1 - max(0, u - 0.88) / 0.12), 700, 4200, 36, 0.8), 0.15)
    # 进了筒里，声音闷下去：一层越来越明显的低低空腔
    cavity = biquad(noise(int((INSERT[1] - INSERT[0]) * RATE)), "bandpass", 300, 2.5)
    add(track, INSERT[0], [v * (i / len(cavity)) ** 2 for i, v in enumerate(cavity)], 0.05)

    # 6. 信落进邮筒
    land(track, LAND, burst, tone, rustle)
    return finish(track)


def land(track, at, burst, tone, rustle):
    """信落进邮筒（投信最后那一下，2026-10-20 新做）：信封落在筒里那一摞信上"""
    # 纸落在纸上：软软的「噗」
    add(track, at, burst(0.09, 0.018, "lowpass", 900, 0.7), 0.50)
    # 空铁筒里低低一声「咚」：很低、很短，是闷的，不是铁皮那种响
    add(track, at, tone(0.30, 74, 0.075), 0.42)
    add(track, at, tone(0.18, 148, 0.04), 0.12)
    # 筒里的空腔回响，慢慢散掉
    add(track, at + 0.01, biquad(burst(0.40, 0.11, "bandpass", 260, 2.2), "highpass", 90), 0.16)
    # 纸摞上的一点细响：信封压到底下那几封
    add(track, at + 0.03, rustle(at + 0.03, at + 0.15, lambda u: (1 - u) ** 2, 1500, 5500, 40, 0.5), 0.05)


def clack(track, at, burst, tone):
    """铁皮翻板落下的闷响，邮筒里一点回声（戳邮筒专用；2026-10-20 起投信不再用它）"""
    add(track, at, tone(0.25, 92, 0.055), 0.45)
    add(track, at, tone(0.15, 205, 0.03), 0.20)
    add(track, at, burst(0.10, 0.012, "bandpass", 720, 1.1), 0.55)
    add(track, at, burst(0.05, 0.004, "bandpass", 2400, 1.5), 0.12)
    add(track, at, tone(0.12, 1240, 0.035), 0.035)
    add(track, at, tone(0.10, 2730, 0.025), 0.02)
    # 邮筒是个空铁筒：低低的一点余音
    add(track, at + 0.02, biquad(burst(0.25, 0.07, "lowpass", 380, 0.7), "highpass", 70), 0.10)


def finish(track):
    """去直流、软限幅"""
    track = biquad(track, "highpass", 50)
    return [math.tanh(v * 1.4) / 1.4 for v in track]


def build_poke():
    """戳邮筒：手指把翻板顶进去一点，翻板落回来「哐」"""
    rng = random.Random(20261016)
    _, burst, tone, _, _ = make(rng)
    track = [0.0] * int(RATE * POKE_LENGTH)
    # 顶开翻板：比投信时那声「吱」轻（只是手指碰了一下）
    add(track, 0.0, burst(0.05, 0.012, "bandpass", 2600, 4.0), 0.06)
    add(track, 0.0, tone(0.05, 1450, 0.015), 0.015)
    clack(track, POKE_CLACK, burst, tone)
    return finish(track)


# ---------- 往投信口推信那一路（2026-10-20） ----------

def build_pick_up():
    """拿起来：纸被拈起来的一点沙沙，两三下细脆"""
    rng = random.Random(20261020)
    _, _, _, rustle, crinkles = make(rng)
    track = [0.0] * int(RATE * 0.35)
    add(track, 0.0, rustle(0.0, 0.18, lambda u: math.sin(math.pi * u) ** 1.5, 1000, 5000, 45, 0.6), 0.09)
    crinkles(track, 0.01, 0.12, 30, 0.05, lambda u: 1 - u)
    return finish(track)


def build_lift_loop():
    """往上推的一路：纸在空中走的风声。一轮 LIFT_LOOP 秒，首尾交叉淡化接上，循环放听不出接缝。
    App 里响度跟着手速、音高跟着高度调（`LetterLiftFeel`），这里只出一段均匀的底子"""
    rng = random.Random(20261021)
    _, _, _, rustle, crinkles = make(rng)
    overlap = 0.4
    total = LIFT_LOOP + overlap
    track = [0.0] * int(RATE * total)
    # 风声：偏低的一层，纸面上的颗粒起伏
    add(track, 0.0, rustle(0.0, total, lambda u: 1.0, 250, 2600, 9, 0.35), 0.13)
    # 纸边抖动的高一点那层，很淡
    add(track, 0.0, rustle(0.0, total, lambda u: 1.0, 1800, 6500, 22, 0.6), 0.03)
    crinkles(track, 0.05, total - 0.05, 6, 0.025)
    track = finish(track)
    n = int(RATE * LIFT_LOOP)
    f = int(RATE * overlap)
    # 头上 overlap 秒和尾巴那段交叉淡化：放到最后一个采样时，接下去的正好是尾巴后面那一段
    return [track[i] * (i / f) + track[n + i] * (1 - i / f) if i < f else track[i] for i in range(n)]


def build_tuck():
    """信纸装到信封底：轻轻一「嗒」（同整段 SLIDE 末尾）"""
    rng = random.Random(20261022)
    _, burst, _, _, _ = make(rng)
    track = [0.0] * int(RATE * 0.2)
    add(track, 0.0, burst(0.06, 0.012, "bandpass", 700, 0.8), 0.18)
    return finish(track)


def build_flap():
    """封舌合上：「啪」（同整段 FLAP 末尾）"""
    rng = random.Random(20261024)
    _, burst, tone, _, _ = make(rng)
    track = [0.0] * int(RATE * 0.25)
    add(track, 0.0, burst(0.06, 0.010, "bandpass", 900, 0.7), 0.30)
    add(track, 0.0, tone(0.05, 160, 0.012), 0.10)
    return finish(track)


def build_settle():
    """没推到就松手：信落回桌上，软软的「噗」，一点纸声"""
    rng = random.Random(20261023)
    _, burst, _, rustle, _ = make(rng)
    track = [0.0] * int(RATE * 0.45)
    add(track, 0.0, burst(0.08, 0.02, "lowpass", 700, 0.7), 0.30)
    add(track, 0.01, rustle(0.01, 0.2, lambda u: (1 - u) ** 1.5, 900, 4500, 35, 0.5), 0.06)
    return finish(track)


sounds_dir = os.path.join(os.path.dirname(__file__), "..", "Memoir", "Resources", "Sounds")
os.makedirs(sounds_dir, exist_ok=True)
tracks = {"sealed": build(True), "plain": build(False)}
# 两份共用一个增益，响度一致；和拆信的音效同一个峰值。
# 🔴 增益钉死在 2026-10-20 之前的值：原来的峰值是投信最后那一下铁皮声，换成「落信」后峰值变低，
# 再按峰值归一会把所有声音（连戳邮筒的「哐」）整体调响 13%。钉住之后「哐」一字节不变，投信整体也不变
peak = max(abs(v) for t in tracks.values() for v in t) or 1.0
gain = 0.45 / 0.4937587726552537
assert peak * gain <= 0.46, f"峰值超了：{peak * gain:.3f}"
fade = int(0.02 * RATE)


def write(track, filename, fade_out=True):
    if fade_out:
        for i in range(fade):
            track[len(track) - 1 - i] *= i / fade
    path = os.path.join(sounds_dir, filename)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * gain)) * 32767)) for v in track))
    print(f"写好了：{os.path.normpath(path)}（{len(track) / RATE:.2f}s）")


for name, track in tracks.items():
    write(track, f"letter_post_{name}.wav")
# 戳邮筒、推信那一路都用投信那两份的音量（不单独归一），几样声音之间的轻重是按这个配的
write(build_poke(), "mailbox_poke.wav")
write(build_pick_up(), "letter_pick_up.wav")
# 循环那段首尾已经接好，结尾不能再淡出（不然每轮结尾一空）
write(build_lift_loop(), "letter_lift_loop.wav", fade_out=False)
write(build_tuck(), "letter_tuck.wav")
write(build_flap(), "letter_flap.wav")
# 推着寄的后半截：整段从 TAIL 切开，头上 5 毫秒淡入（切口不「咔」）
for name, track in tracks.items():
    tail = track[int(TAIL * RATE):]
    ramp = int(0.005 * RATE)
    tail = [v * min(1, i / ramp) for i, v in enumerate(tail)]
    write(tail, f"letter_post_tail_{name}.wav")
write(build_settle(), "letter_settle.wav")
