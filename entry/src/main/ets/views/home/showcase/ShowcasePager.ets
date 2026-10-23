/**
 * 大屏展示模式第 0 级：一屏一篇日记，左右滑动翻篇（U06 R-HOME-08；
 * 样子 R-HOME-06）。对应 iOS `Views/Home/ShowcaseView.swift`。
 *
 * - 与列表模式的分工：列表用来**找**某一篇，大屏用来**重看**——放大照片、
 *   留白，让一篇日记像一张唱片封面那样被重新看见
 * - Swiper + LazyForEach（IDataSource）：只建眼前这一两页（U06 R-HOME-10）
 * - 照片在后台解（`EntryPhotoStore`，最长边 1400px），翻到哪页就把左右
 *   两页的照片先解出来
 * - 图文配比：字越多照片让位越多（R-HOME-06），正文行数同步收紧
 * - 文字区染色取照片底部主色，按感知亮度定深 / 浅字（不能用主题文字色：
 *   那套色是给纸面底设计的，压在深色染出的底上会糊）
 * - 翻到哪篇记在父组件的 singleIndex（@Link）：张开回来时停在手指底下那篇
 * - 🔴 卡片不加阴影（iOS 对照实验：分页容器会按自己的边框裁阴影，
 *   出上下两条硬边）
 */
import { image } from '@kit.ImageKit';
import { JournalEntry } from '../../../models/JournalEntry';
import { cardImageRatio, cardTextLines, ShowcaseZoomLevel,
  showcaseCardSize, zoomPhotoPixels } from '../../../models/ShowcaseDigest';
import { digestOf } from '../../../models/ShowcaseDigest';
import { EntryPhoto, EntryPhotoStore } from '../../../services/EntryPhotoStore';
import { AudioMemoPlayer } from '../../../services/AudioRecorderManager';
import { dayAndWeekday } from '../../../services/AppDateFormatters';
import { STORAGE_KEY_APP_LANGUAGE } from '../../../services/LanguageManager';
import { moodLabelRes } from '../../components/MoodBadge';
import { isDefaultMoodKey } from '../../../models/Mood';
import { WeatherLocationBadge } from '../../components/WeatherLocationBadge';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { cardTintGradient, colorToArgb, dissolveEndColor,
  moodCoverGradient, resolveTintHex, TintTextColors,
  tintTextColorsFor } from './ShowcasePalette';

/** 翻页数据源（LazyForEach 要求 IDataSource） */
class EntryPageSource implements IDataSource {
  private listener: DataChangeListener | undefined = undefined;
  private entries: JournalEntry[] = [];

