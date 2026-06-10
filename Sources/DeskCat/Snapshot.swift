import AppKit
import SceneKit

/// 离屏渲染调试工具：`DeskCat --snapshot out.png` 把当前场景渲染成图片，
/// 可用环境变量 DC_YAW / DC_PITCH（度）和 DC_TAIL（弧度）摆出固定姿势，验证旋转方向。
enum Snapshot {
    static func render(scene catScene: CatScene, to path: String) {
        let env = ProcessInfo.processInfo.environment
        if let head = catScene.headBone, let parent = head.parent {
            let yaw = Float(Double(env["DC_YAW"] ?? "0") ?? 0) * .pi / 180
            let pitch = Float(Double(env["DC_PITCH"] ?? "0") ?? 0) * .pi / 180
            let r = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [1, 0, 0])
            let p = parent.simdWorldOrientation
            head.simdOrientation = (p.inverse * r * p) * catScene.headRest
        }
        if let tail = catScene.tailBone, let angle = Double(env["DC_TAIL"] ?? "") {
            tail.simdOrientation = catScene.tailRest * simd_quatf(angle: Float(angle), axis: [0, 0, 1])
        }

        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = catScene.scene
        let image = renderer.snapshot(
            atTime: 0,
            with: CGSize(width: 512, height: 512),
            antialiasingMode: .multisampling4X
        )
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("快照编码失败\n".data(using: .utf8)!)
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("快照已保存: \(path)")
        } catch {
            FileHandle.standardError.write("快照写入失败: \(error)\n".data(using: .utf8)!)
        }
    }
}
