/**
 * 编辑日记页路由入口（10_BUILD_MANUAL.md 2.4）。逻辑在 `views/edit/EditEntryView`。
 * 参数：`{ id: 日记 id }`。系统返回（侧滑 / 返回键）整个拦下（R-ENTRY-11：
 * 编辑页只有 ✕ / ✓ 两个出口，不响应系统返回）。
 */
import { EditEntryView } from '../views/edit/EditEntryView';

@Entry
@Component
struct EditEntryPage {
  onBackPress(): boolean {
    return true; // 拦截：只能经 ✕ / ✓ 退出（R-ENTRY-11）
  }

  build() {
    Column() {
      EditEntryView()
    }
    .width('100%')
    .height('100%')
  }
}
