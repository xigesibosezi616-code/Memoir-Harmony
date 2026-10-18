/**
 * 正文里的照片锚点卡（10_BUILD_MANUAL.md 2.6）：builder span 的内容。
 * 对应 iOS `PhotoPaperView`（包装器：分发样式 + 固定倾斜 + 按压反馈 + 手势）。
 *
 * 退化方案（Q23，产品已确认按此推进）：RichEditor 无绕排，照片是**整行卡片** ——
 * 卡片宽 46% 按位置（position 左 / 右）对齐（对齐 iOS `RichTextView.photoWidthRatio`
 * = 0.46，正文照片的视觉大小一致），上下是独立文字段；倾斜角照常渲染。
 *
 * 手势（2026-10-17 产品拍板）：
 * - 轻点 → 弹「功能条」（放左 / 右侧、设为封面、换相纸、删除；bindPopup 光感条）
 * - 双击 → 秒换边（卡片内弹簧动画滑到对侧，动画结束才提交数据重插）
 * - 长按 → 全屏查看
 * - 详情页（四个编辑回调都不给）：轻点 / 长按都开全屏纯预览，不弹功能条
 * 相纸样式经会员降级（`effectivePaperStyle`，2.6 全放开，7.2 接判定）。
 */
import { image } from '@kit.ImageKit';
import { curves } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { ContentBlock, ContentBlockType, PhotoPosition, PaperStyle, effectivePaperStyle } from '../../../models/ContentBlock';
import { PhotoPaperIO } from '../../../services/PhotoPaperIO';
import { FALLBACK_PHOTO_ASPECT, PhotoPaperCard } from './PhotoPapers';

/** 卡片宽 = 正文编辑区宽的 46%（iOS `RichTextView.photoWidthRatio` 同款，视觉大小对齐） */
const CARD_WIDTH_RATIO: string = '46%';
/** 双击判定窗口（ms）：窗口内第二击 = 双击，超时 = 单击弹功能条 */
const DOUBLE_TAP_WINDOW_MS: number = 280;
/** 换边动画时长（ms）：弹簧滑到对侧后提交数据（updatePhoto 重插新卡） */
const FLIP_COMMIT_MS: number = 320;

const DOMAIN = 0x0000;
const TAG = 'PhotoAnchorCard';

@Component
export struct PhotoAnchorCard {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  /** 退格第一次选中态（R-RICH-05：视觉上高亮这张卡） */
  @Prop armed: boolean = false;
  /** 照片块本体（更新 = 删旧 span 重插新卡，不做增量响应） */
  block: ContentBlock = new ContentBlock('', ContentBlockType.Photo);
  /** 会员判定（7.2 接上；2.6 恒 true 全放开） */
  isMember: boolean = true;
  /** 长按打开全屏查看（详情页 = 轻点也走它） */
  onOpen: (blockId: string) => void = (_blockId: string): void => {};
  // ---- 功能条动作（全不给 = 纯预览卡，轻点也开全屏） ----
  /** 放左 / 右侧互换 */
  onTogglePosition: ((blockId: string) => void) | undefined = undefined;
  /** 设为 / 取消封面（一篇最多一张，清旧由调用方保证） */
  onToggleCover: ((blockId: string) => void) | undefined = undefined;
  /** 换相纸（重开相纸选择器） */
  onRestyle: ((blockId: string) => void) | undefined = undefined;
  /** 删除照片（调用方负责确认弹窗） */
  onDelete: ((blockId: string) => void) | undefined = undefined;

  @State private pixelMap: image.PixelMap | undefined = undefined;
  @State private photoAspect: number = FALLBACK_PHOTO_ASPECT;
  /** 功能条显隐（bindPopup） */
  @State private showBar: boolean = false;
  /** 双击换边的横向位移（vp）：0 = 原位，正 = 向右滑，负 = 向左滑 */
  @State private slideX: number = 0;
  /** 单击延迟开条 / 双击判定的计时器句柄 */
  private tapTimerId: number = -1;
  private lastTapMs: number = 0;
  /** 换边动画进行中（未提交数据前忽略再次双击） */
  private flipPending: boolean = false;
  /** 换边滑动距离测量（onAreaChange）：整行宽 − 卡片宽 */
  private rowWidthVp: number = 0;
  private cardWidthVp: number = 0;

  aboutToAppear(): void {
    this.loadPhoto();
  }

  aboutToDisappear(): void {
    this.clearTapTimer();
  }

