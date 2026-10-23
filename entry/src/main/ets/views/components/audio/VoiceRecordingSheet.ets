/**
 * 录音面板（10_BUILD_MANUAL.md 2.7）。对应 iOS `VoiceRecordingSheet.swift`：
 * bindSheet MEDIUM 弹出，状态机 idle → recording → recorded，
 * 大圆钮（录：红底白方块 / 录完：播放试听）、脉冲红圈、1s 计时（180s 自动停）、
 * 「重录 + 插入」两键、插完落盘回调相对路径。
 *
 * - 录制走 `AudioRecorderManager`（临时文件在 cacheDir，「插入」才拷进 filesDir/audio）
 * - 权限由页面在开面板前申请好；被拒时页面仍开面板 → 本组件渲染
 *   「无法访问麦克风」引导态（去系统设置 + 取消），对应 iOS `requestRecordingPermission`
 * - 「插入」失败（落盘失败）显示错误文案，面板不关（iOS 同款只 dismiss 成功路径）
 */
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import {
  AUDIO_MAX_DURATION_SECONDS,
  AudioRecorderManager
} from '../../../services/AudioRecorderManager';

/** 录音中主圆钮 / 脉冲圈的红（iOS `Color.red`） */
const RECORDING_RED: string = '#FFE03E3E';

@Component
export struct VoiceRecordingSheet {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  /** 麦克风权限被拒（页面申请失败仍开面板 = 引导去系统设置） */
  micDenied: boolean = false;
  /** 插入（参数 = 落库后的相对路径 "audio/xxx.m4a"；落盘由本组件完成） */
  onInsert: (relativePath: string) => void = (_relativePath: string): void => {};
  /** 取消（本组件自己 reset 临时文件，页面只管关 sheet） */
  onCancel: () => void = (): void => {};

  @State private recording: boolean = false;
  /** 录好还没插（recordedPath 有值） */
  @State private recorded: boolean = false;
  /** 面板内试听中 */
  @State private panelPlaying: boolean = false;
  @State private elapsedSeconds: number = 0;
  /** 试听进度 0..1 */
  @State private playbackProgress: number = 0;
  /** 脉冲动画开关（animateTo iterations:-1 Alternate 驱动） */
  @State private pulse: boolean = false;
  /** 录音起不来 / 落盘失败（错误文案，destructive 色） */
  @State private failed: boolean = false;

  private recorder: AudioRecorderManager = new AudioRecorderManager();
  private timerId: number = -1;

  aboutToDisappear(): void {
    this.clearTimer();
    this.recorder.reset();
  }

