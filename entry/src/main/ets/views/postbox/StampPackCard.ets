/**
 * 每周领邮票的小卡片（U01 2026-10-27，iOS `Views/PostBox/Posting/StampPackCard.swift`）。
 *
 * 进邮筒页时，新的一包到了、邮票夹又没满，就浮出这张卡片：三张叠着的齿孔邮票 +
 * 「这周的邮票到了」+「领取」。点领取 →「+N / 放进邮票夹了」停一下再淡出；
 * 点「稍后」先收起，下次进邮筒页再出来。
 *
 * 这只是个「收到了」的小仪式：寄信时服务端本来就会把到期的那一包补领上，
 * 用户不点也不会寄不出去。所以卡片上不写「必须领取」之类的话，「稍后」随时能关。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import {
  MarkScript,
  MARK_BOUNDS_W,
  MARK_BOUNDS_H,
  drawHandwrittenMark
} from '../splash/HandwrittenMark';

/** 卡片此刻的阶段（iOS StampPackCard.Phase） */
export enum StampPackPhase {
  /** 新的一包到了，等领取 */
  Ready = 0,
  /** 正在领 */
  Claiming = 1,
  /** 领到了（+N，稍后自动收起） */
  Claimed = 2
}

/** '#RRGGBB' + 透明度 → '#AARRGGBB'（齿孔 / 内框 / 票面的半透明都这样算） */
function withAlpha(hex: string, alpha01: number): string {
  const a = Math.round(Math.max(0, Math.min(1, alpha01)) * 255);
  const s = a.toString(16);
  return `#${s.length < 2 ? '0' : ''}${s}${hex.substring(1)}`;
}

/**
 * 尺素自己的邮票：齿孔边 + 内框，票面是手写的 m.（桌面图标同一笔）。**不印字**（用户定）。
 * 画法同 iOS `MarkStamp`：线宽、齿孔间距、内框留白都跟着宽度一起缩。
 */
@Component
export struct MarkStamp {
  /** 票宽（vp）；高 = 宽 × 52/44（iOS 同款比例） */
  widthVp: number = 44;
  /** 邮票的墨色（跟邮戳同一套） */
  ink: string = '#3D3428';
  /** 邮票的纸色（跟信纸同一套） */
  paper: string = '#F7F1E3';
  private ctx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));

  build() {
    Canvas(this.ctx)
      .width(this.widthVp)
      .height(this.widthVp * 52 / 44)
      .onReady((): void => {
        this.draw();
      })
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = this.widthVp;
    const h = w * 52 / 44;
    const k = w / 44;
    // 画布坐标对齐 vp（region 是 px）
    const scale = ctx.width / w;
    ctx.scale(scale, scale);
    // 纸底
    ctx.fillStyle = this.paper;
    ctx.fillRect(0, 0, w, h);
    // 齿孔虚线边（0.1 的短划 + 圆头 = 一圈圆点，像撕下来的齿孔）
    const dashLw = 2.2 * k;
    ctx.strokeStyle = withAlpha(this.ink, 0.55);
    ctx.lineWidth = dashLw;
    ctx.lineCap = 'round';
    ctx.setLineDash([0.1, 4.2 * k]);
    const dashInset = 1 * k + dashLw / 2;
    ctx.strokeRect(dashInset, dashInset, w - dashInset * 2, h - dashInset * 2);
    // 内框
    const frameLw = Math.max(0.5, 0.8 * k);
    ctx.strokeStyle = withAlpha(this.ink, 0.4);
    ctx.lineWidth = frameLw;
    ctx.setLineDash([]);
    const frameInset = 6 * k + frameLw / 2;
    ctx.strokeRect(frameInset, frameInset, w - frameInset * 2, h - frameInset * 2);
    // 票面 m.（完整写好的那一笔；24k 宽，iOS 同款）
    ctx.save();
    const markW = 24 * k;
    const markH = markW * MARK_BOUNDS_H / MARK_BOUNDS_W;
    ctx.translate((w - markW) / 2, (h - markH) / 2);
    drawHandwrittenMark(ctx, markW, markH, MarkScript.total(), withAlpha(this.ink, 0.85));
    ctx.restore();
  }
}

