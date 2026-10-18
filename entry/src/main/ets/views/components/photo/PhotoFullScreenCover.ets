/**
 * 照片全屏查看页（10_BUILD_MANUAL.md 2.6 / 2.9）。对应 iOS `Views/Components/PhotoPaper/PhotoFullScreenView.swift`。
 *
 * - 点击任意处或下拉关闭（下拉 >120vp）；双指缩放 0.9x–4x，松手小于 1 弹回（静态图；
 *   动态照片不支持动态属性，不参与缩放）
 * - 动态照片（2.9，iOS `LivePhotoView` 同款意图）：`loadMovingPhoto` 用配对静态图
 *   （相机 _full / 相册原图）+ 视频构造 `MovingPhoto`，`MovingPhotoView` 长按播放；
 *   加载 / 播放出错退静态图（R-PHOTO-04 兜底）
 * - 右上「⋯」编辑菜单（R-PHOTO-01 / 2.6 卡片）：靠左 / 靠右、设为封面、换相纸、删除
 *   —— 回调全可选：详情页进全屏是纯预览，不给编辑入口（iOS 同款 `hasEditActions`）
 * - 删除先确认（「删除这张照片？」，R-ENTRY-13 之外唯一的整块照片删除路径）
 * - 静态全屏也用 600px 正文缩略图（iOS 同款 `loadImage`；600px 在手机屏上足够）
 */
