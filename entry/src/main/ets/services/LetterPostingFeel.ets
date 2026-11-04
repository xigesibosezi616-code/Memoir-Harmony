/**
 * 投信的手感：跟着动画节点编排的震动 + 投信的封口声（10_BUILD_MANUAL.md 5.6）。
 * 对应 iOS `Views/PostBox/Posting/LetterPostingFeel.swift`。
 *
 * - 震动：鸿蒙的 CoreHaptics 等价物是 `VibratorPatternBuilder`
 *   （VibrateFromPattern，API 18+）——transient 点打 + continuous 持续段 +
 *   points 强度曲线。编排本体在纯逻辑层 `PostingHapticPattern`（单测钉死），
 *   这里只做「事件表 → 系统编排」的转译和缓存。设备不支持（801）/ 忙
 *   （14600101）时退回纯时长脉冲的拍子（VibrateTime）——有一下没一下
 *   总比没有强，且任何一步失败都不影响投信本身
 * - 声音：SoundPool 预载 rawfile 里的两条 wav（生成脚本和 iOS 共用，
 *   `Scripts/make_post_sound.py`），STREAM_USAGE_AUDIOBOOK 是混音用法，
 *   不会把用户正在听的音乐打断
 * - 全部 try/catch 静默：手感是锦上添花
 */
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { vibrator } from '@kit.SensorServiceKit';
import { resourceManager } from '@kit.LocalizationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PostingHapticPattern, HapticEventKind, HapticPatternEvent } from '../models/PostingHapticPattern';

const DOMAIN: number = 0x0000;
const TAG: string = 'PostingFeel';

/** 退路：纯时长脉冲踩动画节点（设备不支持编排时用），[动画秒, 时长 ms] */
const PLAIN_MARKS: number[][] = [
  [0.02, 14], [0.09, 12], [0.17, 10],
  [0.92, 18],
  [1.40, 26],
  [1.60, 22],
  [2.45, 16],
  [2.90, 90]
];

/** 盖火漆的那一下更重、更晚（压在封舌合上之后） */
const SEALED_MARKS: number[][] = [
  [0.02, 14], [0.09, 12], [0.17, 10],
  [0.92, 18],
  [1.40, 26],
  [1.70, 55],
  [2.45, 16],
  [2.90, 90]
];

/** 点邮筒确认震的退路：纯时长脉冲（编排这条路走不通时用） */
const TAP_FALLBACK_MS: number = 40;

export class LetterPostingFeel {
  private pool: media.SoundPool | null = null;
  private plainSoundId: number = -1;
  private sealedSoundId: number = -1;
  private timers: number[] = [];
  private preparing: Promise<void> | null = null;
  private plainPattern: vibrator.VibratorPattern | null = null;
  private sealedPattern: vibrator.VibratorPattern | null = null;
  /** 编排构建就抛（老设备）：别再试，全走退路拍子 */
  private patternBroken: boolean = false;
  /** 已经碰过马达（编排/拍子在震或排着）：没碰过就别发 stop——空 stop 和紧跟的 start 会在驱动层撞车（14600101） */
  private vibrating: boolean = false;
  /** 有 stop 还没在驱动层落地：这期间的 start 要等它落地再发 */
  private stopping: Promise<void> | null = null;
  private attribute: vibrator.VibrateAttribute = { id: 0, usage: 'touch' };

  /**
   * 预载声音（页面出现时调一次；失败静默——顶多没声，不影响投信）。
   * 重复调用安全：同一份只预备一次。
   */
  prepare(rm: resourceManager.ResourceManager): Promise<void> {
    if (this.preparing !== null) {
      return this.preparing;
    }
    const task = this.doPrepare(rm).catch((_e: BusinessError) => {
      // 静默：预载失败只是没声，下次进来再试
      this.preparing = null;
    });
    this.preparing = task;
    return task;
  }

  private async doPrepare(rm: resourceManager.ResourceManager): Promise<void> {
    const info: audio.AudioRendererInfo = {
      usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
      rendererFlags: 0
    };
    const pool = await media.createSoundPool(2, info);
    this.pool = pool;
    const plainFd: resourceManager.RawFileDescriptor = await rm.getRawFd('sounds/letter_post_plain.wav');
    this.plainSoundId = await pool.load(plainFd.fd, plainFd.offset, plainFd.length);
    const sealedFd: resourceManager.RawFileDescriptor = await rm.getRawFd('sounds/letter_post_sealed.wav');
    this.sealedSoundId = await pool.load(sealedFd.fd, sealedFd.offset, sealedFd.length);
  }

  /** 投信开始：放封口声 + 打震动编排（sealed = 盖了火漆的重版） */
  play(sealed: boolean): void {
    this.cancel();
    const soundId = sealed ? this.sealedSoundId : this.plainSoundId;
    if (this.pool !== null && soundId >= 0) {
      this.pool.play(soundId).catch((_e: BusinessError) => {
        // 静默：设备忙不过来就这一封没声
      });
    }
    if (this.stopping !== null) {
      // 前一发 stop 还没落地：start 等 stop 落地再发，否则驱动层报忙（14600101）
      const wait = this.stopping;
      wait.then(() => {
        this.launchHaptic(sealed);
      }).catch(() => {
        this.launchHaptic(sealed);
      });
      return;
    }
    this.launchHaptic(sealed);
  }

