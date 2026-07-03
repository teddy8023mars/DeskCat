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
    static let suitC = SIMD3<Float>(0.44, 0.47, 0.52)      // 蓝灰西装（Ted 剧照的板岩灰）
    static let suitSeamC = SIMD3<Float>(0.30, 0.33, 0.38)  // 前襟缝线阴影
    static let shirtC = SIMD3<Float>(0.93, 0.94, 0.96)     // 白衬衫
    static let tieC = SIMD3<Float>(0.20, 0.36, 0.62)       // 领带蓝

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

        // ——— 西装细节（参考 Ted 剧照）：V 字翻领、白衬衫、蓝领带、前襟闭合缝 ———
        // 贴胸口曲面取点（长结构沿曲面分段，避免直线段中段埋进表面）
        func onChest(_ x: Float, _ y: Float, _ inset: Float) -> SIMD3<Float> {
            [x, y, bodyBlob.surfaceZ(x: x, y: y) - inset]
        }
        // 白衬衫：藏进胸口的 V 形浅色区，露在两条翻领之间
        bodyBlob.add(blend: 0.02, color: shirtC, SDF.ellipsoid(
            center: onChest(0, 0.78, 0.06), radii: [0.155, 0.16, 0.09]
        ))
        bodyBlob.add(blend: 0.02, color: shirtC, SDF.ellipsoid(
            center: onChest(0, 0.62, 0.065), radii: [0.09, 0.11, 0.08]
        ))
        // 蓝领带：领结小球 + 贴曲面的三段窄条（一直垂到 V 字底）
        bodyBlob.add(blend: 0.015, color: tieC, SDF.sphere(center: onChest(0, 0.875, 0.015), radius: 0.05))
        let tiePts = [
            onChest(0, 0.85, 0.008), onChest(0, 0.76, 0.008),
            onChest(0, 0.66, 0.008), onChest(0, 0.56, 0.008),
        ]
        for i in 0..<(tiePts.count - 1) {
            bodyBlob.add(blend: 0.015, color: tieC, SDF.capsule(from: tiePts[i], to: tiePts[i + 1], radius: 0.040))
        }
        // 西装翻领：从肩颈斜向胸口中线的两条隆起，框出 V 字（开口要宽过下巴的遮挡）
        for side: Float in [-1, 1] {
            let lapelPts = [
                onChest(side * 0.20, 0.875, 0.012),
                onChest(side * 0.125, 0.70, 0.012),
                onChest(side * 0.045, 0.555, 0.012),
            ]
            for i in 0..<(lapelPts.count - 1) {
                bodyBlob.add(blend: 0.022, color: suitC, SDF.capsule(from: lapelPts[i], to: lapelPts[i + 1], radius: 0.048))
            }
            // 翻领内缘折线：细凹缝让 V 字轮廓锐利可读
            let lapelEdgePts = [
                onChest(side * 0.145, 0.86, -0.012),
                onChest(side * 0.082, 0.70, -0.012),
                onChest(side * 0.018, 0.56, -0.012),
            ]
            for i in 0..<(lapelEdgePts.count - 1) {
                bodyBlob.subtract(blend: 0.008, color: suitSeamC, SDF.capsule(
                    from: lapelEdgePts[i], to: lapelEdgePts[i + 1], radius: 0.012
                ))
            }
        }
        // 前襟闭合缝：V 字底到下摆的细凹槽（负 inset = 浮在表面外往里挖）
        let frontSeamPts = [onChest(0, 0.545, -0.014), onChest(0, 0.40, -0.014), onChest(0, 0.26, -0.014)]
        for i in 0..<(frontSeamPts.count - 1) {
            bodyBlob.subtract(blend: 0.01, color: suitSeamC, SDF.capsule(from: frontSeamPts[i], to: frontSeamPts[i + 1], radius: 0.018))
        }

        let bodyBoundsMin = SIMD3<Float>(-0.95, -0.10, -0.70)
        let bodyBoundsMax = SIMD3<Float>(0.95, 1.20, 0.95)
        let bodyGeometry = SDFMesh.geometry(
            blob: bodyBlob,
            boundsMin: bodyBoundsMin,
            boundsMax: bodyBoundsMax,
            resolution: 104 // 手掌缝线和脚趾豆是细结构，需要更密的采样
        )
        let body = SCNNode(geometry: bodyGeometry)
        body.name = "Body"
        root.addChildNode(body)
        // 壳层毛发用低分辨率网格 + 剔除布料三角形：身体 ~70% 是西装（整层
        // discard），16 层壳白画一遍全身是最大的 GPU 浪费源
        let bodyShell = SDFMesh.furOnly(SDFMesh.mesh(
            blob: bodyBlob, boundsMin: bodyBoundsMin, boundsMax: bodyBoundsMax, resolution: 64
        ))
        FurShell.addMerged(to: body, data: bodyShell, length: 0.05)

        // 西装扣子：前襟缝上的两颗（参考剧照在腰部）
        for y: Float in [0.46, 0.36] {
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
        // 一整个宽圆的大块头——没有独立腮帮，宽度本身就是脸。
        // 前后深度压扁（z 0.60→0.52）：侧看后脑到眼镜的距离不能是鼻尖到眼镜的
        // 三倍，否则整个头是气球、五官像贴纸
        headBlob.add(blend: 0.1, color: furC, SDF.ellipsoid(center: [0, 0.36, 0], radii: [0.80, 0.62, 0.52]))
        // 眉毛（深色、舒展的缓拱——友好中性，不上挑不耷拉）
        for side: Float in [-1, 1] {
            headBlob.add(blend: 0.035, color: browC, SDF.ellipsoid(
                center: [side * 0.25, 0.67, 0.50], radii: [0.165, 0.048, 0.055]
            ))
        }
        // 奶油色口鼻：上窄下宽，带 Ted 标志性的厚下巴。
        // 突出量是泰迪熊侧面轮廓的灵魂——完全收平侧看就是没脸的圆球；
        // 之前"撅嘴"的病根是吻部太窄太尖，解法是加宽加圆而不是缩没
        headBlob.add(blend: 0.07, color: furLightC, SDF.ellipsoid(
            center: [0, 0.11, 0.50], radii: [0.40, 0.30, 0.26]
        ))
        headBlob.add(blend: 0.08, color: furLightC, SDF.ellipsoid(
            center: [0, -0.03, 0.47], radii: [0.32, 0.18, 0.20]
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

        let headBoundsMin = SIMD3<Float>(-1.00, -0.50, -0.80)
        let headBoundsMax = SIMD3<Float>(1.00, 1.15, 0.95)
        let headGeometry = SDFMesh.geometry(
            blob: headBlob,
            boundsMin: headBoundsMin,
            boundsMax: headBoundsMax,
            resolution: 116 // 嘴缝凹槽很细，需要更高的采样密度
        )
        let headGeometryNode = SCNNode(geometry: headGeometry)
        head.addChildNode(headGeometryNode)
        // 头部全是绒毛，壳层同样只需低分辨率网格（发丝细节来自高度图）
        let headShell = SDFMesh.mesh(
            blob: headBlob, boundsMin: headBoundsMin, boundsMax: headBoundsMax, resolution: 64
        )
        FurShell.addMerged(to: headGeometryNode, data: headShell, length: 0.046)

        // 耳朵：大头顶角的小圆耳（缝上去的玩具耳朵本来就有折痕，且保留抖耳朵动画）
        var ears: [SCNNode] = []
        for side: CGFloat in [-1, 1] {
            let ear = node(SCNSphere(radius: 0.20), fur)
            ear.scale = SCNVector3(1, 1, 0.55)
            ear.position = SCNVector3(side * 0.56, 0.86, -0.06)
            addFuzz(ear)
            FurShell.add(to: ear, length: 0.035, density: 44, color: fur)
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

            // 镜腿：从镜框外缘斜向后贴着太阳穴曲面分段铺设，末端沉进绒毛。
            // 直圆柱悬在半空，侧面看就是几截漂浮的黑线（正脸被镜框挡住才没暴露）
            let s = Float(side)
            let templeY: Float = 0.50 // 头部空间（镜框竖直中心偏上一点）
            // 横向偏移要浮在绒毛壳层(0.046)之上，埋进毛里会被发丝裁成虚线
            var templePts: [SIMD3<Float>] = [[s * 0.37, templeY, Float(glassesZ)]]
            for z: Float in [0.30, 0.10] {
                templePts.append([s * (headBlob.surfaceX(y: templeY, z: z) + 0.042), templeY, z])
            }
            templePts.append([s * (headBlob.surfaceX(y: templeY, z: -0.08) - 0.015), templeY, -0.08])
            head.addChildNode(stitchLine(points: templePts, radius: 0.011, color: frameColor))
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

    /// 给独立绒毛节点挂上和 SDF 网格同一个表面着色器：只有边缘光没有纤维
    /// 纹理的话，耳朵会比头"光滑塑料"一截
    private static func addFuzz(_ node: SCNNode) {
        node.geometry?.firstMaterial?.shaderModifiers = [.surface: SDFMesh.furSurfaceShader]
    }
}