  setEntries(entries: JournalEntry[]): void {
    this.entries = entries;
    if (this.listener !== undefined) {
      this.listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.entries.length;
  }

  getData(index: number): JournalEntry {
    return this.entries[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listener = listener;
  }

  unregisterDataChangeListener(_listener: DataChangeListener): void {
    this.listener = undefined;
  }
}

@Component
export struct ShowcasePager {
  /** 日记重查后重建页数据（@Link 引用替换触发） */
  @Link @Watch('onDataChange') entries: JournalEntry[];
  /** 翻到的那篇（0 基；张开回来时停在手指底下那篇） */
  @Link singleIndex: number;
  /** 点卡片进详情 */
  onOpen: (id: string) => void = (_id: string): void => {};
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';

  private source: EntryPageSource = new EntryPageSource();

  aboutToAppear(): void {
    this.source.setEntries(this.entries);
    this.prefetchAround(this.singleIndex);
  }

  build() {
    Swiper() {
      LazyForEach(this.source, (entry: JournalEntry) => {
        ShowcaseCard({
          entry: entry,
          onTap: (): void => {
            this.onOpen(entry.id);
          }
        })
      }, (entry: JournalEntry): string => `${entry.id}#${entry.updatedAt}`)
    }
    .index(this.singleIndex)
    .onChange((index: number): void => {
      this.singleIndex = index;
      this.prefetchAround(index);
    })
    .loop(false)
    .indicator(false)
    .cachedCount(2)
    .id('showcasePager')
    .width('100%')
    .height('100%')
  }

  /** 左右各两页的照片先在后台解出来，翻过去就有 */
  private prefetchAround(index: number): void {
    if (this.entries.length === 0) {
      return;
    }
    const start = Math.max(0, index - 2);
    const end = Math.min(this.entries.length - 1, index + 2);
    const names: string[] = [];
    for (let i = start; i <= end; i++) {
      const cover = digestOf(this.entries[i], this.appLanguage).cover;
      if (cover.length > 0) {
        names.push(cover);
      }
    }
    EntryPhotoStore.shared().prefetch(names, zoomPhotoPixels(ShowcaseZoomLevel.One));
  }

  private onDataChange(): void {
    this.source.setEntries(this.entries);
    this.prefetchAround(this.singleIndex);
  }
}

// ---- 单篇卡片 ----

@Component
struct ShowcaseCard {
  entry: JournalEntry = new JournalEntry('', Date.now(), Date.now(), Date.now());
  onTap: () => void = (): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';

  /** 轮播的照片（封面优先，其余按出现顺序）、正文预览：建卡时解一次 */
  private photos: string[] = [];
  private preview: string = '';
  private rotationTimeout: number = -1;
  private photoIndex: number = 0;

  /** 正在显示的那张（后台解好的）；换张时旧的压在底下淡出（交叠过渡） */
  @State private currentMap: image.PixelMap | undefined = undefined;
  @State private fadingMap: image.PixelMap | undefined = undefined;
  @State private tintHex: string = '#808080';
  @State private photoLoaded: boolean = false;
  @State private isPlaying: boolean = false;
  /** 所在页尺寸（onAreaChange 实测，vp）：卡按 2:3 封顶算，不再拉满填高 */
  @State private containerWidth: number = 0;
  @State private containerHeight: number = 0;
  private player: AudioMemoPlayer = new AudioMemoPlayer();

  /** 大卡片的照片解到多大（最长边，像素）；轮播间隔（U06 R-HOME-10） */
  private static readonly rotationIntervalMs: number = 4000;
  private static readonly cornerRadius: number = 26;

  aboutToAppear(): void {
    // 封面优先、其余按出现顺序（iOS `showcasePhotoFilenames`）
    const all = this.entry.photoFilenames;
    const cover = this.entry.coverPhotoFilename;
    if (cover !== undefined) {
      this.photos = [cover];
      for (const name of all) {
        if (name !== cover) {
          this.photos.push(name);
        }
      }
    } else {
      this.photos = all;
    }
    this.preview = this.entry.textPreview;

    // 解过的直接用上（翻回来、从总览张开时一出来就有图）
    const store = EntryPhotoStore.shared();
    if (this.photos.length > 0) {
      const first = this.photos[0];
      const exact = store.cached(first, zoomPhotoPixels(ShowcaseZoomLevel.One));
      const any = exact !== undefined ? exact : store.anyCached(first);
      if (any !== undefined) {
        this.currentMap = any.pixelMap;
        this.tintHex = any.tintHex;
        this.photoLoaded = true;
      } else {
        const known = store.knownTint(first);
        if (known !== undefined) {
          this.tintHex = known;
        } else {
          this.tintHex = resolveTintHex(undefined, undefined,
            this.moodColorHex(), this.theme);
        }
        this.loadFirstPhoto();
      }
    } else {
      this.tintHex = resolveTintHex(undefined, undefined,
        this.moodColorHex(), this.theme);
    }
    this.player.onFinished = (): void => {
      this.isPlaying = false;
    };
    if (this.photos.length > 1) {
      this.scheduleRotation();
    }
  }

  aboutToDisappear(): void {
    if (this.rotationTimeout >= 0) {
      clearTimeout(this.rotationTimeout);
      this.rotationTimeout = -1;
    }
    this.player.stop();
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Top }) {
        // 底色：tint 72%→94% 叠页面底（合成不透明）。原来垫毛玻璃：真机上
        // 每翻一张新卡都建一层实时模糊，翻页掉帧（iOS 2026-10-21 测帧）
        Column()
          .width('100%')
          .height('100%')
          .linearGradient(this.tintGradient())

        Column() {
          this.cover()
          this.textArea()
        }
        .width('100%')
        .height('100%')
      }
      .width(this.cardWidth())
      .height(this.cardHeight())
      .borderRadius(ShowcaseCard.cornerRadius)
      .clip(true)
      .border({ width: 0.8, color: 0x38FFFFFF }) // 白 22% 描边
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.containerWidth = Number(newArea.width);
      this.containerHeight = Number(newArea.height);
    })
    .onClick((): void => {
      this.onTap();
    })
  }

  /** 卡片尺寸：量到容器前先按填满渲染（首帧布局回调前来得及换上实测值） */
  private cardWidth(): Length {
    if (this.containerWidth <= 0 || this.containerHeight <= 0) {
      return '100%';
    }
    return showcaseCardSize(this.containerWidth, this.containerHeight)[0];
  }

  private cardHeight(): Length {
    if (this.containerWidth <= 0 || this.containerHeight <= 0) {
      return '100%';
    }
    return showcaseCardSize(this.containerWidth, this.containerHeight)[1];
  }

  /** 封面：照片轮播（交叠淡入淡出）+ 下缘溶进底色 + 页点；没照片是心情色渐变 */
  @Builder
  private cover() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.currentMap === undefined && this.fadingMap === undefined
        && this.photos.length === 0) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 135,
            colors: this.moodGradientStops()
          })
      }
      if (this.fadingMap !== undefined) {
        Image(this.fadingMap)
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.OPACITY.animation({
            duration: 600, curve: Curve.EaseInOut
          }))
      }
      if (this.currentMap !== undefined) {
        Image(this.currentMap)
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.OPACITY.animation({
            duration: 600, curve: Curve.EaseInOut
          }))
      }
      // 溶解 overlay：渐到与底色在照片区底缘逐像素一致的不透明色（无缝）
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            [Color.Transparent, 0.7],
            [this.dissolveMidColor(), 0.9],
            [this.dissolveEnd(), 1]
          ]
        })
      // 页点：多张照片时右上角标进度
      if (this.photos.length > 1) {
        Row({ space: 4 }) {
          ForEach(this.photos, (_name: string, index?: number) => {
            Circle()
              .width(5)
              .height(5)
              .fill((index ?? 0) === this.photoIndex ? 0xF2FFFFFF : 0x66FFFFFF)
          }, (name: string): string => name)
        }
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .backgroundColor(0x47000000)
        .borderRadius(10)
        .margin(14)
      }
    }
    .width('100%')
    .height(`${this.imageRatio() * 100}%`)
    .clip(true)
  }

  /** 文字区：标题 + 日期·心情 + 正文（行数按图文配比收紧）+ 此时此地 + 播放键 */
  @Builder
  private textArea() {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          if (this.entry.title.length > 0) {
            Text(this.entry.title)
              .fontSize(this.theme.headingFont.size)
              .fontWeight(this.theme.headingFont.weight)
              .fontFamily(this.theme.headingFont.family)
              .fontColor(this.textColors().title)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Row({ space: 5 }) {
            Text(dayAndWeekday(new Date(this.entry.date), this.appLanguage))
              .fontSize(this.theme.captionFont.size)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.textColors().meta)
              .maxLines(1)
            if (this.moodLabelText() !== undefined) {
              Text('·')
                .fontSize(this.theme.captionFont.size)
                .fontFamily(this.theme.captionFont.family)
                .fontColor(this.textColors().meta)
              Text(this.moodLabelText())
                .fontSize(this.theme.captionFont.size)
                .fontFamily(this.theme.captionFont.family)
                .fontColor(this.textColors().meta)
                .maxLines(1)
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.entry.hasAudio) {
          Button() {
            SymbolGlyph(this.isPlaying
              ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
              .fontSize(17)
              .fontColor([this.playButtonIconColor()])
          }
          .width(46)
          .height(46)
          .backgroundColor(this.textColors().title)
          .borderRadius(23)
          .onClick((): void => {
            this.togglePlayback();
          })
        }
      }
      .alignItems(VerticalAlign.Center)

      if (this.textLines() > 0 && this.preview.length > 0) {
        Text(this.preview)
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.textColors().body)
          .lineHeight(this.theme.bodyFont.size + this.theme.bodyLineSpacing)
          .maxLines(this.textLines())
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start)
          .width('100%')
      }

      WeatherLocationBadge({
        weatherCode: this.entry.weatherCode ?? '',
        weatherInfo: this.entry.weatherInfo ?? '',
        locationInfo: this.entry.locationInfo ?? '',
        fontSize: this.theme.labelFont.size,
        fontColor: this.textColors().meta,
        iconSize: 11
      })
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20, bottom: 20 })
    .width('100%')
    .layoutWeight(1)
  }

  // ---- 轮播 ----

  /** 第一张：后台解，解好淡入（解过的在上面就拿到了） */
  private loadFirstPhoto(): void {
    if (this.photos.length === 0) {
      return;
    }
    const first = this.photos[0];
    EntryPhotoStore.shared().load(first, zoomPhotoPixels(ShowcaseZoomLevel.One))
      .then((photo: EntryPhoto | undefined): void => {
        if (photo === undefined || this.currentMap !== undefined) {
          return;
        }
        this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, (): void => {
          this.currentMap = photo.pixelMap;
          this.tintHex = photo.tintHex;
          this.photoLoaded = true;
        });
      })
      .catch((): void => {
      });
  }

  private scheduleRotation(): void {
    if (this.rotationTimeout >= 0) {
      clearTimeout(this.rotationTimeout);
    }
    this.rotationTimeout = setTimeout((): void => {
      this.rotateNext();
    }, ShowcaseCard.rotationIntervalMs);
  }

  /** 多张照片轮播：下一张先在后台解好，再和这一张交叠换过去 */
  private rotateNext(): void {
    if (this.photos.length <= 1) {
      return;
    }
    const next = (this.photoIndex + 1) % this.photos.length;
    EntryPhotoStore.shared().load(this.photos[next], zoomPhotoPixels(ShowcaseZoomLevel.One))
      .then((photo: EntryPhoto | undefined): void => {
        if (photo !== undefined) {
          // 旧的压在底下淡出、新的淡入（同一帧插入 / 移除 → 交叠）
          this.fadingMap = this.currentMap;
          this.getUIContext().animateTo({ duration: 600, curve: Curve.EaseInOut }, (): void => {
            this.currentMap = photo.pixelMap;
            this.tintHex = photo.tintHex;
            this.photoLoaded = true;
            this.photoIndex = next;
            this.fadingMap = undefined;
          });
        }
        this.scheduleRotation();
      })
      .catch((): void => {
        this.scheduleRotation();
      });
  }

  // ---- 录音播放 ----

  private togglePlayback(): void {
    if (this.isPlaying) {
      this.player.stop();
      this.isPlaying = false;
      return;
    }
    const first = this.entry.audioURLs[0];
    if (first === undefined) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.player.startRelative(context.filesDir, first).then((ok: boolean): void => {
      this.isPlaying = ok;
    });
  }

  // ---- 配色 ----

  private moodColorHex(): string {
    const digest = digestOf(this.entry, this.appLanguage);
    return digest.moodColorHex;
  }

  private tintArgb(): number {
    const parsed = colorToArgb(this.tintHex);
    return parsed === undefined ? 0xFF808080 : parsed;
  }

  private pageBgArgb(): number {
    const bg = colorToArgb(this.theme.background);
    return bg === undefined ? 0xFFFFFFFF : bg;
  }

  private tintGradient(): LinearGradientOptions {
    const colors = cardTintGradient(this.tintArgb(), this.pageBgArgb());
    return {
      angle: 180,
      colors: [[colors[0], 0], [colors[1], 1]]
    };
  }

  private imageRatio(): number {
    return cardImageRatio(this.preview.length);
  }

  private textLines(): number {
    return cardTextLines(this.preview.length);
  }

  /** 照片下缘溶进底色：渐到底色在照片区底缘的取值（严丝合缝） */
  private dissolveEnd(): ResourceColor {
    return dissolveEndColor(this.tintArgb(), this.pageBgArgb(), this.imageRatio());
  }

  private dissolveMidColor(): ResourceColor {
    const end = dissolveEndColor(this.tintArgb(), this.pageBgArgb(), this.imageRatio());
    return (end & 0x00FFFFFF) | 0x59000000;
  }

  private moodGradientStops(): Array<[ResourceColor, number]> {
    const colors = moodCoverGradient(this.tintArgb(), this.pageBgArgb());
    return [[colors[0], 0], [colors[1], 1]];
  }

  private textColors(): TintTextColors {
    return tintTextColorsFor(this.tintHex);
  }

  /** 播放键图标色：与文字区底色反着来（浅底深键深图标） */
  private playButtonIconColor(): ResourceColor {
    return this.photoLoaded && this.tintIsLight() ? 0xFF121212 : 0xFFFFFFFF;
  }

  private tintIsLight(): boolean {
    const argb = colorToArgb(this.tintHex);
    if (argb === undefined) {
      return true;
    }
    const r = (argb >> 16) & 0xFF;
    const g = (argb >> 8) & 0xFF;
    const b = argb & 0xFF;
    // BT.601 感知亮度（iOS `isLightColor` 同款）
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6;
  }

  private moodLabelText(): ResourceStr | undefined {
    if (this.entry.mood.length === 0) {
      return undefined;
    }
    if (isDefaultMoodKey(this.entry.mood)) {
      const res = moodLabelRes(this.entry.mood);
      if (res !== undefined) {
        return res;
      }
    }
    return this.entry.mood;
  }
}
