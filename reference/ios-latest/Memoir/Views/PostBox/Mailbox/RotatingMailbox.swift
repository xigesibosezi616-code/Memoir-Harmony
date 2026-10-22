import SwiftUI
import UIKit

/// 转到 `yaw`、前后晃到 `pitch` 的邮筒 —— 只管画，不管手势（手势在 `MailboxStage`）。
///
/// 还是原来那张手绘邮筒（2026-10-20 产品定：保留手绘线稿，不重做立体模型），拆成两层
/// （`Scripts/make_mailbox_layers.py`）：
/// - 筒身层 `<邮筒图>_Body`：轮廓、明暗排线、帽顶、领圈、底座 —— 绕竖轴转一圈样子不变，原样画
/// - 部件层 `<邮筒图>_Parts`：投信口、铭牌、logo、字样、小门、帽檐的铆钉 —— 着色器按圆筒曲率绕到当前角度
///   （`MailboxSurface.metal`），转到边上被压扁，转到背面看不见（背面是素的）；铆钉一圈 20 颗，转到哪都有
///
/// 前后晃是整个邮筒绕底座前后倾（像被手拨了一下的铁家伙），带一点透视。
/// 新主题没拆两层的话就画整张原图、转不动 —— 不会坏
struct RotatingMailbox: View {
    let imageName: String
    /// 左右转过的角度（弧度）。正 = 筒面往右走
    let yaw: Double
    /// 前后倾的角度（弧度）。正 = 顶往后仰
    let pitch: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        content
            .rotation3DEffect(.radians(pitch), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.45)
    }

    @ViewBuilder
    private var content: some View {
        if let layers = MailboxLayers.of(imageName) {
            Image(layers.body)
                .resizable()
                .scaledToFit()
                .overlay {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.white)
                            .colorEffect(ShaderLibrary.mailboxSurface(
                                .image(Image(layers.parts)),
                                .float2(geo.size),
                                .float(yaw),
                                .float(displayScale)
                            ))
                    }
                }
        } else {
            Image(imageName)
                .resizable()
                .scaledToFit()
        }
    }
}

/// 邮筒图上的几何（按图宽的比例）。原图 678 宽，和 `MailboxSurface.metal` 的常数是同一套
enum MailboxGeometry {
    /// 筒身半径（到轮廓线内沿）：手指在正面拨多远，筒面就转过多少
    static let bodyRadius: CGFloat = 208.0 / 678.0
}

/// 一个邮筒图拆出来的两层叫什么、有没有
enum MailboxLayers {
    struct Names {
        let body: String
        let parts: String
    }

    @MainActor private static var cache: [String: Names?] = [:]

    /// 邮筒图 `Mailbox_Kent` → `Mailbox_Kent_Body` / `Mailbox_Kent_Parts`。两层都在才算有
    @MainActor
    static func of(_ imageName: String) -> Names? {
        if let hit = cache[imageName] { return hit }
        let names = Names(body: imageName + "_Body", parts: imageName + "_Parts")
        let found = UIImage(named: names.body) != nil && UIImage(named: names.parts) != nil ? names : nil
        if found == nil { NSLog("⚠️ [Mailbox] %@ 没有拆好的两层，画整张原图、转不动", imageName) }
        cache[imageName] = found
        return found
    }
}
