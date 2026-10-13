import UIKit
import SwiftUI

/// 单页内容承载 UIViewController —— UIPageViewController 的"每一页"实际就是这个 VC。
///
/// 根据 `PageData` 分发到两种 SwiftUI 视图：正文页（首页带页眉）/ 末页。
/// 通过 `UIHostingController` 嵌入；背景**强制不透明**（`.pageCurl` 翻页透出问题的根源）。
final class PageContentViewController: UIViewController {
    let page: PageData
    private let themeManager: ThemeManager

    init(page: PageData, themeManager: ThemeManager) {
        self.page = page
        self.themeManager = themeManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 纸张底色跟随主题。**必须不透明**：`.pageCurl` 翻页时会把这一层当作纸的背面，
        // 透明的话翻起来能看穿到下一页（这是当初写死颜色的原因之一）。
        view.backgroundColor = UIColor(themeManager.current.background)
        view.isOpaque = true

        // 🔴 `UIHostingController` 会**新起一棵 SwiftUI 树**，父视图的 environment
        // 不会自动带过来 —— 不显式注入的话，页面视图里的
        // `@Environment(ThemeManager.self)` 取不到值，运行时直接崩。
        let host = UIHostingController(rootView: pageBody.environment(themeManager))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    @ViewBuilder
    private var pageBody: some View {
        switch page {
        case .content(let diary, let pageIndex, let totalPages, let blocks):
            ContentPageView(
                diary: diary,
                pageIndex: pageIndex,
                totalPages: totalPages,
                blocks: blocks
            )
        case .ending(let diary, let hasNext):
            EndingPageView(diary: diary, hasNextDiary: hasNext)
        }
    }
}
