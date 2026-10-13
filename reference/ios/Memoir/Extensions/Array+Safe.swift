import Foundation

extension Array {
    /// 安全下标：越界返回 nil 而非 crash
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
