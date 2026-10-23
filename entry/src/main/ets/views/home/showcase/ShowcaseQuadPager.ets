/**
 * 大屏捏小一级：一屏 4 篇，一页 2 × 2，**还是左右翻页**（U06 R-HOME-08；
 * 2026-10-21 用户定：4 篇时左右翻，16 篇起才上下滚）。
 * 对应 iOS `Views/Home/Overview/ShowcaseQuadPager.swift`。
 *
 * - Swiper + LazyForEach（IDataSource）：只建眼前这一两页（U06 R-HOME-10）
 * - 两边留白 18、格间 12、上下 8（iOS cellSize 同款）；最后一页不满四篇
 *   空着，别让剩下的挪位置
 * - 翻到哪页记在父组件的 quadIndex（@Link）：捏合时按手指落在哪一格
 *   算是哪篇；换级回来停在手指底下那篇
 */
import { JournalEntry } from '../../../models/JournalEntry';
import { QUAD_PAGE_SIZE, ShowcaseZoomLevel, quadPageCount,
  quadPageStart, zoomPhotoPixels } from '../../../models/ShowcaseDigest';
import { EntryPhotoStore } from '../../../services/EntryPhotoStore';
import { digestOf } from '../../../models/ShowcaseDigest';
import { STORAGE_KEY_APP_LANGUAGE } from '../../../services/LanguageManager';
import { OverviewCell } from './OverviewCell';

/** 页号数据源：0..页数-1（LazyForEach 要求 IDataSource） */
class QuadPageSource implements IDataSource {
  private listener: DataChangeListener | undefined = undefined;
  private count: number = 0;

  setCount(count: number): void {
    this.count = count;
    if (this.listener !== undefined) {
      this.listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.count;
  }

  getData(index: number): number {
    return index;
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listener = listener;
  }

  unregisterDataChangeListener(_listener: DataChangeListener): void {
    this.listener = undefined;
  }
}

@Component
export struct ShowcaseQuadPager {
  /** 日记重查后重建页数据（@Link 引用替换触发） */
  @Link @Watch('onDataChange') entries: JournalEntry[];
  /** 翻到的那一页（0 基；捏合换级后停在手指底下那篇所在的那一页） */
  @Link quadIndex: number;
  /** 点一格打开那篇 */
  onOpen: (id: string) => void = (_id: string): void => {};
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';

  private source: QuadPageSource = new QuadPageSource();

  aboutToAppear(): void {
    this.source.setCount(quadPageCount(this.entries.length));
    this.prefetchAround(this.quadIndex);
  }

  build() {
    Swiper() {
      LazyForEach(this.source, (pageIdx: number) => {
        this.quadPage(pageIdx)
      }, (pageIdx: number): string => this.pageKey(pageIdx))
    }
    .index(this.quadIndex)
    .onChange((index: number): void => {
      this.quadIndex = index;
      this.prefetchAround(index);
    })
    .loop(false)
    .indicator(false)
    .cachedCount(1)
    .id('showcaseQuadPager')
    .width('100%')
    .height('100%')
  }

  /** 一页 2 × 2（Grid 按格等分；空格留空，别让剩下的挪位置） */
  @Builder
  private quadPage(pageIdx: number) {
    Grid() {
      ForEach([0, 1, 2, 3], (slot: number) => {
        GridItem() {
          this.slotCell(pageIdx, slot)
        }
      }, (slot: number): string => `${slot}`)
    }
    .columnsTemplate('1fr 1fr')
    .rowsTemplate('1fr 1fr')
    .columnsGap(12)
    .rowsGap(12)
    .padding({ left: 18, right: 18, top: 8, bottom: 8 })
    .width('100%')
    .height('100%')
  }

  @Builder
  private slotCell(pageIdx: number, slot: number) {
    // 最后一页不满四篇：空着（空 Stack 不响应点击，不挡旁边格子的命中区）
    if (quadPageStart(pageIdx) + slot < this.entries.length) {
      OverviewCell({
        digest: digestOf(this.entries[quadPageStart(pageIdx) + slot], this.appLanguage),
        zoom: ShowcaseZoomLevel.Four,
        onOpen: this.onOpen
      })
    }
  }

  /** 左右各一页的照片先在后台解出来，翻过去就有（U06 R-HOME-10） */
  private prefetchAround(page: number): void {
    if (this.entries.length === 0) {
      return;
    }
    const start = Math.max(0, quadPageStart(page) - QUAD_PAGE_SIZE);
    const end = Math.min(this.entries.length - 1,
      quadPageStart(page) + QUAD_PAGE_SIZE * 2 - 1);
    const names: string[] = [];
    for (let i = start; i <= end; i++) {
      const cover = digestOf(this.entries[i], this.appLanguage).cover;
      if (cover.length > 0) {
        names.push(cover);
      }
    }
    EntryPhotoStore.shared().prefetch(names, zoomPhotoPixels(ShowcaseZoomLevel.Four));
  }

  /** 页 key 带内容签名：同页 key 不重建子树，只换页号时增删日记不刷新 UI */
  private pageKey(pageIdx: number): string {
    const start = quadPageStart(pageIdx);
    const end = Math.min(this.entries.length - 1, start + QUAD_PAGE_SIZE - 1);
    let latest = 0;
    for (let i = start; i <= end && i < this.entries.length; i++) {
      latest = Math.max(latest, this.entries[i].updatedAt);
    }
    return `p${pageIdx}#${latest}`;
  }

  private onDataChange(): void {
    this.source.setCount(quadPageCount(this.entries.length));
  }
}
