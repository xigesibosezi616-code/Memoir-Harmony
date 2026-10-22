import QuartzCore
import CoreGraphics

/// 把一本书当成一个**有厚度的长方体**，算出封面、书脊各自的 3D 投影。
///
/// **为什么不直接用 `rotation3DEffect`**：它只能把一张平面转个角度，书转过去时看不到厚度，
/// 像一张卡片。要看到书脊，书脊得是另一个面，而且必须和封面绕**同一根轴**转、用**同一个透视**，
/// 两个面的交界才对得上。`rotation3DEffect` 的透视按各视图自己的尺寸算，封面和书脊宽窄不同，
/// 透视就不一样，交界会错开。所以这里自己拼 `CATransform3D`，所有面共用一套几何。
///
/// **不依赖 App 里的任何类型**（纯 CoreGraphics / QuartzCore），隔离 harness 可以单独编这个文件验证投影。
///
/// 坐标约定（Core Animation）：x 向右、y 向下、z 朝向观看者；盒子中心在原点。
enum BookBox {
    /// 视点到封面的距离（pt）。越小透视越强；520 对 iPhone 上一本 150pt 高的书比较克制
    static let eyeDistance: CGFloat = 520

    enum Face {
        case cover
        /// 书脊：封面左边那一面
        case spine
        /// 书口：封面右边那一面（一页页纸的边）。写日记前选本子的转盘里，右边那几本露出来的是它
        case foreEdge
    }

    /// 整本书转完之后、透视之前在场景里挪到哪。
    ///
    /// 书架上拿起的那本不挪（全是 0），透视的消失点就在书的中心。
    /// 写日记前选本子的转盘（`NotebookCarousel`）是好几本书**共用一个视点**：每本先挪到自己的位置再一起透视，
    /// 偏在两边的书才会像真的那样露出侧面、远近也对得上
    struct Offset {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var z: CGFloat = 0
        static let zero = Offset()
    }

    /// 某个面要用的投影。
    ///
    /// - Parameters:
    ///   - face: 哪个面
    ///   - angle: 整本书绕竖轴转的角度（弧度）
    ///   - coverSize: 封面（盒子正面）的宽高
    ///   - depth: 书的厚度
    ///   - faceCenter: 这个面视图里，对应它在盒子上中心点的那个点（面视图本地坐标）
    ///   - boxCenter: 盒子中心在面视图本地坐标里应落在哪 —— 所有面放在同一个左上对齐的容器里时，它们是同一个点。
    ///     有 `offset` 时它是视点（透视的消失点）在容器里的位置，书在它的基础上再挪 `offset`
    ///   - eye: 视点到 z = 0 平面的距离
    ///   - offset: 整本书在场景里挪到哪（见 `Offset`）
    static func transform(
        face: Face,
        angle: CGFloat,
        coverSize: CGSize,
        depth: CGFloat,
        faceCenter: CGPoint,
        boxCenter: CGPoint,
        eye: CGFloat = eyeDistance,
        offset: Offset = .zero
    ) -> CATransform3D {
        let (faceAngle, offsetX, offsetZ) = placement(face, coverSize: coverSize, depth: depth)

        // 面视图 → 以它自己的中心为原点
        var t = CATransform3DMakeTranslation(-faceCenter.x, -faceCenter.y, 0)
        // 转到它在盒子上的朝向，放到它在盒子上的位置
        t = CATransform3DConcat(t, CATransform3DMakeRotation(faceAngle, 0, 1, 0))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(offsetX, 0, offsetZ))
        // 整本书绕中心竖轴转
        t = CATransform3DConcat(t, CATransform3DMakeRotation(angle, 0, 1, 0))
        // 把封面所在的平面挪回 z = 0：不转的时候投影出来和平面的书一样大，拿起那一下不会"跳"
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(0, 0, -depth / 2))
        // 挪到它在场景里的位置
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(offset.x, offset.y, offset.z))
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / eye
        t = CATransform3DConcat(t, perspective)
        // 盒子中心放回面视图里该在的位置
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(boxCenter.x, boxCenter.y, 0))
        return t
    }

    /// 这个面此刻是否朝向观看者（背过去的面不画）
    static func isVisible(face: Face, angle: CGFloat) -> Bool {
        let faceAngle = placement(face, coverSize: .zero, depth: 0).angle
        let r = CATransform3DConcat(
            CATransform3DMakeRotation(faceAngle, 0, 1, 0),
            CATransform3DMakeRotation(angle, 0, 1, 0)
        )
        // 面的法线 (0,0,1) 转过去之后的 z 分量 > 0 = 朝着观看者
        return r.m33 > 0.01
    }

    /// 共用视点的场景里，这个面此刻是否朝向视点。
    ///
    /// 和上面那个不一样的地方：书偏在一边时，哪怕没转，靠里的那个侧面也朝着视点（站在书架正中，看得见右边那本的书脊）。
    /// 所以要拿「法线」和「面中心 → 视点」比，不能只看法线朝不朝前
    static func isVisible(face: Face, angle: CGFloat, coverSize: CGSize, depth: CGFloat, eye: CGFloat, offset: Offset) -> Bool {
        let (faceAngle, localX, localZ) = placement(face, coverSize: coverSize, depth: depth)
        let turn = CATransform3DMakeRotation(angle, 0, 1, 0)
        let normal = CATransform3DConcat(CATransform3DMakeRotation(faceAngle, 0, 1, 0), turn)
        // 面中心：盒子上的位置 → 跟着整本书转 → 封面平面挪回 z = 0 → 挪到场景里的位置
        let x = localX * turn.m11 + localZ * turn.m31 + offset.x
        let z = localX * turn.m13 + localZ * turn.m33 - depth / 2 + offset.z
        // 视点在 (0, offset.y 那一层无所谓, eye)：只看水平面里的朝向
        return normal.m31 * (0 - x) + normal.m33 * (eye - z) > 0.01
    }

    /// 面在盒子上的朝向，以及面中心相对盒子中心的位置（x, z）
    private static func placement(_ face: Face, coverSize: CGSize, depth: CGFloat) -> (angle: CGFloat, x: CGFloat, z: CGFloat) {
        switch face {
        case .cover: return (0, 0, depth / 2)
        case .spine: return (spineFaceAngle, -coverSize.width / 2, 0)
        case .foreEdge: return (-spineFaceAngle, coverSize.width / 2, 0)
        }
    }

    /// 拿起时转到的角度（弧度）：朝露出书脊的那个方向转 `degrees` 度。
    ///
    /// 方向不靠记 Core Animation 的旋转正负号约定，直接用上面的可见性判断挑 ——
    /// 哪个方向能看见书脊，就往哪个方向转。
    static func liftAngle(degrees: CGFloat) -> CGFloat {
        let radians = degrees * .pi / 180
        return isVisible(face: .spine, angle: radians) ? radians : -radians
    }

    /// 书脊这一面在盒子上的朝向：法线要指向左边（-x）。
    /// 同样不靠记正负号约定：两个候选里挑转完法线 x 分量为负的那个。
    private static let spineFaceAngle: CGFloat = {
        CATransform3DMakeRotation(.pi / 2, 0, 1, 0).m31 < 0 ? .pi / 2 : -.pi / 2
    }()
}
