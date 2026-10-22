import SwiftUI
import UIKit

/// SwiftUI ↔ UIKit 桥接：把 `PageDataSource` 接到 `UIPageViewController`（`.pageCurl` 模式）。
///
/// **设计要点**：
/// - 用 `.pageCurl` + `.horizontal` 实现 Apple Books 同款曲面翻页
/// - 不主动响应 SwiftUI 端的 `currentIndex` 变化（避免打断用户手势）；只在用户翻页完成后**回写**索引
/// - `makeUIViewController` 时根据 dataSource.currentIndex 跳到初始页（所点那篇日记的首页）
/// - 一次翻页转场没结束之前不接受新的翻页手势（见 Coordinator「翻页转场期间锁住手势」）
struct PageCurlReaderView: UIViewControllerRepresentable {
    @ObservedObject var dataSource: PageDataSource
    /// 显式传入而不是用 `@Environment` —— 每一页都要靠它注入 SwiftUI 环境
    /// （见 `PageContentViewController`），Coordinator 也要拿着它建新页。
    let themeManager: ThemeManager

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: nil
        )
        pageVC.dataSource = context.coordinator
        pageVC.delegate = context.coordinator
        // 翻页过程中露出的"书脊底色"，跟纸张同色才不会在卷起时闪出一条异色边
        pageVC.view.backgroundColor = UIColor(themeManager.current.background)

        // 跳到初始页
        if let initialPage = dataSource.allPages[safe: dataSource.currentIndex] {
            let initialVC = PageContentViewController(page: initialPage, themeManager: themeManager)
            pageVC.setViewControllers([initialVC], direction: .forward, animated: false)
        }

        return pageVC
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        // 不主动刷新页面内容——用户翻页时由 Coordinator 回写 dataSource.currentIndex。
        // 但底色要跟一下：主题是在另一个 tab 改的，改完回来阅读器还开着的话，
        // 已建好的页会自己重绘，这一层不跟就会留一条旧主题的边。
        uiViewController.view.backgroundColor = UIColor(themeManager.current.background)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(dataSource: dataSource, themeManager: themeManager)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        let dataSource: PageDataSource
        let themeManager: ThemeManager

        /// 页面 VC 缓存：`PageData.id` → VC。
        ///
        /// 🔴 **不要每次被问到就 new 一个。** `UIPageViewController` 在一次手势里会反复问
        /// before/after，每次新建就等于新起一棵完整的 SwiftUI 树（整页正文 + 照片 + 满屏纸纹图）。
        /// 来回快翻几十次，这些 `UIHostingController` 会堆成山 —— 内存涨到被系统杀掉，
        /// 用户看到的就是「翻着翻着整个软件崩了」（2026-09-27 真机反馈）。
        ///
        /// 复用同一个实例还顺带解决了**身份不稳定**：同一页每次给出不同对象，
        /// 手势进行中 `UIPageViewController` 手里的 VC 会和数据源对不上。
        private var cache: [String: PageContentViewController] = [:]

        /// 缓存只留当前页前后各 3 页，再远的丢掉（翻回去时重建，代价远小于一直占着内存）
        private static let cacheRadius = 3

        init(dataSource: PageDataSource, themeManager: ThemeManager) {
            self.dataSource = dataSource
            self.themeManager = themeManager
        }

        /// 取这一页的 VC：优先复用缓存里的。
        ///
        /// **正在屏幕上显示的那个不能再交出去** —— `UIPageViewController` 收到重复的
        /// view controller 会直接抛异常，所以这种情况下新建一个。
        private func controller(for page: PageData,
                                showing: [UIViewController]) -> PageContentViewController {
            if let cached = cache[page.id], !showing.contains(cached) {
                return cached
            }
            let vc = PageContentViewController(page: page, themeManager: themeManager)
            cache[page.id] = vc
            trimCache(around: page)
            return vc
        }

        private func trimCache(around page: PageData) {
            guard let idx = dataSource.indexOf(page: page) else { return }
            let lower = idx - Self.cacheRadius, upper = idx + Self.cacheRadius
            let keep = Set((lower...upper).compactMap { dataSource.allPages[safe: $0]?.id })
            cache = cache.filter { keep.contains($0.key) }
        }

        // 右滑（上一页：回到较新日记 / 本篇前一页）—— Apple Books 标准方向
        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let current = viewController as? PageContentViewController,
                  let prev = dataSource.previousPage(before: current.page) else {
                return nil   // 边界 → UIPageViewController 自动弹性回弹
            }
            return controller(for: prev, showing: pageViewController.viewControllers ?? [])
        }

        // 左滑（下一页：去较旧日记 / 本篇后一页）—— Apple Books 标准方向
        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let current = viewController as? PageContentViewController,
                  let next = dataSource.nextPage(after: current.page) else {
                return nil
            }
            return controller(for: next, showing: pageViewController.viewControllers ?? [])
        }

        // MARK: 翻页转场期间锁住手势
        //
        // 🔴 快速来回翻页会崩（2026-09-16 实机反馈，崩溃时连着 Xcode，没留下崩溃报告）。
        // UIPageViewController 的已知弱点：上一次翻页转场还没结束（手指拖着 / 松手后卷曲或
        // 回弹的动画中），下一次翻页手势就开始了 —— 两次转场交错，它内部记的「当前是哪几页」
        // 对不上，会抛内部一致性异常。
        //
        // ⚠️ 模拟器上用 UI 测试连翻数百次**没能复现**（测试框架发手势有固定间隔，
        // 追不上真人手指的速度），所以这是按已知问题做的防护，**需要真机确认**。
        //
        // 做法：手势翻页一开始就关掉翻页容器的交互，这一页卷完或弹回之后再打开。
        // 已经按下的这根手指不受影响（关交互只挡新的触摸），返回按钮在容器外面，随时能点。

        /// 每次加锁 / 解锁都换一个号，兜底解锁只认自己那一次
        private var transitionToken = 0

        func pageViewController(_ pageViewController: UIPageViewController,
                                willTransitionTo pendingViewControllers: [UIViewController]) {
            lockPageTurns(in: pageViewController)
        }

        private func lockPageTurns(in pageViewController: UIPageViewController) {
            pageViewController.view.isUserInteractionEnabled = false
            transitionToken += 1
            let token = transitionToken
            // 兜底：万一收不到 didFinishAnimating（转场被系统打断之类），2 秒后自动解锁 ——
            // 绝不能让阅读器永久失去响应
            Task { [weak self, weak pageViewController] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.transitionToken == token else { return }
                pageViewController?.view.isUserInteractionEnabled = true
            }
        }

        private func unlockPageTurns(in pageViewController: UIPageViewController) {
            transitionToken += 1
            pageViewController.view.isUserInteractionEnabled = true
        }

        // 翻页动画结束（翻过去或弹回来都会走到）→ 解锁；翻过去了再回写当前索引
        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            unlockPageTurns(in: pageViewController)
            guard completed,
                  let current = pageViewController.viewControllers?.first as? PageContentViewController else {
                return
            }
            Task { @MainActor in
                if let idx = dataSource.indexOf(page: current.page) {
                    dataSource.currentIndex = idx
                }
            }
        }
    }
}
