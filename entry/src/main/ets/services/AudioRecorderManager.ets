/**
 * 录音的录制 / 试听 / 落盘 / 删除（10_BUILD_MANUAL.md 2.7）。对应 iOS `Services/AudioRecorderManager.swift`。
 *
 * - 录制：`@kit.MediaKit` 的 AVRecorder，AAC-LC 44.1kHz 单声道 m4a
 *   （iOS AVAudioRecorder 同规格；码率 96000 近似 iOS AVAudioQuality.high），
 *   先写 cacheDir 临时文件，`saveRecording` 才拷进 filesDir/audio/
 * - 试听 / 正文卡片播放：AVPlayer（fd:// 打开，timeUpdate 出进度），
 *   一个实例一次播放，`stop()` 释放干净
 * - 最长 3 分钟（180s）：计时由录音面板自己掐（iOS VoiceRecordingSheet 的
 *   1s Timer 同款，到点调 stopRecording）
 * - 「无法开始录音 / 无法播放录音」等失败文案不在这层（要本地化），
 *   方法返回 boolean / 失败回调，UI 层映射成资源串
 */
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AUDIO_DIR_NAME, audioFilenameFor } from './MediaStorage';
import { generateUuid } from '../models/Uuid';

const DOMAIN = 0x0000;
const TAG = 'AudioRecorderManager';

/** 录音上限（秒）：3 分钟（R-ENTRY-08，iOS maxDuration 同款） */
export const AUDIO_MAX_DURATION_SECONDS: number = 180;

/** 相对路径（"audio/xxx.m4a"）→ filesDir/audio/ 下的绝对路径；裸名当 audio/ 下的文件名 */
export function audioAbsolutePath(filesDir: string, relativePath: string): string {
  const prefix = `${AUDIO_DIR_NAME}/`;
  const name = relativePath.startsWith(prefix) ? relativePath.substring(prefix.length) : relativePath;
  return `${filesDir}/${AUDIO_DIR_NAME}/${name}`;
}

/** 删除 filesDir/audio/ 下的一个录音文件（"audio/xxx.m4a" 或裸名）；成功返回 true */
export function deleteAudioFile(filesDir: string, relativePath: string): boolean {
  try {
    fileIo.unlinkSync(audioAbsolutePath(filesDir, relativePath));
    return true;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'deleteAudioFile failed: %{public}s %{public}s',
      relativePath, JSON.stringify(err));
    return false;
  }
}

/** 打开音频文件只读 fd（fd:// 播放用）；失败返回 undefined */
function openReadOnly(path: string): number | undefined {
  try {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    return file.fd;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'openSync failed: %{public}s %{public}s', path, JSON.stringify(err));
    return undefined;
  }
}

function closeFd(fd: number | undefined): void {
  if (fd === undefined) {
    return;
  }
  try {
    fileIo.closeSync(fd);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'closeSync failed: %{public}s', JSON.stringify(err));
  }
}

/**
 * 录音会话（一次「开始 → 停止 → 试听 → 插入」的生命周期）。
 * 临时文件在 cacheDir；`saveRecording` 拷进 filesDir/audio/ 才算落库。
 */
export class AudioRecorderManager {
  /** 正在录音 */
  isRecording: boolean = false;
  /** 录好的临时文件绝对路径（cacheDir 下）；没录 / 已重置 = undefined */
  recordedPath: string | undefined = undefined;

  private avRecorder: media.AVRecorder | undefined = undefined;
  private fileFd: number | undefined = undefined;
  private playback: AudioMemoPlayer | undefined = undefined;

