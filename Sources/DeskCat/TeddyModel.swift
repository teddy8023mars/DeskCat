import AppKit
import SceneKit

/// 代码生成的泰迪熊：独立头部节点（跟随鼠标）、可眨眼的眼睛、黑框眼镜。
/// 原型：浅棕绒毛、大圆头、亮色口鼻、下撇缝线嘴、坐姿、脚掌朝前。
struct TeddyModel {
    let root: SCNNode
    let head: SCNNode
    let body: SCNNode
    let eyes: [SCNNode]
}

enum TeddyBuilder {
    // 配色
    static let fur = NSColor(red: 0.80, green: 0.57, blue: 0.33, alpha: 1)      // 主体绒毛
    static let furLight = NSColor(red: 0.91, green: 0.75, blue: 0.54, alpha: 1) // 口鼻/耳内
    static let padColor = NSColor(red: 0.58, green: 0.40, blue: 0.25, alpha: 1) // 脚掌
    static let noseColor = NSColor(red: 0.15, green: 0.10, blue: 0.08, alpha: 1)
    static let eyeColor = NSColor(red: 0.18, green: 0.12, blue: 0.08, alpha: 1)
    static let frameColor = NSColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)

    static func build() -> TeddyModel {
        let root = SCNNode()
        root.name = "Teddy"

        // —— 身体（呼吸节点）——
        let body = node(SCNSphere(radius: 0.60), fur)
        body.scale = SCNVector3(1.0, 0.95, 0.85)
        body.position = SCNVector3(0, 0.58, 0)
        root.addChildNode(body)

        // —— 腿（坐姿，伸向前方）——
        for side: CGFloat in [-1, 1] {
            let leg = node(SCNCapsule(capRadius: 0.21, height: 0.62), fur)
            leg.position = SCNVector3(side * 0.40, 0.28, 0.38)
            leg.eulerAngles = SCNVector3(-1.25, 0, side * -0.28)
            root.addChildNode(leg)

            let foot = node(SCNSphere(radius: 0.20), fur)
            foot.scale = SCNVector3(1.0, 0.95, 1.1)
            foot.position = SCNVector3(side * 0.50, 0.22, 0.66)
            root.addChildNode(foot)

            // 脚掌（朝前上方，像图里一样对着观众）
            let pad = node(SCNSphere(radius: 0.145), padColor)
            pad.scale = SCNVector3(1.0, 1.0, 0.28)
            pad.position = SCNVector3(side * 0.52, 0.26, 0.82)
            pad.eulerAngles = SCNVector3(-0.5, 0, 0)
            root.addChildNode(pad)
        }

        // —— 手臂（搭在身体两侧、微微向前）——
        for side: CGFloat in [-1, 1] {
            let arm = node(SCNCapsule(capRadius: 0.155, height: 0.58), fur)
            arm.position = SCNVector3(side * 0.58, 0.72, 0.10)
            arm.eulerAngles = SCNVector3(-0.45, 0, side * 0.65)
            root.addChildNode(arm)

            let paw = node(SCNSphere(radius: 0.15), fur)
            paw.position = SCNVector3(side * 0.72, 0.46, 0.28)
            root.addChildNode(paw)
        }

        // —— 头（跟随鼠标的枢轴在脖子处）——
        let head = SCNNode()
        head.name = "Head"
        head.position = SCNVector3(0, 1.18, 0)
        root.addChildNode(head)

        let skull = node(SCNSphere(radius: 0.56), fur)
        skull.scale = SCNVector3(1.0, 0.95, 0.95)
        skull.position = SCNVector3(0, 0.32, 0)
        head.addChildNode(skull)

        // 耳朵 + 耳内
        for side: CGFloat in [-1, 1] {
            let ear = node(SCNSphere(radius: 0.175), fur)
            ear.scale = SCNVector3(1, 1, 0.62)
            ear.position = SCNVector3(side * 0.38, 0.78, -0.04)
            head.addChildNode(ear)

            let inner = node(SCNSphere(radius: 0.105), furLight)
            inner.scale = SCNVector3(1, 1, 0.4)
            inner.position = SCNVector3(side * 0.375, 0.77, 0.06)
            head.addChildNode(inner)
        }

        // 口鼻（亮色大椭球，下半脸）
        let muzzle = node(SCNSphere(radius: 0.33), furLight)
        muzzle.scale = SCNVector3(1.12, 0.85, 0.72)
        muzzle.position = SCNVector3(0, 0.10, 0.42)
        head.addChildNode(muzzle)

        // 鼻子（深色扁椭球）
        let nose = node(SCNSphere(radius: 0.115), noseColor)
        nose.scale = SCNVector3(1.25, 0.75, 0.55)
        nose.position = SCNVector3(0, 0.25, 0.66)
        head.addChildNode(nose)

        // 缝线嘴：鼻下竖线 + 两条下撇线（"︵"形）
        let stitch = node(SCNCylinder(radius: 0.014, height: 0.10), noseColor)
        stitch.position = SCNVector3(0, 0.165, 0.67)
        head.addChildNode(stitch)
        for side: CGFloat in [-1, 1] {
            let lip = node(SCNCylinder(radius: 0.014, height: 0.15), noseColor)
            lip.position = SCNVector3(side * 0.065, 0.095, 0.66)
            lip.eulerAngles = SCNVector3(0.18, 0, side * 1.15)
            head.addChildNode(lip)
        }

        // 眼睛（可眨：眨眼时 y 方向压扁）+ 高光
        var eyes: [SCNNode] = []
        for side: CGFloat in [-1, 1] {
            let eye = node(SCNSphere(radius: 0.075), eyeColor)
            eye.position = SCNVector3(side * 0.19, 0.45, 0.49)
            let highlight = node(SCNSphere(radius: 0.022), .white)
            highlight.position = SCNVector3(0.018, 0.025, 0.062)
            eye.addChildNode(highlight)
            head.addChildNode(eye)
            eyes.append(eye)
        }

        // —— 黑框眼镜 ——
        let glasses = SCNNode()
        glasses.position = SCNVector3(0, 0.45, 0.555)
        for side: CGFloat in [-1, 1] {
            let ring = node(SCNTorus(ringRadius: 0.115, pipeRadius: 0.013), frameColor)
            ring.eulerAngles = SCNVector3(Double.pi / 2, 0, 0)
            ring.scale = SCNVector3(1.2, 1, 0.85)
            ring.position = SCNVector3(side * 0.19, 0, 0)
            glasses.addChildNode(ring)

            // 镜腿：从镜框伸向耳朵
            let temple = node(SCNCylinder(radius: 0.011, height: 0.42), frameColor)
            temple.position = SCNVector3(side * 0.315, 0.02, -0.21)
            temple.eulerAngles = SCNVector3(Double.pi / 2, 0, 0)
            glasses.addChildNode(temple)
        }
        let bridge = node(SCNCylinder(radius: 0.012, height: 0.10), frameColor)
        bridge.position = SCNVector3(0, 0.02, 0)
        bridge.eulerAngles = SCNVector3(0, 0, Double.pi / 2)
        glasses.addChildNode(bridge)
        head.addChildNode(glasses)

        return TeddyModel(root: root, head: head, body: body, eyes: eyes)
    }

    private static func node(_ geometry: SCNGeometry, _ color: NSColor) -> SCNNode {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = color
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
}
