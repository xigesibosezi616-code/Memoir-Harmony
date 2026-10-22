import CoreTransferable
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// **已弃用 / 占位保留**
///
/// 历史背景：曾用 `loadTransferable(type: LivePhotoMovieTransferable.self)` 试图从
/// `PhotosPickerItem` 取 Live Photo 视频部分，但 SwiftUI 的 `PhotosPickerItem`
/// 对 Live Photo **只暴露静态图 representation，不暴露 movie**。所以这条 Transferable
/// 通道对 Live Photo 永远返回 nil。
///
/// 正确做法见 `LivePhotoExtractor.extractLivePhoto(from:)` —— 走 PHAsset +
/// PHAssetResourceManager 读 `.pairedVideo`。
struct LivePhotoMovieTransferable: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .movie) { data in
            LivePhotoMovieTransferable(data: data)
        }
    }
}

/// Live Photo 素材（静态图 + 成对视频）。
struct LivePhotoAssets {
    /// 静态图的**原始字节**。
    ///
    /// ⚠️ **必须原样落盘，绝不能经 `UIImage.jpegData()` 重编码。**
    /// Live Photo 的静态图在 Apple maker note 里藏着一个 content identifier，
    /// `PHLivePhoto.request(withResourceFileURLs:)` 靠它把静态图和 .mov 配成一对。
    /// 一旦重编码，那段元数据就没了，配对永远失败 —— 表现为「只显示静态图，长按不播」，
    /// 而且 `request` 只是安静地回 nil，不报错。2026-08-04 陈总反馈的 Live 图不能用就是这个原因。
    let stillData: Data
    /// 静态图该用的扩展名（heic / jpg 等），由资源 UTI 推出。
    /// 存成不匹配的扩展名会干扰 `PHLivePhoto.request` 判断资源类型。
    let stillExtension: String
    /// 成对视频（.mov）的原始字节
    let videoData: Data
}

/// Live Photo 素材提取工具。
///
/// 要求：
/// - `PhotosPicker` 必须配置 `photoLibrary: .shared()`，否则 `item.itemIdentifier` 为 nil；
/// - Info.plist 必须有 `NSPhotoLibraryUsageDescription`，否则 `PHAsset.fetchAssets` 拿不到资产。
enum LivePhotoExtractor {
    /// 从 PhotosPickerItem 提取 Live Photo 的静态图 + 视频。
    /// 普通静态照片返回 nil（非错误，调用方走常规重编码保存即可）。
    static func extractLivePhoto(from item: PhotosPickerItem) async -> LivePhotoAssets? {
        guard let assetId = item.itemIdentifier else {
            print("🟡 [LivePhoto] itemIdentifier 为 nil — 检查 PhotosPicker 是否配 photoLibrary: .shared()")
            return nil
        }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else {
            print("🟡 [LivePhoto] PHAsset.fetchAssets 没找到资产 — 检查 NSPhotoLibraryUsageDescription 与授权状态")
            return nil
        }
        guard asset.mediaSubtypes.contains(.photoLive) else {
            return nil  // 普通静态照片，正常分支
        }

        let resources = PHAssetResource.assetResources(for: asset)
        // 编辑过的 Live Photo 用全尺寸版本，否则用原始版本。
        // 静态图和视频**必须取同一档**，否则 content identifier 对不上，配对照样失败。
        let isEdited = resources.contains { $0.type == .fullSizePairedVideo }
        let videoResource = resources.first { $0.type == (isEdited ? .fullSizePairedVideo : .pairedVideo) }
        let stillResource = resources.first { $0.type == (isEdited ? .fullSizePhoto : .photo) }

        guard let videoResource, let stillResource else {
            print("🔴 [LivePhoto] 是 Live Photo 但资源不全 (edited=\(isEdited), resources=\(resources.map { $0.type.rawValue }))")
            return nil
        }

        guard let videoData = await data(for: videoResource, ext: "mov") else { return nil }
        let stillExtension = UTType(stillResource.uniformTypeIdentifier)?.preferredFilenameExtension ?? "jpg"
        guard let stillData = await data(for: stillResource, ext: stillExtension) else { return nil }

        return LivePhotoAssets(
            stillData: stillData,
            stillExtension: stillExtension,
            videoData: videoData
        )
    }

    /// 把一个 PHAssetResource 读成 Data（经临时文件中转，读完即删）。
    private static func data(for resource: PHAssetResource, ext: String) async -> Data? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("livephoto_\(UUID().uuidString).\(ext)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true   // 允许从 iCloud 下载（用户可能开了「优化 iPhone 储存空间」）
        // 日志要用的信息先取成值类型：PHAssetResource 不是 Sendable，
        // 直接在下面的 @Sendable 闭包里引用它会报并发警告。
        let typeCode = resource.type.rawValue

        return await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: tempURL,
                options: options
            ) { error in
                defer { try? FileManager.default.removeItem(at: tempURL) }
                if let error {
                    print("🔴 [LivePhoto] writeData 失败 (type=\(typeCode)): \(error)")
                    cont.resume(returning: nil)
                    return
                }
                let data = try? Data(contentsOf: tempURL)
                if data == nil {
                    print("🔴 [LivePhoto] 临时文件读取失败 (type=\(typeCode))")
                }
                cont.resume(returning: data)
            }
        }
    }
}