  /** 发编排（或退路拍子）：从 play 拆出来，等 stop 落地后再调用的那条路也走这里 */
  private launchHaptic(sealed: boolean): void {
    const pattern = this.patternFor(sealed);
    if (pattern !== null) {
      try {
        const effect: vibrator.VibrateFromPattern = { type: 'pattern', pattern: pattern };
        vibrator.startVibration(effect, this.attribute).then(() => {
          this.vibrating = true;
        }).catch((e: BusinessError) => {
          // 801（不支持）/ 14600101（设备忙）：退回老拍子，总得有震
          hilog.warn(DOMAIN, TAG, 'pattern start failed, code=%{public}d, fall back to marks', e.code);
          this.playLegacyMarks(sealed);
        });
        return;
      } catch (e) {
        const err = e as BusinessError;
        hilog.warn(DOMAIN, TAG, 'pattern start threw, code=%{public}d, fall back to marks', err.code);
      }
    }
    this.playLegacyMarks(sealed);
  }

  /**
   * 点邮筒那一下的确认震：一记扎实的中低频敲击（真机反馈「点击邮筒震感弱」——
   * 投信编排要等异步落库后才起，手指点下要立刻有回音）。
   * 拒收（没勾日记 / 不在 Ready）同用这一记：原因在状态行里写着，
   * 触感不再分轻重（原拒收轻震 35/25 并入；连点忽略不震）。
   */
  playMailboxTap(): void {
    // 同步置位：紧随其后的 play()→cancel() 才能正确 stop / 排队（等 stop 落地再起编排）
    this.vibrating = true;
    try {
      const builder = new vibrator.VibratorPatternBuilder();
      const param: vibrator.TransientParam = { intensity: 80, frequency: 30 };
      builder.addTransientEvent(0, param);
      const effect: vibrator.VibrateFromPattern = { type: 'pattern', pattern: builder.build() };
      vibrator.startVibration(effect, this.attribute).catch((_e: BusinessError) => {
        this.buzz(TAP_FALLBACK_MS);
      });
      return;
    } catch (_e) {
      // 静默：编排这条路走不通就退回纯时长
    }
    this.buzz(TAP_FALLBACK_MS);
  }

  /** 停掉还在排 / 还在震的（动画被打断时用；编排和退路拍子都停） */
  cancel(): void {
    this.clearTimers();
    if (!this.vibrating) {
      // 没碰过马达就别发 stop：空 stop 和紧随的 start 会在驱动层撞出 14600101
      return;
    }
    this.vibrating = false;
    try {
      // 无参版停所有模式的振动（含 pattern；没在震就是空操作）
      const stop = vibrator.stopVibration();
      this.stopping = stop.then(() => {
        this.stopping = null;
      }).catch(() => {
        this.stopping = null;
      });
    } catch (_e) {
      // 静默
      this.stopping = null;
    }
  }

  private clearTimers(): void {
    for (const id of this.timers) {
      clearTimeout(id);
    }
    this.timers = [];
  }

  /** 页面销毁时释放（SoundPool 不释放会占着解码器） */
  release(): void {
    this.cancel();
    if (this.pool !== null) {
      const pool = this.pool;
      this.pool = null;
      this.plainSoundId = -1;
      this.sealedSoundId = -1;
      this.preparing = null;
      pool.release().catch((_e: BusinessError) => {
        // 静默：释放失败随它去，页面都没了
      });
    }
  }

  /** 事件表 → 系统编排（一次构建，缓存复用；抛异常由调用方兜底） */
  private static buildPattern(events: HapticPatternEvent[]): vibrator.VibratorPattern {
    const builder = new vibrator.VibratorPatternBuilder();
    for (const event of events) {
      if (event.kind === HapticEventKind.TRANSIENT) {
        const param: vibrator.TransientParam = { intensity: event.intensity, frequency: event.frequency };
        builder.addTransientEvent(event.time, param);
      } else if (event.points.length > 0) {
        const curve: vibrator.VibratorCurvePoint[] = [];
        for (const point of event.points) {
          curve.push({ time: point.time, intensity: point.intensity, frequency: point.frequency });
        }
        const param: vibrator.ContinuousParam = {
          intensity: event.intensity,
          frequency: event.frequency,
          points: curve
        };
        builder.addContinuousEvent(event.time, event.duration, param);
      } else {
        const param: vibrator.ContinuousParam = { intensity: event.intensity, frequency: event.frequency };
        builder.addContinuousEvent(event.time, event.duration, param);
      }
    }
    return builder.build();
  }

  /** 拿编排（缓存；老设备构建失败一次后不再试，全走退路） */
  private patternFor(sealed: boolean): vibrator.VibratorPattern | null {
    if (this.patternBroken) {
      return null;
    }
    const cached = sealed ? this.sealedPattern : this.plainPattern;
    if (cached !== null) {
      return cached;
    }
    try {
      const pattern = LetterPostingFeel.buildPattern(PostingHapticPattern.build(sealed));
      if (sealed) {
        this.sealedPattern = pattern;
      } else {
        this.plainPattern = pattern;
      }
      return pattern;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'pattern build failed, code=%{public}d, use legacy marks', err.code);
      this.patternBroken = true;
      return null;
    }
  }

  /** 退路拍子：纯时长脉冲按节点打（旧实现，设备不支持编排时保底） */
  private playLegacyMarks(sealed: boolean): void {
    const marks = sealed ? SEALED_MARKS : PLAIN_MARKS;
    this.vibrating = true;
    for (const mark of marks) {
      const atSec = mark[0];
      const durationMs = mark[1];
      const id = setTimeout(() => {
        this.buzz(durationMs);
      }, atSec * 1000);
      this.timers.push(id);
    }
  }

  private buzz(durationMs: number): void {
    this.vibrating = true;
    try {
      const effect: vibrator.VibrateTime = { type: 'time', duration: durationMs };
      vibrator.startVibration(effect, this.attribute).catch((_e: BusinessError) => {
        // 静默：设备忙（14600101）之类的错过就错过
      });
    } catch (_e) {
      // 静默：参数不对顶多这一下没了
    }
  }
}
