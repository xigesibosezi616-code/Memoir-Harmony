/**
 * 日记详情页路由入口（10_BUILD_MANUAL.md 2.3 最小版）。
 * 逻辑在 `views/detail/EntryDetailView`；参数：`{ id: 日记 id }`。
 */
import { EntryDetailView } from '../views/detail/EntryDetailView';

@Entry
@Component
struct EntryDetailPage {
  build() {
    Column() {
      EntryDetailView()
    }
    .width('100%')
    .height('100%')
  }
}
