import SwiftUI

/// 日记本封面纹理。rawValue 与 `Cover_{Color}_{rawValue}` asset 命名严格对齐。
///
/// 📌 **2026-10 只剩亚麻**（产品决策）：皮革下架，也不再让用户选材质。
/// 纯色布面只是"还没换照片时"的底子 —— 封面的主角留给用户自己的照片，
/// 选项越多，越像是在暗示"选个颜色就够了"。
/// 存量的 "Leather" 由 `migrateTagsToBookCoverSystem` 改写成 "Linen"。
enum BookTexture: String, CaseIterable, Codable {
    case linen = "Linen"
}
