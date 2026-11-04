/**
 * 投信动画的全页覆盖层：那叠日记收拢成信纸 → 信封从下面托上来 →
 * 举到投信口推进去 → 翻板落回，邮筒里安静下来。
 * 对应 iOS `Views/PostBox/Posting/LetterPostingFlight.swift`。
 *
 * - 只照着 `computeFlightFrame` 摆，自己不算手感（单测在几何层）
 * - `t` 由页面逐帧推进（displaySync 驱动 `postingT`），这里只收结果
 * - 整层不响应点击（`HitTestMode.None`）——动画期间版式不动、
 *   再点邮筒由页面自己忽略
 * - 信封只画投信口以下的部分（口子上面被邮筒的沿挡着）：
 *   遮罩容器摆在口子下沿、`clip(true)`，信封在里面随便推
 */
import { PostingRun, RectF, computeFlightFrame } from '../../models/LetterPostingFlightGeometry';
import { LetterPalette } from './LetterPalette';
import { OutgoingPile } from './OutgoingPile';
import { SealedEnvelope, FoldedLetter } from './SealedEnvelope';

@Component
export struct LetterPostingFlight {
  /** 逐帧推进的动画时刻（秒，0 ~ TOTAL） */
  @Prop t: number = 0;
  /** 正在投的这一封（点下邮筒那一刻的快照） */
  run: PostingRun = new PostingRun([], [], false, '素');
  /** 信件用料（跟着主题换） */
  palette: LetterPalette = LetterPalette.bamboo;
  /** 那叠日记的窗口矩形（动画期间版式恒定，点那一刻量好） */
  pileRect: RectF = { x: 0, y: 0, width: 0, height: 0 };
  /** 投信口矩形（同上） */
  slotRect: RectF = { x: 0, y: 0, width: 0, height: 0 };
  // ---- 那叠日记的版式度量（和页面里那份传同一套，快照才对得上） ----
  @Prop totalHeightVp: number = 188;
  @Prop headerHeightVp: number = 34;
  @Prop rowHeightVp: number = 40;
  @Prop fadeHeightVp: number = 24;

  private frame() {
    return computeFlightFrame(this.t, this.pileRect, this.slotRect, this.run.hasSeal);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. 那叠日记的快照：缩到信纸大小、跟着挪过去、淡掉（换真身进来的是信纸）
      if (this.frame().pileOpacity > 0.001) {
        Stack() {
          OutgoingPile({
            palette: this.palette,
            items: this.run.items,
            excludedIds: this.run.excludedIds,
            interactive: false,
            totalHeightVp: this.totalHeightVp,
            headerHeightVp: this.headerHeightVp,
            rowHeightVp: this.rowHeightVp,
            fadeHeightVp: this.fadeHeightVp
          })
        }
        .width(this.pileRect.width)
        .position({ x: this.pileRect.x, y: this.pileRect.y })
        .scale({ x: this.frame().pileScaleX, y: this.frame().pileScaleY, centerX: '50%', centerY: '50%' })
        .translate({ x: this.frame().pileOffsetX, y: this.frame().pileOffsetY })
        .opacity(this.frame().pileOpacity)
      }

      // 2. 收拢出来的那页信纸（替那叠日记飞进信封）
      if (this.frame().sheetVisible) {
        FoldedLetter({
          palette: this.palette,
          widthVp: this.frame().sheetWidth,
          heightVp: this.frame().sheetHeight
        })
          .position({ x: this.frame().sheetX, y: this.frame().sheetY })
          .opacity(this.frame().sheetOpacity)
      }

      // 3. 投信口里被推开的翻板，露出里面的黑（信进去了就落回去）
      if (this.frame().gapVisible) {
        Column()
          .width(this.frame().gapWidth)
          .height(this.frame().gapHeight)
          .borderRadius(this.frame().gapHeight / 2)
          .backgroundColor('#9E000000')
          .position({ x: this.frame().gapX, y: this.frame().gapY })
      }

      // 4. 信封（只画投信口以下）
      Stack({ alignContent: Alignment.TopStart }) {
        SealedEnvelope({
          palette: this.palette,
          mark: this.run.sealMark,
          hasSeal: this.run.hasSeal,
          progress: this.frame().envProgress,
          sealPress: this.frame().sealPress,
          widthVp: this.frame().envWidth
        })
          .position({
            x: this.frame().envX,
            y: this.frame().envY - this.slotRect.y - this.slotRect.height
          })
          .rotate({
            x: 1, y: 0, z: 0,
            angle: this.frame().envTiltDeg,
            centerX: '50%', centerY: '0%',
            perspective: 0.6
          })
          .opacity(this.frame().envOpacity)
      }
      .position({ x: 0, y: this.slotRect.y + this.slotRect.height })
      .width('100%')
      .height('100%')
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
