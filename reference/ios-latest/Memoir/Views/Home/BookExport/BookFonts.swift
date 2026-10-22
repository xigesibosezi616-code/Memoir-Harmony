import CoreText
import SwiftUI
import UIKit

/// 精装 PDF 的字（2026-10-21 产品定：**中文正文用宋体**）。
///
/// iOS 不自带中文宋体，苹果的「宋体」（Songti SC / TC）是系统可下载字体：第一次导出时用 CoreText 的下载接口取一次
///（十几 MB，系统存着，以后不再下），拿不到（没网 / 失败）就退回苹方，照样能导出。
/// 日文用系统自带的冬青明朝；韩文没有自带的衬线字，用系统黑体；英法西用 Georgia（和 App 里一致）。
/// 跟着 **App 选的语言**定，不跟系统语言
enum BookFonts {
    private enum Script {
        case simplifiedChinese, traditionalChinese, japanese, korean, latin
    }

    private static var script: Script {
        let id = appLocale.identifier.lowercased()
        if id.hasPrefix("zh") {
            return id.contains("hant") || id.contains("tw") || id.contains("hk") ? .traditionalChinese : .simplifiedChinese
        }
        if id.hasPrefix("ja") { return .japanese }
        if id.hasPrefix("ko") { return .korean }
        return .latin
    }

    /// 正文、粗体的 PostScript 名
    private static var names: (regular: String, bold: String) {
        switch script {
        case .simplifiedChinese:  return ("STSongti-SC-Regular", "STSongti-SC-Bold")
        case .traditionalChinese: return ("STSongti-TC-Regular", "STSongti-TC-Bold")
        case .japanese:           return ("HiraMinProN-W3", "HiraMinProN-W6")
        case .korean:             return ("AppleSDGothicNeo-Regular", "AppleSDGothicNeo-Bold")
        case .latin:              return ("Georgia", "Georgia-Bold")
        }
    }

    /// 要不要下载（只有宋体要下）
    static var needsDownload: Bool {
        switch script {
        case .simplifiedChinese, .traditionalChinese:
            return UIFont(name: names.regular, size: 12) == nil || UIFont(name: names.bold, size: 12) == nil
        default:
            return false
        }
    }

    /// 导出前调：宋体还没有就下载，`progress` 0…1。下好了 / 本来就有返回 true；没下成返回 false（退回苹方，照样能排）
    static func prepare(progress: @escaping @Sendable (Double) -> Void = { _ in }) async -> Bool {
        guard needsDownload else { return true }
        let wanted = [names.regular, names.bold]
        let descriptors = wanted.map { CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: $0] as CFDictionary) }
        let finished = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce()
            CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors as CFArray, nil) { state, parameters in
                switch state {
                case .downloading:
                    let info = parameters as NSDictionary
                    if let percent = info[kCTFontDescriptorMatchingPercentage] as? Double {
                        progress(min(max(percent / 100, 0), 1))
                    }
                case .didFailWithError:
                    let error = (parameters as NSDictionary)[kCTFontDescriptorMatchingError] as? NSError
                    NSLog("⚠️ [BookFonts] 宋体下载失败 domain=%@ code=%ld %@", error?.domain ?? "-", error?.code ?? 0, "\(String(describing: error))")
                case .didFinish:
                    if once.claim() { continuation.resume(returning: true) }
                default:
                    break
                }
                return true
            }
        }
        // 下载接口说「完了」不等于真的有了：再按名字取一次
        return finished && !needsDownload
    }

    /// 正文字（UIKit 量高度用）。宋体没有就退回系统字（苹方）
    static func body(_ size: CGFloat, bold: Bool = false) -> UIFont {
        UIFont(name: bold ? names.bold : names.regular, size: size)
            ?? .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }

    /// 正文字（SwiftUI 画用）。和 `body` 同一款，量的和画的才对得上
    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        Font(body(size, bold: bold))
    }
}

/// 回调可能来好几次「完了」：只认第一次
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
