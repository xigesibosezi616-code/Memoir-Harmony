import SwiftUI

/// 给所在 NavigationStack 的导航栏标题上色（大标题，和往上滑收起后的小标题）。`nil` = 系统默认色。
///
/// SwiftUI 没有给导航标题上色的接口，只能顺着视图控制器找到 UIKit 的导航栏去设。
/// 用法：挂在这一页内容的 `.background` 上。设的是整条导航栏，这个 NavigationStack 里推出来的页面也跟着用这个颜色
struct NavigationBarTitleColor: UIViewControllerRepresentable {
    let color: Color?

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.color = color.map { UIColor($0) }
    }

    final class Controller: UIViewController {
        var color: UIColor? {
            didSet { apply() }
        }

        // 刚建出来时还没挂进导航栈，拿不到导航栏；挂进去、要显示时再设一次
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        private func apply() {
            guard let bar = navigationController?.navigationBar else { return }
            let attributes: [NSAttributedString.Key: Any]? = color.map { [.foregroundColor: $0] }
            bar.largeTitleTextAttributes = attributes
            bar.titleTextAttributes = attributes
        }
    }
}
