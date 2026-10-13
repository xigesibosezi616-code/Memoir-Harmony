import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// 从照片里取主色调，用来给大屏卡片的文字区染色。
///
/// **只取图片底部三分之一的平均色**：文字区紧接在图片下缘，取那一带的颜色才能接得上；
/// 取全图平均会出现「天空是蓝的、文字区却是土黄」这种上下不搭。
///
/// 用 Core Image 的 `CIAreaAverage`（GPU 一次归约成 1×1 像素），不做 k-means 聚类 ——
/// 聚类能找出「最鲜艳的那块」，但这里要的是**和图片下缘无缝衔接**的颜色，平均色反而更准。
enum DominantColor {
    /// 按文件名缓存，避免每帧重算（滑动时 body 会频繁重估）
    private static let cache = NSCache<NSString, UIColor>()
    /// 复用 CIContext —— 每次新建的开销比滤镜本身大得多
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func extract(from image: UIImage, cacheKey: String) -> Color {
        let key = cacheKey as NSString
        if let cached = cache.object(forKey: key) {
            return Color(uiColor: cached)
        }
        let color = compute(from: image) ?? UIColor(white: 0.5, alpha: 1)
        cache.setObject(color, forKey: key)
        return Color(uiColor: color)
    }

    private static func compute(from image: UIImage) -> UIColor? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let extent = ciImage.extent
        guard extent.width > 1, extent.height > 1 else { return nil }

        // CI 坐标原点在左下角 —— 所以 y 从 origin 起、高度取 1/3，正是视觉上的底部
        let sampleRect = CGRect(
            x: extent.origin.x,
            y: extent.origin.y,
            width: extent.width,
            height: max(1, extent.height / 3)
        )

        let filter = CIFilter.areaAverage()
        filter.inputImage = ciImage
        filter.extent = sampleRect
        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let raw = UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
        return normalize(raw)
    }

    /// 把平均色调成「能用的染色」。
    ///
    /// 平均色天生偏灰偏暗（各种颜色互相抵消），直接拿来染会是一坨脏色。
    /// 两步修正：饱和度拉起来让呼应看得出来；亮度收进中间段 ——
    /// 否则夜景照片会染出一块死黑（文字看不清）、雪景照片染了等于没染。
    private static func normalize(_ color: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
        let saturation = min(max(s * 1.4, 0.20), 0.72)
        let brightness = min(max(b, 0.38), 0.86)
        return UIColor(hue: h, saturation: saturation, brightness: brightness, alpha: 1)
    }
}