  /** 开始录音（临时文件写 cacheDir）。权限由调用方先申请好；失败返回 false */
  async startRecording(cacheDir: string): Promise<boolean> {
    if (this.isRecording) {
      return true;
    }
    this.recordedPath = undefined;
    await this.discardTempFile();
    let recorder: media.AVRecorder | undefined = undefined;
    try {
      recorder = await media.createAVRecorder();
      recorder.on('error', (err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'AVRecorder error: %{public}d %{public}s', err.code, err.message);
      });
      const filename = `recording_${generateUuid()}.m4a`;
      const path = `${cacheDir}/${filename}`;
      const file = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      this.fileFd = file.fd;
      const profile: media.AVRecorderProfile = {
        audioBitrate: 96000,
        audioChannels: 1,
        audioCodec: media.CodecMimeType.AUDIO_AAC,
        audioSampleRate: 44100,
        fileFormat: media.ContainerFormatType.CFT_MPEG_4A
      };
      const config: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: profile,
        url: `fd://${file.fd}`
      };
      await recorder.prepare(config);
      await recorder.start();
      this.avRecorder = recorder;
      this.isRecording = true;
      this.recordedPath = path;
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'startRecording failed: %{public}s', JSON.stringify(err));
      if (this.fileFd !== undefined) {
        closeFd(this.fileFd);
        this.fileFd = undefined;
      }
      if (recorder !== undefined) {
        recorder.release().catch((): void => {});
      }
      this.avRecorder = undefined;
      await this.discardTempFile();
      return false;
    }
  }

  /** 停止录音（临时文件保留，等 saveRecording / 重置） */
  async stopRecording(): Promise<void> {
    if (!this.isRecording) {
      return;
    }
    this.isRecording = false;
    const recorder = this.avRecorder;
    this.avRecorder = undefined;
    if (recorder === undefined) {
      return;
    }
    try {
      await recorder.stop();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'AVRecorder stop failed: %{public}s', JSON.stringify(err));
    }
    try {
      await recorder.release();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'AVRecorder release failed: %{public}s', JSON.stringify(err));
    }
    closeFd(this.fileFd);
    this.fileFd = undefined;
  }

  /**
   * 把录好的临时文件拷进 filesDir/audio/（audio_<UUID>_<Unix 秒>.m4a），
   * 返回库里的相对路径 "audio/xxx.m4a"；没录 / 失败返回 undefined。
   */
  saveRecording(filesDir: string): string | undefined {
    const source = this.recordedPath;
    if (source === undefined) {
      return undefined;
    }
    const dir = `${filesDir}/${AUDIO_DIR_NAME}`;
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'ensure audio dir failed: %{public}s', JSON.stringify(err));
      try {
        fileIo.mkdirSync(dir, true);
      } catch (err2) {
        hilog.error(DOMAIN, TAG, 'mkdir audio dir failed: %{public}s', JSON.stringify(err2));
        return undefined;
      }
    }
    const filename = audioFilenameFor(generateUuid(), Math.floor(Date.now() / 1000));
    const dest = `${dir}/${filename}`;
    try {
      fileIo.copyFileSync(source, dest);
      return `${AUDIO_DIR_NAME}/${filename}`;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveRecording copy failed: %{public}s', JSON.stringify(err));
      return undefined;
    }
  }

  /** 重置（面板「重录 / 取消 / 关闭」用）：停录、停试听、删临时文件 */
  async reset(): Promise<void> {
    await this.stopRecording();
    this.stopPlayback();
    await this.discardTempFile();
  }

  // ---- 面板内试听（临时文件） ----

  /** 试听刚录的临时文件（返回 false = 播放器起不来） */
  async startPlayback(onTick: (progress: number) => void, onFinished: () => void): Promise<boolean> {
    const path = this.recordedPath;
    if (path === undefined) {
      return false;
    }
    this.stopPlayback();
    const player = new AudioMemoPlayer();
    player.onTick = onTick;
    player.onFinished = onFinished;
    this.playback = player;
    return player.start(path);
  }

  /** 停试听（不删临时文件） */
  stopPlayback(): void {
    if (this.playback !== undefined) {
      this.playback.stop();
      this.playback = undefined;
    }
  }

  /** 删临时文件（路径还在 recordings 里由调用方掌握；这里只清 cacheDir 半成品） */
  private async discardTempFile(): Promise<void> {
    const path = this.recordedPath;
    this.recordedPath = undefined;
    if (path === undefined) {
      return;
    }
    try {
      fileIo.unlinkSync(path);
    } catch (err) {
      // 临时文件本来就可能不存在（还没录就取消）：静默
    }
  }
}

/**
 * 单个音频的播放器（正文录音卡 / 探时长共用）：一个实例一次播放，
 * `stop()` 连 AVPlayer 带 fd 全释放。进度经 timeUpdate（100ms 一拍）回调。
 */
export class AudioMemoPlayer {
  /** 正在播放（prepared → play() 成功后置位） */
  isPlaying: boolean = false;
  /** 总时长（ms，prepared 后有效） */
  durationMs: number = 0;
  /** 进度回调（0..1） */
  onTick: (progress: number) => void = (_progress: number): void => {};
  /** 自然播完（completed）回调 */
  onFinished: () => void = (): void => {};

  private avPlayer: media.AVPlayer | undefined = undefined;
  private fileFd: number | undefined = undefined;