import { image } from '@kit.ImageKit';
import { curves, SymbolGlyphModifier } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { photoAccessHelper, MovingPhotoView, MovingPhotoViewController } from '@kit.MediaLibraryKit';
import { fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import {
  STORAGE_KEY_SAFE_AREA_TOP_VP
} from '../../../services/ImmersiveChrome';
import { ContentBlock, ContentBlockType, PhotoPosition } from '../../../models/ContentBlock';
import { PhotoPaperIO } from '../../../services/PhotoPaperIO';
import { FALLBACK_PHOTO_ASPECT } from './PhotoPapers';

/** 缩放范围（iOS 同款 0.9x–4x） */
const MIN_SCALE: number = 0.9;
const MAX_SCALE: number = 4.0;
/** 下拉超过这个位移才关（iOS 120pt） */
const DISMISS_DRAG_VP: number = 120;
/** 关闭 / 复位动画（iOS spring response 0.3 damping 0.8 近似） */
const RESET_CURVE = curves.springCurve(0, 1, 320, 30);

const DOMAIN = 0x0000;
const TAG = 'PhotoFullScreenCover';

@Component
export struct PhotoFullScreenCover {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  /** 要看的照片块 */
  photo: ContentBlock = new ContentBlock('', ContentBlockType.Photo);
  /** 关闭（点空白 / 下拉 / 菜单操作完成都走它） */
  onDismiss: () => void = (): void => {};
  // ---- 编辑回调（全 undefined = 纯预览，不显示「⋯」） ----
  /** 靠左 / 靠右互换 */
  onTogglePosition: (() => void) | undefined = undefined;
  /** 设为 / 取消封面（一篇最多一张，清旧由调用方保证） */
  onToggleCover: (() => void) | undefined = undefined;
  /** 换相纸（重开相纸选择器） */
  onRestyle: (() => void) | undefined = undefined;
  /** 删除照片（确认弹窗后回调；文件清理由调用方做） */
  onDelete: (() => void) | undefined = undefined;

  @State private pixelMap: image.PixelMap | undefined = undefined;
  @State private photoAspect: number = FALLBACK_PHOTO_ASPECT;
  /** 动态照片对象（loadMovingPhoto 构造；非动态照片 / 加载失败为 undefined） */
  @State private movingPhoto: photoAccessHelper.MovingPhoto | undefined = undefined;
  /** 动态照片加载 / 播放失败 → 退静态图（R-PHOTO-04 兜底） */
  @State private movingPhotoFailed: boolean = false;
  /** 缩放倍数；成员不能叫 scale（撞 .scale() 属性方法） */
  @State private zoomScale: number = 1.0;
  @State private lastZoom: number = 1.0;
  @State private dragOffsetY: number = 0;
  /** 动态照片播放控制器（MovingPhotoView 长按播放用） */
  private movingPhotoController: MovingPhotoViewController = new MovingPhotoViewController();
  /** 打开时刻（ms）：dismiss 日志计时用 */
  private openedAtMs: number = 0;

  aboutToAppear(): void {
    this.openedAtMs = Date.now();
    hilog.info(DOMAIN, TAG, 'cover appear id=%{public}s', this.photo.id);
    this.loadPhoto();
    this.loadMovingPhoto();
  }

  private hasEditActions(): boolean {
    return this.onTogglePosition !== undefined || this.onToggleCover !== undefined ||
      this.onRestyle !== undefined || this.onDelete !== undefined;
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 纯黑底（延伸到状态栏 / 手势条底下）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .expandSafeArea([SafeAreaType.SYSTEM])

      // 动态照片：MovingPhotoView 长按播放（组件不支持动态属性，不参与缩放/拖拽）
      if (this.movingPhoto !== undefined && !this.movingPhotoFailed) {
        MovingPhotoView({
          movingPhoto: this.movingPhoto,
          controller: this.movingPhotoController
        })
          .objectFit(ImageFit.Contain)
          .muted(false)
          .width('100%')
          .height('100%')
          .onError((): void => {
            // 播放出错：退静态图（R-PHOTO-04）
            hilog.error(DOMAIN, TAG, 'MovingPhotoView onError, fallback to still');
            this.movingPhotoFailed = true;
          })
      } else if (this.pixelMap !== undefined) {
        Image(this.pixelMap)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
          .draggable(false)
          .scale({ x: this.zoomScale, y: this.zoomScale })
          .offset({ y: this.dragOffsetY })
      } else {
        Column() {
          Text($r('app.string.s_6c2b170c04'))
            .fontSize(14)
            .fontColor('#99FFFFFF')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      // 右上「⋯」编辑菜单（详情页纯预览不显示）
      if (this.hasEditActions()) {
        Row() {
          SymbolGlyph($r('sys.symbol.more'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor([Color.White])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor('#59000000')
        .justifyContent(FlexAlign.Center)
        .margin({ top: this.safeAreaTopVp + 16, right: 16 })
        .bindMenu(this.editMenuItems())
      }
    }
    .width('100%')
    .height('100%')
    // 浮层转场内置（弃用 bindContentCover 后自己补）：淡入 + 轻微放大进场
    .transition(
      TransitionEffect.OPACITY
        .animation({ curve: Curve.EaseOut, duration: 250 })
        .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 })
          .animation({ curve: Curve.EaseOut, duration: 250 }))
    )
    // 点击：放大时复位，否则关闭（iOS 同款）。幽灵点击守卫已移除：那是
    // bindContentCover 模态转场重投递打开点击的专属问题，页面内浮层无此现象
    .onClick((): void => {
      if (this.zoomScale > 1.01) {
        this.animateReset();
      } else {
        hilog.info(DOMAIN, TAG, 'cover dismiss by tap dt=%{public}dms', Date.now() - this.openedAtMs);
        this.onDismiss();
      }
    })
    // 双指缩放 0.9x–4x，松手小于 1 弹回
    .gesture(
      PinchGesture({ fingers: 2 })
        .onActionUpdate((event: GestureEvent): void => {
          this.zoomScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, this.lastZoom * event.scale));
        })
        .onActionEnd((): void => {
          this.lastZoom = this.zoomScale;
          if (this.zoomScale < 1.0) {
            this.animateReset();
          }
        })
    )
    // 未放大时下拉关闭
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Vertical })
        .onActionUpdate((event: GestureEvent): void => {
          if (this.zoomScale <= 1.01 && event.offsetY > 0) {
            this.dragOffsetY = event.offsetY;
          }
        })
        .onActionEnd((): void => {
          if (this.zoomScale <= 1.01 && this.dragOffsetY > DISMISS_DRAG_VP) {
            hilog.info(DOMAIN, TAG, 'cover dismiss by drag dy=%{public}f', this.dragOffsetY);
            this.onDismiss();
          } else {
            this.dragOffsetY = 0;
          }
        })
    )
  }

  /**
   * 右上「⋯」菜单：靠左 / 靠右、设为 / 取消封面、换相纸、删除（iOS 2026-08 后唯一编辑入口）。
   * 官方数组形式 bindMenu(Array<MenuElement>)，系统默认菜单样式，等价 iOS `Menu { Button }`；
   * 各项 symbolIcon 走 MenuElement 官方符号位（API 12+）。
   */
  private editMenuItems(): Array<MenuElement> {
    const items: Array<MenuElement> = [];
    if (this.onTogglePosition !== undefined) {
      const toggleItem: MenuElement = {
        value: this.photo.position === PhotoPosition.Right ?
          $r('app.string.s_9eda140339') : $r('app.string.s_613b4f74e0'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_left_arrow_right')),
        action: (): void => {
          this.onTogglePosition?.();
          this.onDismiss();
        }
      };
      items.push(toggleItem);
    }
    if (this.onToggleCover !== undefined) {
      const coverItem: MenuElement = {
        value: this.photo.isCover === true ?
          $r('app.string.s_5f9ab839a4') : $r('app.string.s_b7607a6106'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.star')),
        action: (): void => {
          this.onToggleCover?.();
          this.onDismiss();
        }
      };
      items.push(coverItem);
    }
    if (this.onRestyle !== undefined) {
      const restyleItem: MenuElement = {
        value: $r('app.string.s_047472a1db'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.picture_on_square')),
        action: (): void => {
          this.onRestyle?.();
          this.onDismiss();
        }
      };
      items.push(restyleItem);
    }
    if (this.onDelete !== undefined) {
      const deleteItem: MenuElement = {
        value: $r('app.string.s_c488684daf'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        action: (): void => {
          this.confirmDelete();
        }
      };
      items.push(deleteItem);
    }
    return items;
  }

  /** 删除前确认（AlertDialog，destructive 语义） */
  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.s_c488684daf'),
      message: $r('app.string.s_223d9e4e74'),
      primaryButton: {
        value: $r('app.string.s_4d0b4688c7'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.s_c488684daf'),
        fontColor: '#B5473A',
        action: (): void => {
          this.onDelete?.();
          this.onDismiss();
        }
      },
      cancel: (): void => {
      }
    });
  }

  private animateReset(): void {
    this.getUIContext().animateTo({ curve: RESET_CURVE }, (): void => {
      this.zoomScale = 1.0;
      this.lastZoom = 1.0;
      this.dragOffsetY = 0;
    });
  }

  private loadPhoto(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const io = PhotoPaperIO.forFilesDir(context.filesDir);
    io.loadImage(this.photo.photoFilename).then((loaded: image.PixelMap | undefined): void => {
      if (loaded === undefined) {
        return; // 留「照片加载失败」文案
      }
      this.pixelMap = loaded;
      const info = loaded.getImageInfoSync();
      if (info.size.width > 0 && info.size.height > 0) {
        this.photoAspect = info.size.width / info.size.height;
      }
    }).catch((): void => {
      // 失败保持占位文案
    });
  }

  /**
   * 动态照片加载（2.9）：配对静态图（相机 `_full` / 相册原图）+ 视频构造 `MovingPhoto`。
   * 非动态照片 / 任一文件缺失 / loadMovingPhoto 失败 → 不设置（静态图兜底，R-PHOTO-04）。
   */
  private loadMovingPhoto(): void {
    if (!this.photo.isLivePhoto) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const stillName = this.photo.pairingStillFilename;
    const videoName = this.photo.livePhotoVideoFilename;
    if (stillName === undefined || videoName === undefined) {
      return;
    }
    const io = PhotoPaperIO.forFilesDir(context.filesDir);
    photoAccessHelper.MediaAssetManager.loadMovingPhoto(context,
      fileUri.getUriFromPath(`${io.photosDir}/${stillName}`),
      fileUri.getUriFromPath(`${io.photosDir}/${videoName}`))
      .then((movingPhoto: photoAccessHelper.MovingPhoto): void => {
        this.movingPhoto = movingPhoto;
        hilog.info(DOMAIN, TAG, 'loadMovingPhoto ok');
      })
      .catch((err: BusinessError): void => {
        // 失败退静态图（静态 pixelMap 照常显示）
        hilog.error(DOMAIN, TAG, 'loadMovingPhoto failed %{public}d %{public}s',
          err.code, err.message);
        this.movingPhotoFailed = true;
      });
  }
}
