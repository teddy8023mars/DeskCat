import AppKit
import SceneKit

/// 每帧驱动小猫行为：头部跟随鼠标、尾巴摆动、呼吸、空闲小动作、鼠标靠近反应。
final class CatBrain: NSObject, SCNSceneRendererDelegate {
    private let cat: CatScene

    /// 主线程更新、渲染线程读取的窗口位置缓存
    private let frameLock = NSLock()
    private var _windowFrame = CGRect.zero
    var windowFrame: CGRect {
        get { frameLock.lock(); defer { frameLock.unlock() }; return _windowFrame }
        set { frameLock.lock(); _windowFrame = newValue; frameLock.unlock() }
    }

    private var lastTime: TimeInterval = -1
    private var currentLook = simd_quatf(angle: 0, axis: [0, 1, 0])
    private var currentBodyYaw: Float = 0

    // 尾巴
    private var tailAmp: Float = 0.25
    private var tailAmpTarget: Float = 0.25
    private var tailSpeed: Float = 2.5

    // 空闲动作
    private var nextIdleAt: TimeInterval = 0
    private var idleEndAt: TimeInterval = 0
    private var rollTarget: Float = 0

    // 靠近反应
    private var excited = false
    private var lastHopAt: TimeInterval = 0

    // 眨眼（仅对有独立眼睛节点的形象生效）
    private var nextBlinkAt: TimeInterval = 0
    private var blinkUntil: TimeInterval = 0

    /// 头部跟随的虚拟距离（屏幕点），越小转头越敏感
    private let virtualDistance: Float = 480

    init(cat: CatScene) {
        self.cat = cat
        super.init()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime < 0 ? Float(1.0 / 60.0) : Float(min(time - lastTime, 0.1))
        lastTime = time

        let (yaw, pitch, distance) = mouseAngles()

        // 鼠标靠近 → 兴奋状态
        let nowExcited = distance < 220
        if nowExcited && !excited && time - lastHopAt > 3 {
            lastHopAt = time
            tailAmpTarget = 0.9
            tailSpeed = 7
            idleEndAt = time + 2.5
            DispatchQueue.main.async { [hopNode = cat.hopNode] in
                hopNode.runAction(CatBrain.hopAction())
            }
        }
        excited = nowExcited

        // 空闲小动作调度
        if time > idleEndAt {
            tailAmpTarget = 0.25
            tailSpeed = 2.5
            rollTarget = 0
            if nextIdleAt == 0 { nextIdleAt = time + .random(in: 4...9) }
            if time > nextIdleAt {
                nextIdleAt = 0
                idleEndAt = time + .random(in: 1.8...3.0)
                switch Int.random(in: 0..<3) {
                case 0: // 兴奋摇尾巴
                    tailAmpTarget = 0.8
                    tailSpeed = 6
                case 1: // 好奇歪头
                    rollTarget = Float.random(in: 0.18...0.3) * (Bool.random() ? 1 : -1)
                default: // 小跳
                    DispatchQueue.main.async { [hopNode = cat.hopNode] in
                        hopNode.runAction(CatBrain.hopAction())
                    }
                }
            }
        }

        // 目标视线（世界空间，相机朝 -Z，猫面向 +Z）
        let yawQ = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let pitchQ = simd_quatf(angle: -pitch, axis: [1, 0, 0])
        let rollQ = simd_quatf(angle: rollTarget, axis: [0, 0, 1])
        let target = yawQ * pitchQ * rollQ

        // 平滑插值，兴奋时反应更快
        let k: Float = excited ? 14 : 7
        let blend = 1 - exp(-k * dt)
        currentLook = simd_slerp(currentLook, target, blend)

        // 身体跟着轻微转向（头转得多，身体转得少）
        currentBodyYaw += (yaw * 0.3 - currentBodyYaw) * (1 - exp(-4 * dt))
        cat.yawNode.simdOrientation = simd_quatf(angle: currentBodyYaw, axis: [0, 1, 0])

        // 把世界空间的视线旋转换算到头部骨骼的局部空间：
        // L' = (P⁻¹ · R · P) · L_rest，P 为父节点世界朝向
        if let head = cat.headBone, let parent = head.parent {
            let p = parent.simdWorldOrientation
            let local = p.inverse * currentLook * p
            head.simdOrientation = local * cat.headRest
        }

        // 尾巴摆动
        tailAmp += (tailAmpTarget - tailAmp) * (1 - exp(-5 * dt))
        if let tail = cat.tailBone {
            let wag = simd_quatf(angle: sin(Float(time) * tailSpeed) * tailAmp, axis: [0, 0, 1])
            tail.simdOrientation = cat.tailRest * wag
        }

        // 眨眼：随机间隔压扁眼球 0.13 秒
        if !cat.eyeNodes.isEmpty {
            if nextBlinkAt == 0 { nextBlinkAt = time + .random(in: 1.5...4) }
            if time > nextBlinkAt {
                blinkUntil = time + 0.13
                nextBlinkAt = time + .random(in: 2.5...6)
            }
            let lid: Float = time < blinkUntil ? 0.12 : 1
            for eye in cat.eyeNodes {
                eye.simdScale = simd_float3(1, lid, 1)
            }
        }

        // 呼吸起伏
        if let body = cat.bodyBone {
            let breath = 1 + 0.015 * sin(Float(time) * 2.0)
            body.simdScale = simd_float3(repeating: breath)
        }
    }

