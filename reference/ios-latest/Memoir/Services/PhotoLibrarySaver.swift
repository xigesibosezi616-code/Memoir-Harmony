import Foundation
import Photos

/// 把尺素相机拍的照片存一份进系统相册。
///
/// **只管相机拍的，不碰从相册选的**（那本来就在相册里）。
/// 相机拍下即存，不给开关（2026-08-06 决策）—— 用户在尺素里按快门，
/// 拍到的东西理应和用系统相机一样留在相册里，找不到才是意外。
///
/// 日记正文里放的是**裁过的方图**，完整的那一张只在相册里 ——
/// 这也是「拍下就存」的另一层理由：不存就等于拍完即弃。
///
/// **失败一律静默**：存相册是「顺手多给一份」，不是主流程。用户没授权、相册满了，
/// 都不该打断写日记 —— 日记那份已经在沙盒里存好了。
enum PhotoLibrarySaver {

    /// 存一张相机拍的照片进系统相册。传了 `movieURL` 就作为 Live Photo 存。
    /// - Parameters:
    ///   - stillData: **未裁剪**的原始静态图字节（元数据要完整，否则相册里也配不成 Live Photo）
    ///   - movieURL: 成对视频；nil 表示普通静态照片
    static func saveCameraShot(stillData: Data, movieURL: URL?) async {
        // addOnly 权限：只申请「添加」而不是「读取整个相册」，是能满足需求的最小权限
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            print("🟡 [PhotoLibrary] 未获授权，跳过存相册（status=\(status.rawValue)）")
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: stillData, options: nil)

                if let movieURL {
                    let videoOptions = PHAssetResourceCreationOptions()
                    // 视频文件在 tmp/，交给系统后我们自己就不再需要它了
                    videoOptions.shouldMoveFile = false
                    request.addResource(with: .pairedVideo, fileURL: movieURL, options: videoOptions)
                }
            }
            print("🟢 [PhotoLibrary] 已存入相册（live=\(movieURL != nil)）")
        } catch {
            print("🔴 [PhotoLibrary] 存入相册失败：\(error.localizedDescription)")
        }
    }
}
