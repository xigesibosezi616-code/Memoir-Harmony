/**
 * 这篇日记要记哪个地点 —— 地点选择器（10_BUILD_MANUAL.md 2.10，R-PLACE-01）。
 * 对应 iOS `Views/Compose/LocationPickerView.swift`，微信式：
 * 「不显示位置 / 当前位置」两行 + 按距离排序的附近地点，可搜索。
 *
 * 数据全部来自华为官方 kit（Q8 拍板）：无关键词走 MapKit `site.nearbySearch`
 * （周边 POI），有关键词走 `site.searchByText`（以当前位置为中心放宽到 5km）。
 * 搜不到不是错误（郊野、室内很常见），静默留空。
 */
import { site } from '@kit.MapKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { PlaceMode } from '../../models/Draft';

const DOMAIN = 0x0000;
const TAG = 'LocationPicker';

/** 附近 / 搜索结果里的一行 */
class NearbySiteOption {
  readonly name: string;
  readonly address: string;
  readonly distanceText: string;

  constructor(name: string, address: string, distanceText: string) {
    this.name = name;
    this.address = address;
    this.distanceText = distanceText;
  }
}

@Component
export struct LocationPickerView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  /** 当前选择模式（auto / none / manual），决定哪行打勾 */
  @Prop currentMode: string = PlaceMode.Auto;
  /** 手动挑过的地名（manual 行打勾判定） */
  manualName: string = '';
  /** 自动解析出的地名，「当前位置」那行的标题 */
  autoName: string = '';
  /** 当前坐标（附近搜索中心） */
  latitude: number = 0;
  longitude: number = 0;
  /** 定位没拿到时附近列表整个留空（胶囊态点进来也可能没坐标：权限拒后取天气失败等） */
  hasCoordinate: boolean = false;
  /** 选定：mode + manual 模式下挑中的名字。选择器自己不关 sheet，由调用方收 */
  onSelect: (mode: string, manualName: string) => void =
    (_mode: string, _manualName: string): void => {};
  onCancel: () => void = (): void => {};

  @State query: string = '';
  @State sites: NearbySiteOption[] = [];
  @State isLoading: boolean = false;
  /** 输入停顿 300ms 再搜，避免每敲一个字打一次请求（iOS scheduleSearch 同款） */
  private searchTimer: number = -1;
  /** 并发搜索丢弃旧结果：只有最新一次请求的返回才进列表 */
  private loadSeq: number = 0;

  aboutToAppear(): void {
    this.loadSites();
  }

  aboutToDisappear(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
  }

  build() {
    Column() {
      // 标题行：取消（左）+ 选择地点（居中）
      Stack({ alignContent: Alignment.Center }) {
        Text($r('app.string.s_6ca9eae4f6'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textSecondary)
          .letterSpacing(this.theme.letterSpacingWide)
        Row() {
          Text($r('app.string.s_4d0b4688c7'))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textSecondary)
            .onClick((): void => {
              this.onCancel();
            })
          Blank()
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: 4, bottom: 14 })

      // 搜索框
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.textTertiary])
        TextInput({ text: this.query, placeholder: this.searchPlaceholderText() })
          .onChange((value: string): void => {
            this.onQueryChange(value);
          })
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .placeholderColor(this.theme.textTertiary)
          .placeholderFont({
            size: this.theme.bodyFont.size,
            weight: this.theme.bodyFont.weight,
            family: this.theme.bodyFont.family
          })
          .backgroundColor(Color.Transparent)
          .padding({ left: 0, right: 0, top: 0, bottom: 0 })
          .height(34)
          .layoutWeight(1)
          .defaultFocus(false)
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 12, right: 12 })
      .width('100%')
      .height(46)
      .borderRadius(14)
      .backgroundColor(this.theme.cardBackground)
      .margin({ bottom: 6 })

      // 列表：固定两行 + 附近地点
      List() {
        // 不显示位置
        ListItem() {
          this.optionRow($r('app.string.s_4aaa4b57b9'), '', false,
            this.currentMode === PlaceMode.None, (): void => {
              this.choose(PlaceMode.None, '');
            })
        }

        // 当前位置（autoName 是数据、副标题才是文案；解析出来才显示这行）
        if (this.autoName.length > 0) {
          ListItem() {
            this.optionRow(this.autoName, this.currentPlaceSubtitle(), true,
              this.currentMode === PlaceMode.Auto, (): void => {
                this.choose(PlaceMode.Auto, '');
              })
          }
        }

        // 分组标题：附近 / 搜索结果
        ListItem() {
          Text(this.query.trim().length > 0 ? $r('app.string.s_2f17ec1476') : $r('app.string.s_08c2940d38'))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textTertiary)
            .width('100%')
            .padding({ top: 10, bottom: 4 })
        }

        if (this.isLoading && this.sites.length === 0) {
          ListItem() {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(this.theme.accent)
              Text($r('app.string.s_eff49a2e1b'))
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textTertiary)
            }
            .alignItems(VerticalAlign.Center)
            .width('100%')
            .padding({ top: 8, bottom: 8 })
          }
        } else if (this.sites.length === 0) {
          ListItem() {
            Text(this.emptySitesText())
              .fontSize(this.theme.labelFont.size)
              .fontWeight(this.theme.labelFont.weight)
              .fontFamily(this.theme.labelFont.family)
              .fontColor(this.theme.textTertiary)
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          }
        } else {
          ForEach(this.sites, (option: NearbySiteOption) => {
            ListItem() {
              this.optionRow(option.name, this.siteSubtitle(option),
                this.siteSubtitleVisible(option),
                this.currentMode === PlaceMode.Manual && option.name === this.manualName,
                (): void => {
                  this.choose(PlaceMode.Manual, option.name);
                })
            }
          }, (option: NearbySiteOption): string => option.name + '#' + option.address)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .padding({ left: 20, right: 20, top: 12, bottom: 16 })
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }

  /** 一行选项：标题（+副标题）+ 选中勾（副标题可能是资源也可能是数据，统一 ResourceStr） */
  @Builder
  private optionRow(title: ResourceStr, subtitle: ResourceStr, subtitleVisible: boolean,
    selected: boolean, action: () => void) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (subtitleVisible) {
          Text(subtitle)
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.accent])
      }
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding({ top: 11, bottom: 11 })
    .onClick((): void => {
      action();
    })
  }

  // ---- 文案 ----

  private searchPlaceholderText(): ResourceStr {
    return $r('app.string.s_3c71843c7b');
  }

  /** 「当前位置」行的副标题（数据是标题 autoName，副标题才是文案，iOS 同款） */
  private currentPlaceSubtitle(): ResourceStr {
    return $r('app.string.s_b458ea40bf');
  }

  private emptySitesText(): ResourceStr {
    return this.query.trim().length > 0
      ? $r('app.string.s_35795a4e98')
      : $r('app.string.s_52cd34ba98');
  }

  /** 附近站点的副标题：距离 + 地址，帮用户在同名店铺间分辨 */
  private siteSubtitle(option: NearbySiteOption): string {
    if (option.distanceText.length > 0 && option.address.length > 0) {
      return `${option.distanceText} · ${option.address}`;
    }
    if (option.distanceText.length > 0) {
      return option.distanceText;
    }
    return option.address;
  }

  /** 站点行有没有副标题可显示（距离或地址任一） */
  private siteSubtitleVisible(option: NearbySiteOption): boolean {
    return option.distanceText.length > 0 || option.address.length > 0;
  }

  // ---- 搜索 ----

  private onQueryChange(value: string): void {
    this.query = value;
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      this.loadSites();
    }, 300);
  }

  private choose(mode: string, manualName: string): void {
    this.onSelect(mode, manualName);
  }

  /**
   * 无关键词用周边专用请求（空 query 的文本搜索搜不出东西）；
   * 有关键词以当前位置为中心放宽到 5km 做文本搜索（iOS 同款参数）。
   */
  private async loadSites(): Promise<void> {
    if (!this.hasCoordinate) {
      this.sites = [];
      return;
    }
    this.loadSeq++;
    const seq = this.loadSeq;
    this.isLoading = true;
    const keyword = this.query.trim();
    try {
      let found: NearbySiteOption[] = [];
      if (keyword.length === 0) {
        const result = await site.nearbySearch({
          location: { latitude: this.latitude, longitude: this.longitude },
          radius: 1000,
          pageSize: 20,
          language: 'zh'
        });
        found = LocationPickerView.optionsFrom(result.sites);
      } else {
        const result = await site.searchByText({
          query: keyword,
          location: { latitude: this.latitude, longitude: this.longitude },
          radius: 5000,
          pageSize: 20,
          language: 'zh'
        });
        found = LocationPickerView.optionsFrom(result.sites);
      }
      if (seq === this.loadSeq) {
        this.sites = found;
      }
    } catch (err) {
      const be = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'site search failed: %{public}d %{public}s',
        be.code, be.message ?? '');
      if (seq === this.loadSeq) {
        this.sites = [];
      }
    } finally {
      if (seq === this.loadSeq) {
        this.isLoading = false;
      }
    }
  }

  /** Site 列表 → 选项行（过滤无名、按距离升序——iOS 手动排序的同款结果） */
  private static optionsFrom(sites: Array<site.Site> | undefined): NearbySiteOption[] {
    const options: NearbySiteOption[] = [];
    if (sites === undefined) {
      return options;
    }
    const sorted = sites.slice(0);
    sorted.sort((a: site.Site, b: site.Site): number => {
      return (a.distance ?? Number.MAX_SAFE_INTEGER) - (b.distance ?? Number.MAX_SAFE_INTEGER);
    });
    for (const one of sorted) {
      const name = one.name ?? '';
      if (name.length === 0) {
        continue;
      }
      options.push(new NearbySiteOption(name, one.formatAddress ?? '',
        LocationPickerView.distanceText(one.distance)));
    }
    return options;
  }

  private static distanceText(meters: number | undefined): string {
    if (meters === undefined || meters < 0) {
      return '';
    }
    if (meters < 1000) {
      return `${Math.round(meters)} m`;
    }
    return `${(meters / 1000).toFixed(1)} km`;
  }
}