  /** 播放 filesDir/audio/ 下的相对路径（"audio/xxx.m4a" / 裸名） */
  async startRelative(filesDir: string, relativePath: string): Promise<boolean> {
    return this.start(audioAbsolutePath(filesDir, relativePath));
  }

  /** 播放绝对路径文件；返回 false = 打不开 / 起不来（调用方映射失败文案） */
  async start(absolutePath: string): Promise<boolean> {
    this.stop();
    const fd = openReadOnly(absolutePath);
    if (fd === undefined) {
      return false;
    }
    let player: media.AVPlayer | undefined = undefined;
    try {
      player = await media.createAVPlayer();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'createAVPlayer failed: %{public}s', JSON.stringify(err));
      closeFd(fd);
      return false;
    }
    this.fileFd = fd;
    this.avPlayer = player;
    const self = this;
    player.on('stateChange', (state: string): void => {
      self.handleState(state);
    });
    player.on('error', (err: BusinessError): void => {
      hilog.error(DOMAIN, TAG, 'AVPlayer error: %{public}d %{public}s', err.code, err.message);
      self.stop();
    });
    player.on('timeUpdate', (timeMs: number): void => {
      if (self.durationMs > 0) {
        self.onTick(Math.min(timeMs / self.durationMs, 1));
      }
    });
    try {
      player.url = `fd://${fd}`;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'set url failed: %{public}s', JSON.stringify(err));
      this.stop();
      return false;
    }
    return true; // prepared → play 在 stateChange 里接续；失败走 error → stop
  }

  /** 停止并释放（进度归零；可重复调用） */
  stop(): void {
    const player = this.avPlayer;
    this.avPlayer = undefined;
    this.isPlaying = false;
    this.durationMs = 0;
    closeFd(this.fileFd);
    this.fileFd = undefined;
    if (player === undefined) {
      return;
    }
    player.release().catch((err: Object): void => {
      hilog.error(DOMAIN, TAG, 'AVPlayer release failed: %{public}s', JSON.stringify(err));
    });
  }

  private handleState(state: string): void {
    const player = this.avPlayer;
    if (player === undefined) {
      return;
    }
    if (state === 'initialized') {
      player.prepare().catch((err: Object): void => {
        hilog.error(DOMAIN, TAG, 'prepare failed: %{public}s', JSON.stringify(err));
      });
      return;
    }
    if (state === 'prepared') {
      this.durationMs = player.duration > 0 ? player.duration : 0;
      player.play().then((): void => {
        this.isPlaying = true;
      }).catch((err: Object): void => {
        hilog.error(DOMAIN, TAG, 'play failed: %{public}s', JSON.stringify(err));
        this.stop();
      });
      return;
    }
    if (state === 'completed') {
      this.stop();
      this.onFinished();
    }
  }
}

/**
 * 探一个音频的时长（ms；正文录音卡未播放时显示总时长用，iOS `duration(of:)` 同款）。
 * 失败 / 读不到返回 0。AVPlayer 全流程（create → prepared → release）一锤子买卖。
 */
export async function probeAudioDurationMs(filesDir: string, relativePath: string): Promise<number> {
  const path = audioAbsolutePath(filesDir, relativePath);
  const fd = openReadOnly(path);
  if (fd === undefined) {
    return 0;
  }
  let player: media.AVPlayer | undefined = undefined;
  try {
    player = await media.createAVPlayer();
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'probe createAVPlayer failed: %{public}s', JSON.stringify(err));
    closeFd(fd);
    return 0;
  }
  const p = player;
  return await new Promise<number>((resolve: (value: number) => void): void => {
    let settled = false;
    const finish = (value: number): void => {
      if (settled) {
        return;
      }
      settled = true;
      closeFd(fd);
      resolve(value);
    };
    p.on('error', (): void => {
      p.release().catch((): void => {});
      finish(0);
    });
    p.on('stateChange', (state: string): void => {
      if (state === 'initialized') {
        p.prepare().catch((): void => {
          p.release().catch((): void => {});
          finish(0);
        });
      } else if (state === 'prepared') {
        const duration = p.duration > 0 ? p.duration : 0;
        p.release().then((): void => {
          finish(duration);
        }).catch((): void => {
          finish(duration);
        });
      }
    });
    try {
      p.url = `fd://${fd}`;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'probe set url failed: %{public}s', JSON.stringify(err));
      p.release().catch((): void => {});
      finish(0);
    }
  });
}
