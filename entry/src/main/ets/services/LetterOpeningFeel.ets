/**
 * 拆火漆信的手感：跟着三步拆信编排的震动 + 拆信的纸声（10_BUILD_MANUAL.md 5.7）。
 * 对应 iOS `Views/PostBox/Envelope/LetterOpeningFeel.swift`。
 *
 * - 编排本体在纯逻辑层 `LetterOpeningHapticPattern`（单测钉死），这里只做
 *   「事件表 → 系统编排」的转译和缓存；时间轴在 `LetterOpeningTimeline`
 * - 声音：SoundPool 预载 rawfile 里的三条拆信 wav（和 iOS 共用同一份文件，
 *   md5 一致），STREAM_USAGE_AUDIOBOOK 混音用法，不打断用户在放的音乐
 * - 「减弱动态效果」：鸿蒙没有对应系统设置 / 查询 API（平台偏差，见
 *   PROGRESS.md 5.7），只有 `playQuiet()` 供后续接入
 * - 全部 try/catch 静默：手感是锦上添花，任何一步失败不影响拆信本身
 */
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { vibrator } from '@kit.SensorServiceKit';
import { resourceManager } from '@kit.LocalizationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LetterOpeningHapticPattern } from '../models/LetterOpeningHapticPattern';
import { LetterOpeningTimeline } from '../models/LetterOpeningTimeline';
import { HapticPatternEvent, HapticEventKind } from '../models/PostingHapticPattern';

const DOMAIN: number = 0x0000;
const TAG: string = 'LetterOpeningFeel';

/** 「减弱动态效果」下的轻轻一顿（iOS playQuiet: tap 0.45 / 0.2） */
const QUIET_MS: number = 14;

export class LetterOpeningFeel {
  private pool: media.SoundPool | null = null;
  private soundIds: number[] = [-1, -1, -1];
  private preparing: Promise<void> | null = null;
  private patterns: (vibrator.VibratorPattern | null)[] = [null, null, null];
  /** 编排构建就抛（老设备）：别再试，全走退路拍子 */
  private patternBroken: boolean = false;
  /** 退路拍子：每步纯时长脉冲踩起点（设备不支持编排时用），[步, 时长 ms] */
  private legacyMarks: number[][] = [
    [0, 40], [1, 90], [2, 120]
  ];
  /** 已经碰过马达（编排/拍子在震或排着）：没碰过就别发 stop——空 stop 和
   * 紧跟的 start 会在驱动层撞车（14600101） */
  private vibrating: boolean = false;
  /** 有 stop 还没在驱动层落地：这期间的 start 要等它落地再发 */
  private stopping: Promise<void> | null = null;
  private attribute: vibrator.VibrateAttribute = { id: 0, usage: 'touch' };

  /**
   * 预载三条拆信声（读信页出现时调一次；失败静默——顶多没声）。
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
    const pool = await media.createSoundPool(3, info);
    this.pool = pool;
    for (let stage = 0; stage < LetterOpeningTimeline.STAGE_COUNT; stage++) {
      const fd: resourceManager.RawFileDescriptor =
        await rm.getRawFd(`sounds/letter_open_${stage + 1}.wav`);
      this.soundIds[stage] = await pool.load(fd.fd, fd.offset, fd.length);
    }
  }

  /** 拆一步（stage 0 火漆 / 1 封舌 / 2 信纸）：放这一步的纸声 + 打震动编排 */
  play(stage: number): void {
    if (stage < 0 || stage >= LetterOpeningTimeline.STAGE_COUNT) {
      return;
    }
    this.stop();
    if (this.pool !== null && this.soundIds[stage] >= 0) {
      this.pool.play(this.soundIds[stage]).catch((_e: BusinessError) => {
        // 静默：设备忙不过来就这一步没声
      });
    }
    if (this.stopping !== null) {
      // 前一发 stop 还没落地：start 等 stop 落地再发，否则驱动层报忙（14600101）
      const wait = this.stopping;
      wait.then(() => {
        this.launchHaptic(stage);
      }).catch(() => {
        this.launchHaptic(stage);
      });
      return;
    }
    this.launchHaptic(stage);
  }

  /** 「减弱动态效果」下：没有拆信过程，只在信纸出现时轻轻一顿（不放声音） */
  playQuiet(): void {
    this.buzz(QUIET_MS);
  }

  /** 停掉还在排 / 还在震的（连续点下一步前先清场） */
  stop(): void {
    if (!this.vibrating) {
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

  /** 页面销毁时释放（SoundPool 不释放会占着解码器）。不打断正在震的 */
  release(): void {
    if (this.pool !== null) {
      const pool = this.pool;
      this.pool = null;
      this.soundIds = [-1, -1, -1];
      this.preparing = null;
      pool.release().catch((_e: BusinessError) => {
        // 静默：释放失败随它去，页面都没了
      });
    }
  }

  /** 发编排（或退路拍子）：从 play 拆出来，等 stop 落地后再调用的那条路也走这里 */
  private launchHaptic(stage: number): void {
    const pattern = this.patternFor(stage);
    if (pattern !== null) {
      try {
        const effect: vibrator.VibrateFromPattern = { type: 'pattern', pattern: pattern };
        vibrator.startVibration(effect, this.attribute).then(() => {
          this.vibrating = true;
        }).catch((e: BusinessError) => {
          // 801（不支持）/ 14600101（设备忙）：退回老拍子，总得有震
          hilog.warn(DOMAIN, TAG, 'pattern start failed, stage=%{public}d code=%{public}d, fall back to marks',
            stage, e.code);
          this.playLegacyMarks(stage);
        });
        return;
      } catch (e) {
        const err = e as BusinessError;
        hilog.warn(DOMAIN, TAG, 'pattern start threw, stage=%{public}d code=%{public}d, fall back to marks',
          stage, err.code);
      }
    }
    this.playLegacyMarks(stage);
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
  private patternFor(stage: number): vibrator.VibratorPattern | null {
    if (this.patternBroken) {
      return null;
    }
    const cached = this.patterns[stage];
    if (cached !== null) {
      return cached;
    }
    try {
      const pattern = LetterOpeningFeel.buildPattern(LetterOpeningHapticPattern.build(stage));
      this.patterns[stage] = pattern;
      return pattern;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'pattern build failed, stage=%{public}d code=%{public}d, use legacy marks',
        stage, err.code);
      this.patternBroken = true;
      return null;
    }
  }

  /** 退路拍子：一步一记纯时长脉冲（旧设备保底；时长随步的长短配） */
  private playLegacyMarks(stage: number): void {
    const mark = this.legacyMarks[stage];
    if (mark === undefined) {
      return;
    }
    this.buzz(mark[1]);
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
