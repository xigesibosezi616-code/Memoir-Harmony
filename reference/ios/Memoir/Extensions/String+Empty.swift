import Foundation

extension String {
    /// 空串（含纯空白）当作 nil，便于用 `??` 串联降级路径。
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
