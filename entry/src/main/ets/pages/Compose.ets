/**
 * 写日记页路由入口（10_BUILD_MANUAL.md 2.1）。逻辑全在 `views/compose/ComposeView`。
 */
import { ComposeView } from '../views/compose/ComposeView';

@Entry
@Component
struct ComposePage {
  build() {
    Column() {
      ComposeView()
    }
    .width('100%')
    .height('100%')
  }
}
