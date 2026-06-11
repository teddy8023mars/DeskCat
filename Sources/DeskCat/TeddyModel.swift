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
    static let browC = SIMD3<Float>(0.55, 0.37, 0.20)      // 眉毛（比毛色深，表情才能"读"出来）
    static let suitC = SIMD3<Float>(0.25, 0.40, 0.53)      // 西装蓝
    static let shirtC = SIMD3<Float>(0.42, 0.56, 0.66)     // 内衬浅蓝
    static let bowC = SIMD3<Float>(0.66, 0.18, 0.18)       // 领结砖红（压灰度融入暖色调）

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
        // 内衬浅蓝：贴着躯干真实表面、几乎全部藏进躯干，只在胸前露出平贴的色块
        // （之前外凸 0.08，侧看像悬浮的鼓包）
        let chestZ = bodyBlob.surfaceZ(x: 0, y: 0.74)
        bodyBlob.add(blend: 0.03, color: shirtC, SDF.ellipsoid(
            center: [0, 0.76, chestZ - 0.105], radii: [0.17, 0.22, 0.12]
        ))
        // 西装袖子（融进躯干，像缝上去的）
        for side: Float in [-1, 1] {
            bodyBlob.add(blend: 0.06, color: suitC, SDF.capsule(
                from: [side * 0.42, 0.76, 0.05],
                to: [side * 0.62, 0.46, 0.20],
                radius: 0.14
            ))
            // 连指手套式绒毛手掌：靠剪影读出"手"，不靠刻线
            bodyBlob.add(blend: 0.035, color: furC, SDF.sphere(center: [side * 0.66, 0.36, 0.26], radius: 0.13))
            // 拇指鼓包（朝上偏内，软融合进掌心）
            bodyBlob.add(blend: 0.03, color: furC, SDF.sphere(
                center: [side * 0.59, 0.43, 0.31], radius: 0.058
            ))
        }
        // 短腿（绒毛，西装不盖腿；blend 调小避免绒毛色晕染到西装下摆）
        for side: Float in [-1, 1] {
            bodyBlob.add(blend: 0.05, color: furC, SDF.capsule(
                from: [side * 0.30, 0.36, 0.08],
                to: [side * 0.42, 0.24, 0.42],
                radius: 0.19
            ))
            bodyBlob.add(blend: 0.05, color: furC, SDF.ellipsoid(
                center: [side * 0.45, 0.20, 0.52], radii: [0.19, 0.18, 0.22]
            ))
            // 奶油色脚底掌垫（呼应口鼻的奶油色，软融进脚型）
            bodyBlob.add(blend: 0.028, color: furLightC, SDF.ellipsoid(
                center: [side * 0.46, 0.17, 0.70], radii: [0.115, 0.105, 0.05]
            ))
            // 三个脚趾：脚背顶缘的绒毛小圆瓣——缝出来的鼓包，靠剪影读出脚趾
            bodyBlob.add(blend: 0.03, color: furC, SDF.sphere(center: [side * 0.46, 0.345, 0.585], radius: 0.052))
            for toe: Float in [-1, 1] {
                bodyBlob.add(blend: 0.03, color: furC, SDF.sphere(
                    center: [side * 0.46 + toe * 0.10, 0.315, 0.59], radius: 0.052
                ))
            }
        }

        // 红色平绒蝴蝶结：和身体同一套 SDF 软融合"缝"在胸口——
        // 圆鼓的缎面翼呼应全身的软圆形状语言，绒毛着色器自动给它平绒质感
        for side: Float in [-1, 1] {
            bodyBlob.add(blend: 0.025, color: bowC, SDF.ellipsoid(
                center: [side * 0.11, 0.745, 0.41], radii: [0.11, 0.072, 0.055]
            ))
        }
        bodyBlob.add(blend: 0.02, color: bowC, SDF.ellipsoid(
            center: [0, 0.745, 0.44], radii: [0.05, 0.055, 0.045]
        ))

        let bodyGeometry = SDFMesh.geometry(
            blob: bodyBlob,
            boundsMin: [-0.95, -0.10, -0.70],
            boundsMax: [0.95, 1.20, 0.95],
            resolution: 104 // 手掌缝线和脚趾豆是细结构，需要更密的采样
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
        // 眉毛（深色、舒展的缓拱——友好中性，不上挑不耷拉）
        for side: Float in [-1, 1] {
            headBlob.add(blend: 0.035, color: browC, SDF.ellipsoid(
                center: [side * 0.25, 0.67, 0.50], radii: [0.165, 0.048, 0.055]
            ))
        }
        // 奶油色口鼻：上窄下宽，带 Ted 标志性的厚下巴
        // （侧看突出量收敛：前缘从头球面外 ~0.18 收到 ~0.08，贴脸不撅嘴）
        headBlob.add(blend: 0.07, color: furLightC, SDF.ellipsoid(
            center: [0, 0.10, 0.46], radii: [0.38, 0.28, 0.22]
        ))
        headBlob.add(blend: 0.08, color: furLightC, SDF.ellipsoid(
            center: [0, -0.04, 0.44], radii: [0.30, 0.17, 0.18]
        ))
        // 脖子（藏进身体，转头时不露缝）
        headBlob.add(blend: 0.12, color: furC, SDF.capsule(from: [0, -0.12, 0], to: [0, 0.15, 0], radius: 0.32))

        // ——— 嘴：闭合的立体缝（参考 Ted 剧照——凹槽缝 + 周围的肉感结构） ———
        let mouthSurfZ = headBlob.surfaceZ(x: 0, y: 0.12)
        // 颊肉：嘴线上方两侧的鼓起（立体感来自嘴周围的结构）
        for side: Float in [-1, 1] {
            headBlob.add(blend: 0.06, color: furLightC, SDF.ellipsoid(
                center: [side * 0.11, 0.175, mouthSurfZ - 0.055], radii: [0.105, 0.085, 0.07]
            ))
        }
        // 下巴鼓起（嘴线下方）
        headBlob.add(blend: 0.07, color: furLightC, SDF.ellipsoid(
            center: [0, -0.01, mouthSurfZ - 0.085], radii: [0.13, 0.08, 0.07]
        ))
        // 嘴缝：沿微笑曲线挖一道浅凹槽（阴影自然落进去，任何角度都立体）
        let seamC = SIMD3<Float>(0.46, 0.33, 0.22) // 凹槽内的暖阴影色
        var seamPts: [SIMD3<Float>] = []
        for i in 0...10 {
            let t = Float(i) / 10 * 2 - 1
            let x = t * 0.215
            let y = 0.105 + 0.05 * t * t
            seamPts.append([x, y, headBlob.surfaceZ(x: x, y: y) + 0.016])
        }
        for i in 0..<(seamPts.count - 1) {
            headBlob.subtract(blend: 0.018, color: seamC, SDF.capsule(
                from: seamPts[i], to: seamPts[i + 1], radius: 0.026
            ))
        }
        // 人中：鼻底到嘴缝的竖凹槽
        let philtrumTop = SIMD3<Float>(0, 0.245, headBlob.surfaceZ(x: 0, y: 0.245) + 0.014)
        let philtrumBottom = SIMD3<Float>(0, 0.13, headBlob.surfaceZ(x: 0, y: 0.13) + 0.014)
        headBlob.subtract(blend: 0.016, color: seamC, SDF.capsule(
            from: philtrumTop, to: philtrumBottom, radius: 0.02
        ))

        let headGeometry = SDFMesh.geometry(
            blob: headBlob,
            boundsMin: [-1.00, -0.50, -0.80],
            boundsMax: [1.00, 1.15, 0.95],
            resolution: 116 // 嘴缝凹槽很细，需要更高的采样密度
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


        // 眼睛：加大 + 琥珀色虹膜 + 双高光——眼睛承载灵动感
        var eyes: [SCNNode] = []
        let eyeSurfZ = headBlob.surfaceZ(x: 0.22, y: 0.47)
        for side: CGFloat in [-1, 1] {
            let eye = node(SCNSphere(radius: 0.078), NSColor(red: 0.40, green: 0.25, blue: 0.12, alpha: 1))
            eye.position = SCNVector3(side * 0.22, 0.47, CGFloat(eyeSurfZ - 0.012))

            let pupil = node(SCNSphere(radius: 0.042), .black)
            pupil.position = SCNVector3(0, 0, 0.042)
            eye.addChildNode(pupil)

            let highlight = node(SCNSphere(radius: 0.019), .white)
            highlight.position = SCNVector3(0.020, 0.024, 0.064)
            eye.addChildNode(highlight)

            let sparkle = node(SCNSphere(radius: 0.009), .white)
            sparkle.position = SCNVector3(-0.020, -0.016, 0.070)
            eye.addChildNode(sparkle)

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

    /// 沿 3D 折线生成连续缝线：球关节 + 圆柱段
    private static func stitchLine(points: [SIMD3<Float>], radius: CGFloat, color: NSColor) -> SCNNode {
        let line = SCNNode()
        for (i, p) in points.enumerated() {
            let joint = node(SCNSphere(radius: radius), color)
            joint.simdPosition = p
            line.addChildNode(joint)

            guard i + 1 < points.count else { continue }
            let q = points[i + 1]
            let dir = q - p
            let length = simd_length(dir)
            guard length > 1e-5 else { continue }
            let segment = node(SCNCylinder(radius: radius, height: CGFloat(length)), color)
            segment.simdPosition = (p + q) / 2
            segment.simdOrientation = simd_quatf(from: [0, 1, 0], to: dir / length)
            line.addChildNode(segment)
        }
        return line
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