    /// 返回鼠标相对小猫的偏航/俯仰角（弧度）和距离（屏幕点）
    private func mouseAngles() -> (yaw: Float, pitch: Float, distance: Float) {
        guard let event = CGEvent(source: nil) else { return (0, 0, .greatestFiniteMagnitude) }
        let mouse = event.location // 全局坐标，主屏左上角原点，y 向下
        let frame = windowFrame
        guard frame.width > 0 else { return (0, 0, .greatestFiniteMagnitude) }

        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let mouseX = Float(mouse.x)
        let mouseY = Float(mainHeight - mouse.y) // 转为 Cocoa 坐标（y 向上）

        // 头部大致在窗口中心偏上
        let headX = Float(frame.midX)
        let headY = Float(frame.midY) + Float(frame.height) * 0.1

        let dx = mouseX - headX
        let dy = mouseY - headY
        let yaw = atan2(dx, virtualDistance)
        let pitch = atan2(dy, virtualDistance)
        let distance = sqrt(dx * dx + dy * dy)

        // 限制转头幅度，避免脖子拧断
        return (
            max(-0.9, min(0.9, yaw)),
            max(-0.55, min(0.65, pitch)),
            distance
        )
    }

    /// 卡通小跳：压缩 → 跳起拉伸 → 落地压缩 → 恢复
    static func hopAction() -> SCNAction {
        let duration = 0.55
        return SCNAction.customAction(duration: duration) { node, elapsed in
            let t = Float(elapsed) / Float(duration)
            var scaleY: Float = 1
            var scaleXZ: Float = 1
            var posY: Float = 0
            switch t {
            case ..<0.2: // 蓄力压缩
                let p = t / 0.2
                scaleY = 1 - 0.12 * p
                scaleXZ = 1 + 0.07 * p
            case ..<0.6: // 跳起拉伸
                let p = (t - 0.2) / 0.4
                posY = 0.28 * sin(p * .pi)
                scaleY = 1 + 0.1 * sin(p * .pi)
                scaleXZ = 1 - 0.05 * sin(p * .pi)
            case ..<0.8: // 落地压缩
                let p = (t - 0.6) / 0.2
                scaleY = 1 - 0.1 * (1 - p)
                scaleXZ = 1 + 0.06 * (1 - p)
            default:
                break
            }
            node.simdScale = simd_float3(scaleXZ, scaleY, scaleXZ)
            node.simdPosition = simd_float3(0, posY, 0)
        }
    }
}
