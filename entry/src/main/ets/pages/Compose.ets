/**
 * 写日记页路由入口（10_BUILD_MANUAL.md 2.1）。逻辑全在 `views/compose/ComposeView`。
 * 系统返回（侧滑手势 / 返回键）在这里拦截：onBackPress 返回 true 并经
 * AppStorage tick 转交 ComposeView 决策——不拦截则 router.back() 直接退出，
 * 有内容也不弹「保存 / 不保存」确认（真机踩坑，R-ENTRY-02/03）。
 */
import { ComposeView, STORAGE_KEY_COMPOSE_BACK_TICK } from '../views/compose/ComposeView';

@Entry
@Component
struct ComposePage {
  onBackPress(): boolean {
    const current: number = AppStorage.get<number>(STORAGE_KEY_COMPOSE_BACK_TICK) ?? 0;
    AppStorage.setOrCreate(STORAGE_KEY_COMPOSE_BACK_TICK, current + 1);
    return true; // 拦截：直接退 / 弹保存确认由 ComposeView 决定
  }

  build() {
    Column() {
      ComposeView()
    }
    .width('100%')
    .height('100%')
  }
}