  build() {
    Column() {
      if (this.micDenied) {
        this.permissionDeniedContent()
      } else {
        this.recorderContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }

  // ---- 录音主面板（iOS 同布局：标题 / 大圆钮 / 计时 / 进度 / 状态 / 底部按钮） ----

  @Builder
  private recorderContent() {
    Column({ space: 24 }) {
      Blank()

      Text($r('app.string.s_3ba60ad590'))
        .fontSize(18)
        .fontFamily(this.theme.headingFont.family)
        .fontColor(this.theme.textPrimary)

      this.recordButton()

      Text(this.formatTime(this.elapsedSeconds))
        .fontSize(18)
        .fontFamily(this.theme.headingFont.family)
        .fontColor(this.theme.textPrimary)

      // 录音进度条（1s 计时驱动；3 分钟封顶）
      if (this.recording) {
        Column({ space: 4 }) {
          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width('100%')
              .height(4)
              .borderRadius(2)
              .backgroundColor(this.theme.border)
            Row()
              .width(`${Math.min(this.elapsedSeconds / AUDIO_MAX_DURATION_SECONDS, 1) * 100}%`)
              .height(4)
              .borderRadius(2)
              .backgroundColor(RECORDING_RED)
          }
          .width('100%')
          .padding({ left: 40, right: 40 })
          Text($r('app.string.s_226a655b92'))
            .fontSize(10)
            .fontColor(this.theme.textTertiary)
        }
        .padding({ left: 40, right: 40 })
        .width('100%')
      }

      // 试听进度条（录完未插时）
      if (!this.recording && this.recorded) {
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%')
            .height(4)
            .borderRadius(2)
            .backgroundColor(this.theme.border)
          Row()
            .width(`${Math.round(this.playbackProgress * 100)}%`)
            .height(4)
            .borderRadius(2)
            .backgroundColor(this.theme.accent)
        }
        .width('100%')
        .padding({ left: 40, right: 40 })
      }

      Text(this.statusText())
        .fontSize(12)
        .fontColor(this.theme.textTertiary)

      if (this.failed) {
        Text($r('app.string.s_094be81a60'))
          .fontSize(12)
          .fontColor(this.theme.destructive)
      }

      Blank()

      // 底部按钮：录完 = 重录 + 插入；未录 / 录制中 = 取消
      Row({ space: 16 }) {
        if (this.recorded && !this.recording) {
          Text($r('app.string.s_6f69dd45f8'))
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 14, bottom: 14 })
            .borderRadius(12)
            .backgroundColor(this.theme.surfaceBackground)
            .onClick((): void => {
              this.resetSession();
            })
          Text($r('app.string.s_022bf3283d'))
            .fontSize(14)
            .fontColor(Color.White)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 14, bottom: 14 })
            .borderRadius(12)
            .backgroundColor(this.theme.accent)
            .onClick((): void => {
              this.insertRecording();
            })
        } else {
          Text($r('app.string.s_4d0b4688c7'))
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 14, bottom: 14 })
            .borderRadius(12)
            .backgroundColor(this.theme.surfaceBackground)
            .onClick((): void => {
              this.cancelSession();
            })
        }
      }
      .padding({ left: 20, right: 20, bottom: 20 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  /** 大圆钮：脉冲红圈（录制中）+ 64 主圆（白方块 / 播放 / 红点三态） */
  @Builder
  private recordButton() {
    Stack() {
      if (this.recording) {
        // 外圈 120：脉冲放大淡出
        Circle()
          .width(120)
          .height(120)
          .fill(this.pulse ? '#00E03E3E' : '#26E03E3E')
          .scale({ x: this.pulse ? 1.3 : 1, y: this.pulse ? 1.3 : 1 })
          .animation({ duration: 800, curve: Curve.EaseInOut })
        // 内圈 88
        Circle()
          .width(88)
          .height(88)
          .fill(this.pulse ? '#26E03E3E' : '#4DE03E3E')
          .scale({ x: this.pulse ? 1.1 : 1, y: this.pulse ? 1.1 : 1 })
          .animation({ duration: 800, curve: Curve.EaseInOut })
      }
      Stack() {
        if (this.recording) {
          // 录制中：白方块（停止位）
          Column()
            .width(20)
            .height(20)
            .borderRadius(4)
            .backgroundColor(Color.White)
        } else if (this.recorded) {
          // 录完：试听播放 / 暂停
          SymbolGlyph(this.panelPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
            .fontSize(24)
            .fontColor([Color.White])
        } else {
          // 未录：白色小圆点
          Circle()
            .width(20)
            .height(20)
            .fill(Color.White)
        }
      }
      .width(64)
      .height(64)
      .borderRadius(32)
      .backgroundColor(this.recording ? RECORDING_RED : this.theme.accent)
      .onClick((): void => {
        if (this.recording) {
          this.stopRecording();
        } else if (this.recorded) {
          this.togglePanelPlayback();
        } else {
          this.startRecording();
        }
      })
    }
  }

  // ---- 权限被拒引导态（无法访问麦克风 + 去设置 + 取消） ----

  @Builder
  private permissionDeniedContent() {
    Column({ space: 14 }) {
      Blank()
      SymbolGlyph($r('sys.symbol.mic'))
        .fontSize(34)
        .fontColor([this.theme.textTertiary])
      Text($r('app.string.s_7126a0f54e'))
        .fontSize(16)
        .fontColor(this.theme.textPrimary)
      Text($r('app.string.microphone_permission_reason'))
        .fontSize(13)
        .fontColor(this.theme.textTertiary)
        .textAlign(TextAlign.Center)
        .padding({ left: 36, right: 36 })
      Blank()
      Text($r('app.string.s_1f2998c9c8'))
        .fontSize(14)
        .fontColor(Color.White)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 14, bottom: 14 })
        .borderRadius(12)
        .backgroundColor(this.theme.accent)
        .onClick((): void => {
          this.openAppSettings();
        })
      Text($r('app.string.s_4d0b4688c7'))
        .fontSize(14)
        .fontColor(this.theme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 14, bottom: 14 })
        .onClick((): void => {
          this.cancelSession();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, bottom: 20 })
  }

  // ---- 录音状态机 ----

  private startRecording(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.failed = false;
    this.elapsedSeconds = 0;
    this.recorder.startRecording(context.cacheDir).then((ok: boolean): void => {
      if (!ok) {
        this.failed = true;
        return;
      }
      this.recording = true;
      this.startPulse();
      this.clearTimer();
      this.timerId = setInterval((): void => {
        this.elapsedSeconds++;
        if (this.elapsedSeconds >= AUDIO_MAX_DURATION_SECONDS) {
          this.stopRecording(); // 3 分钟自动停（iOS 面板计时器同款）
        }
      }, 1000);
    });
  }

  private stopRecording(): void {
    this.clearTimer();
    this.stopPulse();
    this.recorder.stopRecording().then((): void => {
      this.recording = false;
      this.recorded = this.recorder.recordedPath !== undefined;
    });
  }

  /** 面板内试听（临时文件） */
  private togglePanelPlayback(): void {
    if (this.panelPlaying) {
      this.recorder.stopPlayback();
      this.panelPlaying = false;
      return;
    }
    this.recorder.startPlayback((progress: number): void => {
      this.playbackProgress = progress;
    }, (): void => {
      this.panelPlaying = false;
      this.playbackProgress = 0;
    }).then((ok: boolean): void => {
      if (ok) {
        this.panelPlaying = true;
      }
    });
  }

  /** 「重录」：清临时文件回未录态 */
  private resetSession(): void {
    this.clearTimer();
    this.stopPulse();
    this.recorder.reset();
    this.recording = false;
    this.recorded = false;
    this.panelPlaying = false;
    this.playbackProgress = 0;
    this.elapsedSeconds = 0;
    this.failed = false;
  }

  /** 「插入」：临时文件拷进 filesDir/audio → 回调相对路径（失败不关面板） */
  private insertRecording(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.clearTimer();
    this.recorder.stopPlayback();
    this.panelPlaying = false;
    const path = this.recorder.saveRecording(context.filesDir);
    if (path === undefined) {
      this.failed = true;
      return;
    }
    this.recorder.reset();
    this.onInsert(path);
  }

  /** 「取消」：清临时文件，页面关 sheet */
  private cancelSession(): void {
    this.resetSession();
    this.onCancel();
  }

  private statusText(): Resource {
    if (this.recording) {
      return $r('app.string.s_421efbce02');
    }
    if (this.recorded) {
      return this.panelPlaying ? $r('app.string.s_5f7e5d5768') : $r('app.string.s_997b9c5847');
    }
    return $r('app.string.s_3d39e30c5a');
  }

  // ---- 动画 / 计时 / 设置跳转 ----

  private startPulse(): void {
    this.getUIContext().animateTo({
      duration: 800,
      iterations: -1,
      playMode: PlayMode.Alternate,
      curve: Curve.EaseInOut
    }, (): void => {
      this.pulse = true;
    });
  }

  private stopPulse(): void {
    this.getUIContext().animateTo({ duration: 0 }, (): void => {
      this.pulse = false;
    });
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /** 「去设置」：跳系统设置的本应用信息页（application_info_entry） */
  private openAppSettings(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo): void => {
        const want: Want = {
          bundleName: 'com.huawei.hmos.settings',
          abilityName: 'com.huawei.hmos.settings.MainAbility',
          uri: `application_info_entry/${info.name}`
        };
        context.startAbility(want).catch((): void => {
          // 跳转失败（极端场景）：留在引导态
        });
      }).catch((): void => {
        // 取不到包信息：留在引导态
      });
  }

  /** 「mm:ss」（补零，iOS `%02d:%02d` 同款） */
  private formatTime(totalSeconds: number): string {
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes < 10 ? '0' : ''}${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }
}
