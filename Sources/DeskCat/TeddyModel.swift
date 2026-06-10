import AppKit
import SceneKit
import simd

/// 代码生成的泰迪熊，原型为电影 Ted 2。
/// 身体和头分别由 SDF smooth-min 融合成无缝的有机绒毛整体（参考 vibe modeling
/// 最佳实践），眼睛/鼻子/眼镜等配件保持锐利的独立几何体形成质感对比。
struct TeddyModel {
    let root: SCNNode
    let head: SCNNode
    let body: SCNNode
    let eyes: [SCNNode]
    let ears: [SCNNode]
}

enum TeddyBuilder {
    // 配色（取自 Ted 2 剧照；SIMD 值供 SDF 顶点色使用）
    static let furC = SIMD3<Float>(0.73, 0.54, 0.33)       // 蜂蜜棕绒毛
    static let furLightC = SIMD3<Float>(0.89, 0.77, 0.60)  // 奶油色口鼻
    static let padC = SIMD3<Float>(0.55, 0.38, 0.23)
    static let suitC = SIMD3<Float>(0.25, 0.40, 0.53)      // 西装蓝
    static let shirtC = SIMD3<Float>(0.42, 0.56, 0.66)     // 内衬浅蓝

    static let fur = NSColor(red: 0.73, green: 0.54, blue: 0.33, alpha: 1)
    static let noseColor = NSColor(red: 0.16, green: 0.10, blue: 0.08, alpha: 1)
    static let irisColor = NSColor(red: 0.24, green: 0.15, blue: 0.09, alpha: 1)
    static let frameColor = NSColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)

    static func build() -> TeddyModel {
        let root = SCNNode()
        root.name = "Teddy"

        // ============ 身体：矮壮短腿（Ted 的头占全身近四成，身体要小） ============
        var bodyBlob = SDFBlob()
        // 调试：DC_TESTSPHERE=1 时只渲染一个纯球，隔离网格化引擎问题
        if ProcessInfo.processInfo.environment["DC_TESTSPHERE"] != nil {
            bodyBlob.add(blend: 0.1, color: furC, SDF.sphere(center: [0, 0.56, 0], radius: 0.55))
            let g = SDFMesh.geometry(blob: bodyBlob, boundsMin: [-0.8, -0.2, -0.8], boundsMax: [0.8, 1.3, 0.8], resolution: 72)
            let n = SCNNode(geometry: g)
            root.addChildNode(n)
            let head = SCNNode(); head.name = "Head"; head.position = SCNVector3(0, 1.1, 0)
            root.addChildNode(head)
            return TeddyModel(root: root, head: head, body: n, eyes: [], ears: [])
        }
        // 躯干（西装蓝）
        bodyBlob.add(blend: 0.1, color: suitC, SDF.ellipsoid(center: [0, 0.52, 0], radii: [0.56, 0.50, 0.46]))
        // 内衬浅蓝（大部分藏在躯干里，只露出胸前一片）
        bodyBlob.add(blend: 0.03, color: shirtC, SDF.ellipsoid(center: [0, 0.72, 0.38], radii: [0.15, 0.21, 0.12]))
        // 西装袖子（融进躯干，像缝上去的）
        for side: Float in [-1, 1] {
            bodyBlob.add(blend: 0.06, color: suitC, SDF.capsule(
                from: [side * 0.42, 0.76, 0.05],
                to: [side * 0.62, 0.46, 0.20],
                radius: 0.14
            ))
            // 露出的绒毛手掌（小 blend 让袖口像缝制的边）
            bodyBlob.add(blend: 0.022, color: furC, SDF.sphere(center: [side * 0.66, 0.38, 0.26], radius: 0.135))
        }
        // 短腿（绒毛，西装不盖腿）
        for side: Float in [-1, 1] {
            bodyBlob.add(blend: 0.07, color: furC, SDF.capsule(
                from: [side * 0.30, 0.36, 0.08],
                to: [side * 0.42, 0.24, 0.42],
                radius: 0.19
            ))
            bodyBlob.add(blend: 0.05, color: furC, SDF.ellipsoid(
                center: [side * 0.45, 0.20, 0.52], radii: [0.19, 0.18, 0.22]
            ))
            // 深色脚掌（颜色区域，几乎不改变形状）
            bodyBlob.add(blend: 0.025, color: padC, SDF.ellipsoid(
                center: [side * 0.47, 0.24, 0.72], radii: [0.115, 0.115, 0.04]
            ))
        }

        let bodyGeometry = SDFMesh.geometry(
            blob: bodyBlob,
            boundsMin: [-0.95, -0.10, -0.70],
            boundsMax: [0.95, 1.20, 0.95],
            resolution: 72
        )
        let body = SCNNode(geometry: bodyGeometry)
        body.name = "Body"
        root.addChildNode(body)

        // 西装扣子（贴着融合后的真实表面）
        for y: Float in [0.56, 0.42, 0.28] {
            let z = bodyBlob.surfaceZ(x: 0, y: y)
            let button = node(SCNSphere(radius: 0.026), frameColor)
            button.position = SCNVector3(0, CGFloat(y), CGFloat(z + 0.008))
            root.addChildNode(button)
        }

        // ============ 头：巨大的宽圆头（比身体还宽，Ted 的标志比例） ============
        let head = SCNNode()
        head.name = "Head"
        head.position = SCNVector3(0, 1.00, 0)
        root.addChildNode(head)

        var headBlob = SDFBlob()
        // 一整个宽圆的大块头——没有独立腮帮，宽度本身就是脸
        headBlob.add(blend: 0.1, color: furC, SDF.ellipsoid(center: [0, 0.36, 0], radii: [0.80, 0.64, 0.60]))
        // 眉骨（眼镜上方两道独立隆起的绒毛丘——Ted 表情的灵魂）
        for side: Float in [-1, 1] {
            headBlob.add(blend: 0.04, color: furC, SDF.ellipsoid(
                center: [side * 0.24, 0.66, 0.50], radii: [0.16, 0.055, 0.06]
            ))
        }
        // 奶油色口鼻：上窄下宽，带 Ted 标志性的厚下巴
        headBlob.add(blend: 0.07, color: furLightC, SDF.ellipsoid(
            center: [0, 0.10, 0.52], radii: [0.38, 0.28, 0.26]
        ))
        headBlob.add(blend: 0.08, color: furLightC, SDF.ellipsoid(
            center: [0, -0.04, 0.48], radii: [0.30, 0.17, 0.21]
        ))
        // 脖子（藏进身体，转头时不露缝）
        headBlob.add(blend: 0.12, color: furC, SDF.capsule(from: [0, -0.12, 0], to: [0, 0.15, 0], radius: 0.32))

        let headGeometry = SDFMesh.geometry(
            blob: headBlob,
            boundsMin: [-1.00, -0.50, -0.80],
            boundsMax: [1.00, 1.15, 0.95],
            resolution: 80
        )
        head.addChildNode(SCNNode(geometry: headGeometry))

        // 耳朵：大头顶角的小圆耳（缝上去的玩具耳朵本来就有折痕，且保留抖耳朵动画）
        var ears: [SCNNode] = []
        for side: CGFloat in [-1, 1] {
            let ear = node(SCNSphere(radius: 0.20), fur)
            ear.scale = SCNVector3(1, 1, 0.55)
            ear.position = SCNVector3(side * 0.56, 0.86, -0.06)
            addFuzz(ear)
            head.addChildNode(ear)
            ears.append(ear)
        }

        // ——— 五官配件：贴着融合后的真实曲面 ———
        // 小黑鼻（在口鼻顶部，Ted 的鼻子不大）
        let noseSurfZ = headBlob.surfaceZ(x: 0, y: 0.30)
        let nose = node(SCNSphere(radius: 0.105), noseColor)
        nose.scale = SCNVector3(1.15, 0.78, 0.5)
        nose.position = SCNVector3(0, 0.30, CGFloat(noseSurfZ + 0.012))
        head.addChildNode(nose)

        // 缝线嘴：鼻下短竖线 + 宽幅浅弧下撇嘴
        let mouthZ = CGFloat(headBlob.surfaceZ(x: 0, y: 0.10) + 0.006)
        let stitch = node(SCNCylinder(radius: 0.012, height: 0.10), noseColor)
        stitch.position = SCNVector3(0, 0.205, mouthZ - 0.01)
        head.addChildNode(stitch)
        for side: CGFloat in [-1, 1] {
            let lipInner = node(SCNCylinder(radius: 0.012, height: 0.16), noseColor)
            lipInner.position = SCNVector3(side * 0.078, 0.135, mouthZ)
            lipInner.eulerAngles = SCNVector3(0.20, 0, side * 1.42)
            head.addChildNode(lipInner)

            let lipOuter = node(SCNCylinder(radius: 0.012, height: 0.13), noseColor)
            lipOuter.position = SCNVector3(side * 0.205, 0.085, mouthZ - 0.045)
            lipOuter.eulerAngles = SCNVector3(0.28, 0, side * 1.15)
            head.addChildNode(lipOuter)
        }

        // 小黑豆眼（贴着口鼻上沿、间距宽——参考图里眼睛很小）
        var eyes: [SCNNode] = []
        let eyeSurfZ = headBlob.surfaceZ(x: 0.22, y: 0.47)
        for side: CGFloat in [-1, 1] {
            let eye = node(SCNSphere(radius: 0.06), irisColor)
            eye.position = SCNVector3(side * 0.22, 0.47, CGFloat(eyeSurfZ - 0.008))

            let pupil = node(SCNSphere(radius: 0.03), .black)
            pupil.position = SCNVector3(0, 0, 0.036)
            eye.addChildNode(pupil)

            let highlight = node(SCNSphere(radius: 0.014), .white)
            highlight.position = SCNVector3(0.015, 0.017, 0.052)
            eye.addChildNode(highlight)

            head.addChildNode(eye)
            eyes.append(eye)
        }

        // 细方框眼镜（更宽，横跨大脸）
        let glassesZ = CGFloat(headBlob.surfaceZ(x: 0, y: 0.46) + 0.05)
        let glasses = SCNNode()
        glasses.position = SCNVector3(0, 0.46, glassesZ)
        for side: CGFloat in [-1, 1] {
            let frame = node(rectFrameShape(), frameColor)
            frame.position = SCNVector3(side * 0.215, 0, 0)
            glasses.addChildNode(frame)

            let temple = node(SCNCylinder(radius: 0.009, height: 0.52), frameColor)
            temple.position = SCNVector3(side * 0.40, 0.04, -0.25)
            temple.eulerAngles = SCNVector3(Double.pi / 2, 0, 0)
            glasses.addChildNode(temple)
        }
        let bridge = node(SCNCylinder(radius: 0.010, height: 0.08), frameColor)
        bridge.position = SCNVector3(0, 0.03, 0)
        bridge.eulerAngles = SCNVector3(0, 0, Double.pi / 2)
        glasses.addChildNode(bridge)
        head.addChildNode(glasses)

        return TeddyModel(root: root, head: head, body: body, eyes: eyes, ears: ears)
    }

    /// 细边圆角矩形镜框
    private static func rectFrameShape() -> SCNGeometry {
        let outer = NSBezierPath(
            roundedRect: NSRect(x: -0.155, y: -0.10, width: 0.31, height: 0.20),
            xRadius: 0.05, yRadius: 0.05
        )
        let inner = NSBezierPath(
            roundedRect: NSRect(x: -0.141, y: -0.086, width: 0.282, height: 0.172),
            xRadius: 0.042, yRadius: 0.042
        )
        outer.append(inner.reversed)
        outer.windingRule = .nonZero
        outer.flatness = 0.0008
        return SCNShape(path: outer, extrusionDepth: 0.026)
    }

    private static func node(_ geometry: SCNGeometry, _ color: NSColor) -> SCNNode {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = color
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    /// 给独立绒毛节点加上和 SDF 网格一致的边缘绒毛高光
    private static func addFuzz(_ node: SCNNode) {
        node.geometry?.firstMaterial?.shaderModifiers = [
            .surface: """
            float fuzz = pow(1.0 - max(0.0, dot(normalize(_surface.view), _surface.normal)), 2.2);
            _surface.diffuse.rgb += fuzz * 0.4 * _surface.diffuse.rgb;
            """
        ]
    }
}
