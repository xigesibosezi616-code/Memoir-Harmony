import SwiftUI

/// 用户可见错误 / 提示的统一出口。
///
/// **用法**：通过 `AppEnvironment.errors` 取用，调用 `present(...)` 触发 toast。
/// 顶层 overlay（`ContentView`）观察 `current` 字段自动展示。
///
/// **承接对象**：
/// - AI 服务网络失败、配额不足、内容过滤等
/// - 未来渐进替换现有 54 处 `try?` 静默吞错时，错误从这里冒出
@Observable
final class ErrorPresenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let kind: Kind
    }
    enum Kind: Equatable { case error, info, success }

    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    /// 展示一条提示。应从主线程 / View 动作 / @MainActor 上下文调用。
    func present(_ message: String, kind: Kind = .error, duration: TimeInterval = 3) {
        dismissTask?.cancel()
        current = Toast(message: message, kind: kind)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    /// 从 Error 展示。优先用 LocalizedError 文案，否则用 fallback。
    func present(_ error: Error, fallback: String, duration: TimeInterval = 4) {
        let msg = (error as? LocalizedError)?.errorDescription ?? fallback
        present(msg, kind: .error, duration: duration)
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}
