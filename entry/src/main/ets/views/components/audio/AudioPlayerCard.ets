/**
 * 正文里的录音锚点卡（10_BUILD_MANUAL.md 2.7）：builder span 的内容。
 * 对应 iOS `AudioPlayerCard` + `AudioOverlayView`（armed = tint 60% 边框 radius 10）。
 *
 * 布局对齐 iOS：36 播放圆钮 + 3 进度条 + 10fp 时长，卡片 padding 12、
 * radius 10、surfaceBackground；编辑态多一枚 ✕（直接删，无确认，iOS xmark 同款；
 * 详情页不给 onDelete = 纯试听卡）。
 *
 * 播放走内部 `AudioMemoPlayer`（aboutToDisappear 全释放）；未播放时
 * `probeAudioDurationMs` 探时长显示「m:ss」，播放失败 toast。
 */
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { ContentBlock, ContentBlockType } from '../../../models/ContentBlock';
import { AudioMemoPlayer, probeAudioDurationMs } from '../../../services/AudioRecorderManager';

@Component
export struct AudioPlayerCard {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  /** 退格第一次选中态（R-RICH-05：accent 边框高亮，iOS `isArmed` 同款） */
  @Prop armed: boolean = false;
  /** 录音块本体（更新 = 删旧 span 重插新卡，不做增量响应） */
  block: ContentBlock = new ContentBlock('', ContentBlockType.Audio);
  /** ✕ 删除（编辑态给；详情页不给 = 纯试听卡） */
  onDelete: ((blockId: string) => void) | undefined = undefined;

  @State private playing: boolean = false;
  /** 播放进度 0..1（驱动进度条） */
  @State private progress: number = 0;
  /** 总时长秒（探不到 0 → 占位 0:00） */
  @State private durationSeconds: number = 0;

  private player: AudioMemoPlayer | undefined = undefined;

  aboutToAppear(): void {
    this.probeDuration();
  }

  aboutToDisappear(): void {
    this.stopPlayback();
  }

  build() {
    Row({ space: 10 }) {
      // 播放 / 暂停圆钮（36vp，iOS 同款）。
      // ⚠️ Block 必须与手势同节点：RichEditor 的光标 / 选词手势会赢下手势仲裁
      // （照片卡真机实测同款结论）；Block 放根 Row 会阻塞子节点触摸测试，
      // 播放 / ✕ 全部收不到事件（真机 Touch test result is empty 实测回归）
      Stack() {
        SymbolGlyph(this.playing ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
          .fontSize(15)
          .fontColor([Color.White])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.theme.accent)
      .hitTestBehavior(HitTestMode.Block)
      .gesture(
        TapGesture({ count: 1 })
          .onAction((): void => {
            this.togglePlayback();
          })
      )

      // 进度条（3vp）+ 时长（10fp）
      Column({ space: 5 }) {
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%')
            .height(3)
            .borderRadius(1.5)
            .backgroundColor(this.theme.textTertiary)
            .opacity(0.3)
          Row()
            .width(`${Math.round(this.progress * 100)}%`)
            .height(3)
            .borderRadius(1.5)
            .backgroundColor(this.theme.accent)
        }
        .width('100%')
        Text(this.durationLabel())
          .fontSize(10)
          .fontColor(this.theme.textSecondary)
          .fontFamily(this.theme.labelFont.family)
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // ✕ 直接删（无确认，iOS xmark 同款）。Block 同节点，理由同播放钮
      if (this.onDelete !== undefined) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(13)
          .fontColor([this.theme.textTertiary])
          .padding(4)
          .hitTestBehavior(HitTestMode.Block)
          .gesture(
            TapGesture({ count: 1 })
              .onAction((): void => {
                this.stopPlayback();
                this.onDelete?.(this.block.id);
              })
          )
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .borderRadius(10)
    .backgroundColor(this.theme.surfaceBackground)
    .border(this.armed ? {
      width: 2,
      color: this.theme.accent,
      radius: 10
    } : { width: 0 })
  }

  /** 轻点圆钮：播 / 停（另起一个 AudioMemoPlayer，一次一个实例全释放） */
  private togglePlayback(): void {
    if (this.playing) {
      this.stopPlayback();
      return;
    }
    const context = this.getUIContext().getHostContext();
    const filename = this.block.audioFilename;
    if (context === undefined || filename === undefined) {
      this.reportPlaybackFailure();
      return;
    }
    const player = new AudioMemoPlayer();
    player.onTick = (p: number): void => {
      this.progress = p;
    };
    player.onFinished = (): void => {
      this.playing = false;
      this.progress = 0;
    };
    player.startRelative(context.filesDir, filename).then((ok: boolean): void => {
      if (!ok) {
        this.reportPlaybackFailure();
        return;
      }
      this.player = player;
      this.playing = true;
      if (player.durationMs > 0) {
        this.durationSeconds = Math.round(player.durationMs / 1000);
      }
    });
  }

  private stopPlayback(): void {
    if (this.player !== undefined) {
      this.player.stop();
      this.player = undefined;
    }
    this.playing = false;
    this.progress = 0;
  }

  /** 卡片未播放时探一次时长（iOS `duration(of:)` 同款） */
  private probeDuration(): void {
    const context = this.getUIContext().getHostContext();
    const filename = this.block.audioFilename;
    if (context === undefined || filename === undefined) {
      return;
    }
    probeAudioDurationMs(context.filesDir, filename).then((ms: number): void => {
      if (ms > 0) {
        this.durationSeconds = Math.round(ms / 1000);
      }
    });
  }

  /** 「m:ss」（时长未知占位 0:00，录完落盘的都有时长） */
  private durationLabel(): string {
    const total = Math.max(this.durationSeconds, 0);
    const minutes = Math.floor(total / 60);
    const seconds = total % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  private reportPlaybackFailure(): void {
    this.getUIContext().getPromptAction()
      .showToast({ message: $r('app.string.s_e4c4ff3b29') });
  }
}