  build() {
    Row() {
      Column() {
        // pixelMap 异步加载完成 → @State 变化 → 分支翻转强制重建整条渲染链。
        // 不能只把 pixelMap 当普通变量传下去：V1 状态管理下父组件刷新不更新
        // 子组件普通成员变量，Image 永远拿不到图（真机实测只显示占位图标）。
        if (this.pixelMap === undefined) {
          PhotoPaperCard({
            style: this.displayStyle(),
            photoAspect: this.photoAspect
          })
        } else {
          PhotoPaperCard({
            style: this.displayStyle(),
            pixelMap: this.pixelMap,
            photoAspect: this.photoAspect
          })
        }
      }
      .width(CARD_WIDTH_RATIO)
      .rotate({ angle: this.block.rotationAngle ?? 0 })
      .opacity(this.armed ? 0.85 : 1.0)
      .border(this.armed ? {
        width: 1.5,
        color: this.theme.accent,
        radius: 10
      } : { width: 0 })
      .translate({ x: this.slideX })
      .onAreaChange((_old: Area, newValue: Area): void => {
        this.cardWidthVp = typeof newValue.width === 'number' ? newValue.width : 0;
      })
      // RichEditor 的光标 / 选词手势会赢下手势仲裁，卡片的点 / 长按全被吃掉（真机实测）。
      // Block：触摸到卡片为止，不再冒泡给 RichEditor —— 点照片 = 弹功能条（iOS 同款，
      // 照片卡不参与文本选择）。
      // ⚠️ 只能加在 46% 卡片本体上：外层 Row 是 100% 宽的锚点行，Block 放外面会把
      // 整行的触摸都吞掉 → 插入照片后正文打不了字（真机实测回归，⑥）
      .hitTestBehavior(HitTestMode.Block)
      // 轻点（延迟判定双击）→ 功能条；双击 → 秒换边
      .gesture(
        TapGesture({ count: 1 })
          .onAction((): void => {
            this.handleTap();
          })
      )
      // 长按 → 全屏查看（R-PHOTO-01）
      .gesture(
        LongPressGesture({ repeat: false, duration: 350 })
          .onAction((): void => {
            this.clearTapTimer();
            this.showBar = false;
            this.onOpen(this.block.id);
          })
      )
      // 功能条（bindPopup 光感浮条）：autoCancel 点外部自动收
      .bindPopup(this.showBar, {
        builder: this.functionBarBuilder,
        placement: Placement.Bottom,
        popupColor: Color.Transparent,
        enableArrow: false,
        autoCancel: true,
        onStateChange: (state: PopupStateChangeParam): void => {
          if (!state.isVisible) {
            this.showBar = false;
          }
        }
      })
    }
    .width('100%')
    .justifyContent(this.block.position === PhotoPosition.Left ? FlexAlign.Start : FlexAlign.End)
    .padding({ top: 2, bottom: 8 })
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.rowWidthVp = typeof newArea.width === 'number' ? newArea.width : 0;
    })
  }

  /** 轻点 / 双击统一入口：窗口内第二击 = 换边；否则 280ms 后弹功能条（或纯预览开全屏） */
  private handleTap(): void {
    const now = Date.now();
    if (now - this.lastTapMs < DOUBLE_TAP_WINDOW_MS) {
      this.lastTapMs = 0;
      this.clearTapTimer();
      this.flipAnimated();
      return;
    }
    this.lastTapMs = now;
    this.clearTapTimer();
    this.tapTimerId = setTimeout((): void => {
      this.tapTimerId = -1;
      if (this.hasBarActions()) {
        this.showBar = true;
      } else {
        this.onOpen(this.block.id);
      }
    }, DOUBLE_TAP_WINDOW_MS);
  }

  /** 详情页纯预览（四个动作都不给）时不弹条 */
  private hasBarActions(): boolean {
    return this.onTogglePosition !== undefined || this.onToggleCover !== undefined ||
      this.onRestyle !== undefined || this.onDelete !== undefined;
  }

  /**
   * 双击秒换边：先在卡片内做弹簧滑动（translate），动画完才提交数据 ——
   * 页面改 position + updatePhoto（删旧 span 重插新卡，新卡天然落在新侧）。
   * 提交前忽略后续双击，避免数据 / 视觉错位。
   */
  private flipAnimated(): void {
    if (this.onTogglePosition === undefined || this.flipPending) {
      return;
    }
    const slide = Math.max(0, this.rowWidthVp - this.cardWidthVp);
    if (slide <= 0) {
      // 几何还没量到（极早双击）：退化成直接换边，无动画
      this.onTogglePosition(this.block.id);
      return;
    }
    this.flipPending = true;
    const toggle = this.onTogglePosition;
    const blockId = this.block.id;
    const goingRight = this.block.position !== PhotoPosition.Left;
    const target = goingRight ? slide : -slide;
    this.getUIContext().animateTo({ curve: curves.springCurve(0, 1, 300, 28) }, (): void => {
      this.slideX = target;
    });
    setTimeout((): void => {
      this.flipPending = false;
      this.slideX = 0; // 提交后 updatePhoto 重插新卡，本卡即销毁；先归位防一帧闪
      toggle(blockId);
    }, FLIP_COMMIT_MS);
  }

  private clearTapTimer(): void {
    if (this.tapTimerId >= 0) {
      clearTimeout(this.tapTimerId);
      this.tapTimerId = -1;
    }
  }

  /** 功能条：光感深色浮条（放左 / 右侧 · 设为封面 · 换相纸 · 删除） */
  @Builder
  functionBarBuilder() {
    Row({ space: 2 }) {
      if (this.onTogglePosition !== undefined) {
        this.barButton($r('sys.symbol.arrow_left_arrow_right'),
          this.block.position === PhotoPosition.Left ? $r('app.string.s_613b4f74e0') : $r('app.string.s_9eda140339'),
          (): void => {
            this.runBarAction((): void => {
              this.onTogglePosition?.(this.block.id);
            });
          }, false)
      }
      if (this.onToggleCover !== undefined) {
        this.barButton($r('sys.symbol.star'),
          this.block.isCover === true ? $r('app.string.s_5f9ab839a4') : $r('app.string.s_b7607a6106'),
          (): void => {
            this.runBarAction((): void => {
              this.onToggleCover?.(this.block.id);
            });
          }, false)
      }
      if (this.onRestyle !== undefined) {
        this.barButton($r('sys.symbol.picture_on_square'),
          $r('app.string.s_047472a1db'),
          (): void => {
            this.runBarAction((): void => {
              this.onRestyle?.(this.block.id);
            });
          }, false)
      }
      if (this.onDelete !== undefined) {
        this.barButton($r('sys.symbol.trash'),
          $r('app.string.s_c488684daf'),
          (): void => {
            this.runBarAction((): void => {
              this.onDelete?.(this.block.id);
            });
          }, true)
      }
    }
    .padding({ left: 6, right: 6, top: 6, bottom: 6 })
    .borderRadius(24)
    .backgroundColor('#E61C1C1E')
    .border({ width: 0.5, color: '#33FFFFFF' })
    .shadow({ radius: 18, color: '#33000000', offsetY: 6 })
  }

  /** 先收条再执行动作（动作里的 updatePhoto 会重插卡片，条随旧卡销毁） */
  private runBarAction(action: () => void): void {
    this.showBar = false;
    action();
  }

  @Builder
  private barButton(icon: Resource, label: Resource, onTap: () => void, destructive: boolean) {
    Column({ space: 3 }) {
      SymbolGlyph(icon)
        .fontSize(17)
        .fontColor([destructive ? '#FFB5473A' : '#F2FFFFFF'])
      Text(label)
        .fontSize(10)
        .fontColor(destructive ? '#FFB5473A' : '#E6FFFFFF')
        .maxLines(1)
    }
    .constraintSize({ minWidth: 64 })
    .padding({ top: 8, bottom: 6, left: 6, right: 6 })
    .borderRadius(16)
    .onClick((): void => {
      onTap();
    })
  }

  /** 实际渲染样式：会员款 + 非会员 → 宝丽来（存值不改，`effectivePaperStyle`） */
  private displayStyle(): PaperStyle {
    const stored = this.block.paperStyle ?? PaperStyle.Polaroid;
    return effectivePaperStyle(stored, this.isMember);
  }

  private loadPhoto(): void {
    const context = this.getUIContext().getHostContext();
    // 诊断日志（真机 spike）：锚点卡装载路径上所有静默分支可见
    hilog.info(DOMAIN, TAG, 'anchor aboutToAppear id=%{public}s file=%{public}s ctx=%{public}s',
      this.block.id, this.block.photoFilename ?? 'nil', context === undefined ? 'nil' : 'ok');
    if (context === undefined) {
      return;
    }
    const io = PhotoPaperIO.forFilesDir(context.filesDir);
    io.loadImage(this.block.photoFilename).then((loaded: image.PixelMap | undefined): void => {
      if (loaded === undefined) {
        hilog.warn(DOMAIN, TAG, 'anchor load missed id=%{public}s file=%{public}s',
          this.block.id, this.block.photoFilename ?? 'nil');
        return; // 留 4:3 占位格（加载失败也有格子，不塌陷）
      }
      hilog.info(DOMAIN, TAG, 'anchor load ok id=%{public}s file=%{public}s',
        this.block.id, this.block.photoFilename ?? 'nil');
      // 先算比例再赋 pixelMap：两次赋值同帧批量刷新，分支重建时两个值都已就位
      const info = loaded.getImageInfoSync();
      if (info.size.width > 0 && info.size.height > 0) {
        this.photoAspect = info.size.width / info.size.height;
      }
      this.pixelMap = loaded;
    }).catch((err: BusinessError): void => {
      // 加载失败保持占位格
      hilog.error(DOMAIN, TAG, 'anchor load threw id=%{public}s: %{public}s',
        this.block.id, JSON.stringify(err));
    });
  }
}
