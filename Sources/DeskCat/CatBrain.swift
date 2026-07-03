import AppKit
import SceneKit

/// 每帧驱动伴侣行为：弹簧头部跟随、眼神领先、尾巴/耳朵、呼吸摇曳、空闲小动作。
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

    // 头部弹簧动力学（欠阻尼 → 带一点回弹，更像活物）
    private var yawAngle: Float = 0
    private var yawVel: Float = 0
    private var pitchAngle: Float = 0
    private var pitchVel: Float = 0
    private var rollCurrent: Float = 0
    private var currentBodyYaw: Float = 0

    // 尾巴（小猫）
    private var tailAmp: Float = 0.25
    private var tailAmpTarget: Float = 0.25
    private var tailSpeed: Float = 2.5

    // 空闲动作
    private var nextIdleAt: TimeInterval = 0
    private var idleEndAt: TimeInterval = 0
    private var rollTarget: Float = 0

    // 耳朵抖动（泰迪熊）
    private var earTwitchStart: TimeInterval = -1
    private var twitchEarIndex = 0

    // 靠近反应
    private var excited = false

    // 眨眼（仅对有独立眼睛节点的形象生效）
    private var nextBlinkAt: TimeInterval = 0
    private var blinkUntil: TimeInterval = 0

    // 眼球扫视（saccade）：空闲时随机瞟一眼
    private var nextSaccadeAt: TimeInterval = 0
    private var saccadeUntil: TimeInterval = 0
    private var saccadeYaw: Float = 0
    private var saccadePitch: Float = 0

    // 表情：嘴部暗缝 + 短嘴角（仅泰迪熊）。幅度刻意克制，避免破坏毛绒玩具神态。
    private var mouthOpen: Float = 0
    private var mouthOpenTarget: Float = 0
    private var smile: Float = 0
    private var smileTarget: Float = 0
    private var nextExprAt: TimeInterval = 0
    private var exprEndAt: TimeInterval = 0

    /// 头部跟随的虚拟距离（屏幕点），越小转头越敏感
    private let virtualDistance: Float = 480

    init(cat: CatScene) {
        self.cat = cat
        super.init()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime < 0 ? Float(1.0 / 60.0) : Float(min(time - lastTime, 0.1))
        lastTime = time
        let t = Float(time)

        let (targetYaw, targetPitch, distance) = mouseAngles()

        // 鼠标靠近 → 兴奋状态（转头更快、尾巴摇得欢，不跳）
        let nowExcited = distance < 220
        if nowExcited && !excited {
            tailAmpTarget = 0.9
            tailSpeed = 7
            idleEndAt = time + 2.5
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
                // 小猫：摇尾巴/歪头；泰迪熊：抖耳朵/歪头
                if cat.tailBone != nil && Bool.random() {
                    tailAmpTarget = 0.8
                    tailSpeed = 6
                } else if !cat.earNodes.isEmpty && Bool.random() {
                    earTwitchStart = time
                    twitchEarIndex = Int.random(in: 0..<cat.earNodes.count)
                } else {
                    rollTarget = Float.random(in: 0.18...0.3) * (Bool.random() ? 1 : -1)
                }
            }
        }

        // —— 头部弹簧（半隐式欧拉，欠阻尼带回弹）——
        let stiffness: Float = excited ? 130 : 60
        let omega = sqrt(stiffness)
        let damping = 2 * 0.62 * omega
        yawVel += (-stiffness * (yawAngle - targetYaw) - damping * yawVel) * dt
        yawAngle += yawVel * dt
        pitchVel += (-stiffness * (pitchAngle - targetPitch) - damping * pitchVel) * dt
        pitchAngle += pitchVel * dt
        rollCurrent += (rollTarget - rollCurrent) * (1 - exp(-6 * dt))

        let currentLook = simd_quatf(angle: yawAngle, axis: [0, 1, 0])
            * simd_quatf(angle: -pitchAngle, axis: [1, 0, 0])
            * simd_quatf(angle: rollCurrent, axis: [0, 0, 1])

        // 身体轻微跟转 + 缓慢摇曳
        currentBodyYaw += (targetYaw * 0.3 - currentBodyYaw) * (1 - exp(-4 * dt))
        let sway = sin(t * 0.7) * 0.015
        cat.yawNode.simdOrientation = simd_quatf(angle: currentBodyYaw, axis: [0, 1, 0])
            * simd_quatf(angle: sway, axis: [0, 0, 1])

        // 把世界空间的视线旋转换算到头部骨骼的局部空间：
        // L' = (P⁻¹ · R · P) · L_rest，P 为父节点世界朝向
        if let head = cat.headBone, let parent = head.parent {
            let p = parent.simdWorldOrientation
            let local = p.inverse * currentLook * p
            head.simdOrientation = local * cat.headRest
        }

        // 眼神：领先 + 持续注视 + 空闲扫视
        if !cat.eyeNodes.isEmpty {
            // 领先：头还没转到位时，眼珠先看向目标（皮克斯式"眼先动，头后到"）
            var gazeYaw = (targetYaw - yawAngle) * 0.9
            var gazePitch = (targetPitch - pitchAngle) * 0.9
            // 持续注视：头到位后瞳孔仍朝鼠标方向偏一点，不然眼神是"死"的
            gazeYaw += targetYaw * 0.14
            gazePitch += targetPitch * 0.14
            // 扫视：空闲时偶尔快速瞟一眼别处再回来，像在想事情
            if time > saccadeUntil, time > nextSaccadeAt {
                if nextSaccadeAt == 0 {
                    nextSaccadeAt = time + .random(in: 3...8)
                } else {
                    saccadeYaw = Float.random(in: -0.22...0.22)
                    saccadePitch = Float.random(in: -0.12...0.12)
                    saccadeUntil = time + .random(in: 0.25...0.6)
                    nextSaccadeAt = time + .random(in: 3...8)
                }
            }
            if time < saccadeUntil, !excited {
                gazeYaw += saccadeYaw
                gazePitch += saccadePitch
            }
            let leadYaw = max(-0.32, min(0.32, gazeYaw))
            let leadPitch = max(-0.26, min(0.26, gazePitch))
            let eyeQuat = simd_quatf(angle: leadYaw, axis: [0, 1, 0])
                * simd_quatf(angle: -leadPitch, axis: [1, 0, 0])
            for eye in cat.eyeNodes {
                eye.simdOrientation = eyeQuat
            }
        }

        // 尾巴摆动（小猫）
        tailAmp += (tailAmpTarget - tailAmp) * (1 - exp(-5 * dt))
        if let tail = cat.tailBone {
            let wag = simd_quatf(angle: sin(t * tailSpeed) * tailAmp, axis: [0, 0, 1])
            tail.simdOrientation = cat.tailRest * wag
        }

        // 耳朵抖动（泰迪熊）：短促衰减的弹性缩放
        if earTwitchStart >= 0, twitchEarIndex < cat.earNodes.count {
            let elapsed = Float(time - earTwitchStart)
            let ear = cat.earNodes[twitchEarIndex]
            if elapsed < 0.6 {
                let pulse = 1 + 0.16 * sin(elapsed * 32) * exp(-elapsed * 5)
                ear.simdScale = simd_float3(1, pulse, 0.55)
            } else {
                ear.simdScale = simd_float3(1, 1, 0.55)
                earTwitchStart = -1
            }
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

        // —— 表情：保留低位嘴缝的神态，只叠加短促微表情 ——
        if let mouth = cat.mouthNode {
            if excited {
                smileTarget = 0.35
                mouthOpenTarget = max(mouthOpenTarget, 0.10)
                exprEndAt = max(exprEndAt, time + 0.35)
            }
            if cat.hopNode.hasActions { // 点击互动 → 开心大笑
                smileTarget = 0.55
                mouthOpenTarget = max(mouthOpenTarget, 0.20)
                exprEndAt = max(exprEndAt, time + 0.55)
            }
            if time > exprEndAt {
                smileTarget = 0
                mouthOpenTarget = 0
                if nextExprAt == 0 { nextExprAt = time + .random(in: 12...28) }
                if time > nextExprAt {
                    nextExprAt = 0
                    switch Int.random(in: 0..<3) {
                    case 0: // 轻轻一笑
                        smileTarget = 0.32; mouthOpenTarget = 0.08
                        exprEndAt = time + .random(in: 0.8...1.3)
                    case 1: // 嘴角动一下
                        smileTarget = 0.22
                        exprEndAt = time + 0.55
                    default: // 小声嘟哝一下
                        mouthOpenTarget = 0.10
                        exprEndAt = time + 0.45
                    }
                }
            }
            mouthOpen += (mouthOpenTarget - mouthOpen) * (1 - exp(-9 * dt))
            smile += (smileTarget - smile) * (1 - exp(-7 * dt))
            let open = CGFloat(max(0, min(1, mouthOpen)))
            mouth.scale = SCNVector3(
                0.08 + 0.42 * open,
                0.06 + 0.24 * open,
                0.08 + 0.30 * open
            )
            for c in cat.smileCornerNodes {
                c.scale = SCNVector3(CGFloat(smile), CGFloat(smile), CGFloat(smile))
            }
        }

        // 呼吸起伏
        if let body = cat.bodyBone {
            let breath = 1 + 0.02 * sin(t * 2.0)
            body.simdScale = simd_float3(repeating: breath)
        }

        // —— 自适应帧率：只在"有事发生"时满帧，纯坐着呼吸时降到低帧省电 ——
        // 头还在转、被鼠标吸引、正播空闲动作/眨眼/抖耳/小跳 → 活跃；否则空闲
        let headMoving = abs(yawVel) > 0.02 || abs(pitchVel) > 0.02
            || abs(yawAngle - targetYaw) > 0.01 || abs(pitchAngle - targetPitch) > 0.01
        let busy = excited || time < idleEndAt || earTwitchStart >= 0
            || time < blinkUntil || cat.hopNode.hasActions
            || time < exprEndAt || mouthOpen > 0.03
        let target = (headMoving || busy) ? Self.activeFPS : Self.idleFPS
        if let view = renderer as? SCNView, view.preferredFramesPerSecond != target {
            view.preferredFramesPerSecond = target
        }
    }

    /// 活跃时满帧（跟手、动画流畅）；空闲时仅维持缓慢呼吸，大幅省电
    private static let activeFPS = 60
    private static let idleFPS = 10

    /// 返回鼠标相对头部的偏航/俯仰角（弧度）和距离（屏幕点）
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

    /// 卡通小跳：压缩 → 跳起拉伸 → 落地压缩 → 恢复（仅点击触发）
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
                posY = 0.22 * sin(p * .pi)
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
