import AppKit
import SceneKit

/// 代码生成的泰迪熊：独立头部节点（跟随鼠标）、可眨眼+转动的眼睛、方框眼镜、绒毛质感。
/// 原型：金棕色绒毛、宽圆大头、突出的口鼻、下撇缝线嘴、方框眼镜、坐姿脚掌朝前。
struct TeddyModel {
    let root: SCNNode
    let head: SCNNode
    let body: SCNNode
    let eyes: [SCNNode]
    let ears: [SCNNode]
}

enum TeddyBuilder {
    // 配色（对齐原型：金蜂蜜棕，口鼻略浅）
    static let fur = NSColor(red: 0.79, green: 0.56, blue: 0.31, alpha: 1)
    static let furLight = NSColor(red: 0.87, green: 0.67, blue: 0.43, alpha: 1)
    static let padColor = NSColor(red: 0.52, green: 0.36, blue: 0.22, alpha: 1)
    static let noseColor = NSColor(red: 0.13, green: 0.09, blue: 0.07, alpha: 1)
    static let irisColor = NSColor(red: 0.30, green: 0.19, blue: 0.11, alpha: 1)
    static let frameColor = NSColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)

    // 绒毛贴图按色调缓存（生成一次）
    private static let furTexture = makeFurTexture(tint: fur)
    private static let furLightTexture = makeFurTexture(tint: furLight)

    static func build() -> TeddyModel {
        let root = SCNNode()
        root.name = "Teddy"

        // —— 身体（呼吸节点）——
        let body = furNode(SCNSphere(radius: 0.60), furTexture)
        body.scale = SCNVector3(1.06, 0.95, 0.86)
        body.position = SCNVector3(0, 0.58, 0)
        root.addChildNode(body)

        // —— 腿（坐姿，伸向前方）——
        for side: CGFloat in [-1, 1] {
            let leg = furNode(SCNCapsule(capRadius: 0.22, height: 0.62), furTexture)
            leg.position = SCNVector3(side * 0.40, 0.28, 0.38)
            leg.eulerAngles = SCNVector3(-1.25, 0, side * -0.28)
            root.addChildNode(leg)

            let foot = furNode(SCNSphere(radius: 0.21), furTexture)
            foot.scale = SCNVector3(1.0, 0.95, 1.1)
            foot.position = SCNVector3(side * 0.50, 0.22, 0.66)
            root.addChildNode(foot)

            // 脚掌（朝前上方对着观众）
            let pad = node(SCNSphere(radius: 0.15), padColor)
            pad.scale = SCNVector3(1.0, 1.0, 0.28)
            pad.position = SCNVector3(side * 0.52, 0.26, 0.83)
            pad.eulerAngles = SCNVector3(-0.5, 0, 0)
            root.addChildNode(pad)
        }

        // —— 手臂 ——
        for side: CGFloat in [-1, 1] {
            let arm = furNode(SCNCapsule(capRadius: 0.16, height: 0.58), furTexture)
            arm.position = SCNVector3(side * 0.58, 0.72, 0.10)
            arm.eulerAngles = SCNVector3(-0.45, 0, side * 0.65)
            root.addChildNode(arm)

            let paw = furNode(SCNSphere(radius: 0.155), furTexture)
            paw.position = SCNVector3(side * 0.72, 0.46, 0.28)
            root.addChildNode(paw)
        }

        // —— 头（跟随鼠标的枢轴在脖子处）——
        let head = SCNNode()
        head.name = "Head"
        head.position = SCNVector3(0, 1.16, 0)
        root.addChildNode(head)

        // 宽圆头型（原型头部比例大、偏宽）
        let skull = furNode(SCNSphere(radius: 0.56), furTexture)
        skull.scale = SCNVector3(1.12, 0.95, 0.92)
        skull.position = SCNVector3(0, 0.32, 0)
        head.addChildNode(skull)

        // 耳朵（头顶两角，存引用供抖动动画）
        var ears: [SCNNode] = []
        for side: CGFloat in [-1, 1] {
            let ear = furNode(SCNSphere(radius: 0.19), furTexture)
            ear.scale = SCNVector3(1, 1, 0.55)
            ear.position = SCNVector3(side * 0.42, 0.76, -0.02)
            head.addChildNode(ear)
            ears.append(ear)

            let inner = node(SCNSphere(radius: 0.115), furLight)
            inner.scale = SCNVector3(1, 1, 0.4)
            inner.position = SCNVector3(side * 0.415, 0.75, 0.07)
            head.addChildNode(inner)
        }

        // 大口鼻（突出、占下半脸）
        let muzzle = furNode(SCNSphere(radius: 0.36), furLightTexture)
        muzzle.scale = SCNVector3(1.15, 0.88, 0.72)
        muzzle.position = SCNVector3(0, 0.06, 0.46)
        head.addChildNode(muzzle)

        // 鼻子（宽扁深色）
        let nose = node(SCNSphere(radius: 0.115), noseColor)
        nose.scale = SCNVector3(1.3, 0.75, 0.5)
        nose.position = SCNVector3(0, 0.22, 0.70)
        head.addChildNode(nose)

        // 缝线嘴：鼻下竖线 + 两条下撇线
        let stitch = node(SCNCylinder(radius: 0.012, height: 0.09), noseColor)
        stitch.position = SCNVector3(0, 0.135, 0.72)
        head.addChildNode(stitch)
        for side: CGFloat in [-1, 1] {
            let lip = node(SCNCylinder(radius: 0.012, height: 0.14), noseColor)
            lip.position = SCNVector3(side * 0.068, 0.07, 0.71)
            lip.eulerAngles = SCNVector3(0.15, 0, side * 1.3)
            head.addChildNode(lip)
        }

        // 眼睛：琥珀色眼珠 + 黑瞳孔 + 高光，可整体转动（眼神领先于头）
        var eyes: [SCNNode] = []
        for side: CGFloat in [-1, 1] {
            let eye = node(SCNSphere(radius: 0.082), irisColor)
            eye.position = SCNVector3(side * 0.17, 0.45, 0.50)

            let pupil = node(SCNSphere(radius: 0.038), .black)
            pupil.position = SCNVector3(0, 0, 0.052)
            eye.addChildNode(pupil)

            let highlight = node(SCNSphere(radius: 0.018), .white)
            highlight.position = SCNVector3(0.022, 0.024, 0.072)
            eye.addChildNode(highlight)

            head.addChildNode(eye)
            eyes.append(eye)
        }

        // —— 方框眼镜（圆角矩形镜框，对齐原型）——
        let glasses = SCNNode()
        glasses.position = SCNVector3(0, 0.45, 0.56)
        for side: CGFloat in [-1, 1] {
            let frame = node(rectFrameShape(), frameColor)
            frame.position = SCNVector3(side * 0.175, 0, 0)
            glasses.addChildNode(frame)

            let temple = node(SCNCylinder(radius: 0.010, height: 0.44), frameColor)
            temple.position = SCNVector3(side * 0.315, 0.035, -0.21)
            temple.eulerAngles = SCNVector3(Double.pi / 2, 0, 0)
            glasses.addChildNode(temple)
        }
        let bridge = node(SCNCylinder(radius: 0.011, height: 0.09), frameColor)
        bridge.position = SCNVector3(0, 0.035, 0)
        bridge.eulerAngles = SCNVector3(0, 0, Double.pi / 2)
        glasses.addChildNode(bridge)
        head.addChildNode(glasses)

        return TeddyModel(root: root, head: head, body: body, eyes: eyes, ears: ears)
    }

    /// 圆角矩形镜框（带孔的环形截面，挤出成型）
    private static func rectFrameShape() -> SCNGeometry {
        let outer = NSBezierPath(
            roundedRect: NSRect(x: -0.15, y: -0.105, width: 0.30, height: 0.21),
            xRadius: 0.06, yRadius: 0.06
        )
        let inner = NSBezierPath(
            roundedRect: NSRect(x: -0.132, y: -0.087, width: 0.264, height: 0.174),
            xRadius: 0.05, yRadius: 0.05
        )
        outer.append(inner.reversed)
        outer.windingRule = .nonZero
        outer.flatness = 0.0008 // 细分平滑，避免圆角变成八边形
        let shape = SCNShape(path: outer, extrusionDepth: 0.028)
        return shape
    }

    // MARK: - 材质

    private static func node(_ geometry: SCNGeometry, _ color: NSColor) -> SCNNode {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = color
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    /// 绒毛节点：噪点贴图 + 边缘绒毛高光（菲涅尔），模拟毛绒玩具质感
    private static func furNode(_ geometry: SCNGeometry, _ texture: NSImage) -> SCNNode {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = texture
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(2, 2, 1)
        material.shaderModifiers = [
            .surface: """
            float fuzz = pow(1.0 - max(0.0, dot(normalize(_surface.view), _surface.normal)), 2.2);
            _surface.diffuse.rgb += fuzz * 0.45 * _surface.diffuse.rgb;
            """
        ]
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    /// 程序生成绒毛贴图：底色 + 几千条随机短绒毛笔触
    private static func makeFurTexture(tint: NSColor) -> NSImage {
        let size = 256
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let base = tint.usingColorSpace(.deviceRGB) ?? tint
        base.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()

        func shade(_ delta: CGFloat, alpha: CGFloat) -> NSColor {
            NSColor(
                red: min(max(base.redComponent + delta, 0), 1),
                green: min(max(base.greenComponent + delta * 0.85, 0), 1),
                blue: min(max(base.blueComponent + delta * 0.7, 0), 1),
                alpha: alpha
            )
        }

        // 粗颗粒明暗斑块（绒毛蓬松的光影）
        for _ in 0..<350 {
            let r = CGFloat.random(in: 6...20)
            let rect = NSRect(
                x: CGFloat.random(in: -20...CGFloat(size)),
                y: CGFloat.random(in: -20...CGFloat(size)),
                width: r, height: r
            )
            shade(CGFloat.random(in: -0.05...0.05), alpha: 0.18).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }

        // 细短绒毛笔触
        for _ in 0..<5000 {
            let x = CGFloat.random(in: 0...CGFloat(size))
            let y = CGFloat.random(in: 0...CGFloat(size))
            let length = CGFloat.random(in: 2.5...6)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: y))
            path.line(to: NSPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
            path.lineWidth = CGFloat.random(in: 0.6...1.2)
            shade(CGFloat.random(in: -0.09...0.09), alpha: 0.45).setStroke()
            path.stroke()
        }

        image.unlockFocus()
        return image
    }
}