@Component
export struct StampPackCard {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  /** 卡片此刻的阶段（父组件持有，点按钮回调上去改） */
  @Prop phase: StampPackPhase = StampPackPhase.Ready;
  /** 领到了几张（Claimed 时显示「+N」；数字不查翻译表，各语言都是「+20」） */
  @Prop claimedAdded: number = 0;
  /** 邮票的墨色和纸色：跟邮戳、信纸同一套 */
  ink: string = '#3D3428';
  paper: string = '#F7F1E3';
  onClaim: () => void = (): void => {};
  onLater: () => void = (): void => {};

  private isClaimed(): boolean {
    return this.phase === StampPackPhase.Claimed;
  }

  private isClaiming(): boolean {
    return this.phase === StampPackPhase.Claiming;
  }

  /** 领到以后三张邮票收拢成一摞（0.25 = 快并拢了） */
  private spread(): number {
    return this.isClaimed() ? 0.25 : 1;
  }

  build() {
    Column() {
      this.stampStack()

      // 两段文字不交叉淡变（叠在一起会糊）：旧的先淡出，新的稍后再淡入
      if (this.isClaimed()) {
        Column({ space: 4 }) {
          Text(`+${this.claimedAdded}`)
            .fontSize(30)
            .fontWeight(600) // iOS .semibold
            .fontFamily('serif')
            .fontColor(this.theme.textPrimary)
          Text($r('app.string.s_8e54b4b852'))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textSecondary)
        }
        .alignItems(HorizontalAlign.Center)
        .transition(TransitionEffect.OPACITY
          .animation({ duration: 250, delay: 150, curve: Curve.EaseIn }))
      } else {
        Column() {
          Text($r('app.string.s_58db88cd01'))
            .fontSize(this.theme.headingFont.size)
            .fontWeight(this.theme.headingFont.weight)
            .fontFamily(this.theme.headingFont.family)
            .fontColor(this.theme.textPrimary)
            .textAlign(TextAlign.Center)
          Text($r('app.string.s_c8356051fa'))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textSecondary)
            .textAlign(TextAlign.Center)
            .margin({ top: 6 })

          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Stack() {
              Text($r('app.string.s_39d12e73fb'))
                .fontSize(this.theme.bodyFont.size)
                .fontWeight(600) // iOS .semibold
                .fontFamily(this.theme.bodyFont.family)
                .fontColor(this.theme.background)
                .opacity(this.isClaiming() ? 0 : 1)
              if (this.isClaiming()) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(this.theme.background)
              }
            }
            .width('100%')
            .height(44)
          }
          .width('100%')
          .height(44)
          .backgroundColor(this.theme.accent)
          .enabled(!this.isClaiming())
          .margin({ top: 22 })
          .onClick((): void => {
            this.onClaim();
          })

          Text($r('app.string.s_479fcc1cc0'))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textTertiary)
            .width('100%')
            .height(36)
            .textAlign(TextAlign.Center)
            .margin({ top: 4 })
            .onClick((): void => {
              this.onLater();
            })
        }
        .transition(TransitionEffect.OPACITY
          .animation({ duration: 150, curve: Curve.EaseOut }))
      }
    }
    .padding({
      left: 24,
      right: 24,
      top: 26,
      bottom: this.isClaimed() ? 26 : 12
    })
    .width(270)
    .backgroundColor(this.theme.cardBackground)
    .borderRadius(20)
    .border({ width: 0.5, color: this.theme.border })
    .shadow({ radius: 24, color: 'rgba(0,0,0,0.18)', offsetX: 0, offsetY: 10 })
  }

  /** 三张叠着的邮票，像刚从邮局拿回来的一小叠。领到以后收拢成一摞 */
  @Builder
  private stampStack() {
    Stack() {
      MarkStamp({ widthVp: 44, ink: this.ink, paper: this.paper })
        .rotate({ angle: -9 * this.spread() })
        .offset({ x: -26 * this.spread(), y: 4 * this.spread() })
        .animation({ duration: 450, curve: Curve.EaseInOut })
      MarkStamp({ widthVp: 44, ink: this.ink, paper: this.paper })
        .rotate({ angle: 7 * this.spread() })
        .offset({ x: 26 * this.spread(), y: 3 * this.spread() })
        .animation({ duration: 450, curve: Curve.EaseInOut })
      MarkStamp({ widthVp: 44, ink: this.ink, paper: this.paper })
        .animation({ duration: 450, curve: Curve.EaseInOut })
    }
    .height(64)
    .margin({ bottom: 18 })
  }
}
