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
            printContentMargins(rep)
        } catch {
            FileHandle.standardError.write("快照写入失败: \(error)\n".data(using: .utf8)!)
        }
    }

    /// 打印模型轮廓到画面四边的距离（百分比），用于检查取景是否裁切
    private static func printContentMargins(_ rep: NSBitmapImageRep) {
        guard rep.bitsPerSample == 8, rep.hasAlpha, let data = rep.bitmapData else { return }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        let spp = rep.samplesPerPixel, bpr = rep.bytesPerRow
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            let row = data + y * bpr
            for x in 0..<w where row[x * spp + spp - 1] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return }
        print(String(
            format: "轮廓边距%%: 上 %.1f 左 %.1f 下 %.1f 右 %.1f",
            Double(minY) / Double(h) * 100,
            Double(minX) / Double(w) * 100,
            Double(h - 1 - maxY) / Double(h) * 100,
            Double(w - 1 - maxX) / Double(w) * 100
        ))
    }
}
