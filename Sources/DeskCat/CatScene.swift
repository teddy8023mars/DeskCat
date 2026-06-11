import AppKit
import SceneKit
import GLTFKit2

enum CompanionKind: String {
    case cat
    case teddy
}

/// 负责搭建场景（相机/灯光/归一化）并暴露驱动所需的节点。
/// 支持两种形象：GLB 小猫 / 代码生成的泰迪熊。
final class CatScene {
    let scene = SCNScene()

    /// 层级：root → hopNode(跳跃/挤压) → yawNode(身体转向) → modelRoot(归一化缩放) → 模型内容
    let hopNode = SCNNode()
    let yawNode = SCNNode()
    let modelRoot = SCNNode()

    private(set) var headBone: SCNNode?
    private(set) var tailBone: SCNNode?
    private(set) var bodyBone: SCNNode?
    private(set) var eyeNodes: [SCNNode] = []
    private(set) var earNodes: [SCNNode] = []

    private(set) var headRest = simd_quatf(angle: 0, axis: [0, 1, 0])
    private(set) var tailRest = simd_quatf(angle: 0, axis: [0, 1, 0])

    init(asset: GLTFAsset) {
        let gltfScene = SCNScene(gltfAsset: asset)
        for child in gltfScene.rootNode.childNodes {
            modelRoot.addChildNode(child)
        }
        // 漫画感：扁平着色，避免 PBR 在简单灯光下显脏
        modelRoot.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] {
                material.lightingModel = .lambert
            }
        }
        headBone = modelRoot.childNode(withName: "Head", recursively: true)
        tailBone = modelRoot.childNode(withName: "Tail", recursively: true)
        bodyBone = modelRoot.childNode(withName: "Body", recursively: true)
        finishSetup()
    }

    init(teddy: TeddyModel) {
        modelRoot.addChildNode(teddy.root)
        headBone = teddy.head
        bodyBone = teddy.body
        eyeNodes = teddy.eyes
        earNodes = teddy.ears
        finishSetup()
    }

    private func finishSetup() {
        scene.background.contents = NSColor.clear
        headRest = headBone?.simdOrientation ?? simd_quatf(angle: 0, axis: [0, 1, 0])
        tailRest = tailBone?.simdOrientation ?? simd_quatf(angle: 0, axis: [0, 1, 0])

        // 归一化：最大边长缩放到 2.0，中心移到原点
        let (bbMin, bbMax) = modelRoot.boundingBox
        let size = SCNVector3(bbMax.x - bbMin.x, bbMax.y - bbMin.y, bbMax.z - bbMin.z)
        let maxDim = max(size.x, max(size.y, size.z))
        let scale = 2.0 / max(maxDim, 0.001)
        modelRoot.scale = SCNVector3(scale, scale, scale)
        let center = SCNVector3(
            (bbMin.x + bbMax.x) / 2 * scale,
            (bbMin.y + bbMax.y) / 2 * scale,
            (bbMin.z + bbMax.z) / 2 * scale
        )
        modelRoot.position = SCNVector3(-center.x, -center.y, -center.z)

        yawNode.addChildNode(modelRoot)
        hopNode.addChildNode(yawNode)
        scene.rootNode.addChildNode(hopNode)

        // 相机：正面略偏上，营造"坐在桌面看你"的视角
        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.01
        camera.zFar = 50
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        // 长焦镜头（低 FOV 减少透视畸变，玩具感更强）；取景留安全边距
        camera.fieldOfView = 30
        // 屏幕空间环境光遮蔽：凹处（嘴角/趾缝/领结褶）落下接触阴影，细节才立体
        camera.screenSpaceAmbientOcclusionIntensity = 1.1
        camera.screenSpaceAmbientOcclusionRadius = 0.18
        cameraNode.position = SCNVector3(0, 0.55, 5.0)
        cameraNode.look(at: SCNVector3(0, -0.02, 0))
        scene.rootNode.addChildNode(cameraNode)

        // 三点布光：主光（暖）+ 补光（冷）+ 轮廓光（照亮绒毛边缘）
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light!.type = .directional
        keyLight.light!.intensity = 900
        keyLight.light!.color = NSColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        // 柔和自投影：下巴投在胸口、头投在身体，部件之间有深度分离
        keyLight.light!.castsShadow = true
        keyLight.light!.shadowRadius = 7
        keyLight.light!.shadowSampleCount = 24
        keyLight.light!.shadowColor = NSColor(white: 0, alpha: 0.38)
        keyLight.light!.shadowMapSize = CGSize(width: 1024, height: 1024)
        keyLight.light!.automaticallyAdjustsShadowProjection = true
        keyLight.eulerAngles = SCNVector3(-Double.pi / 5, Double.pi / 7, 0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light!.type = .directional
        fillLight.light!.intensity = 300
        fillLight.light!.color = NSColor(red: 0.85, green: 0.90, blue: 1.0, alpha: 1)
        fillLight.eulerAngles = SCNVector3(-Double.pi / 12, -Double.pi / 4, 0)
        scene.rootNode.addChildNode(fillLight)

        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light!.type = .directional
        rimLight.light!.intensity = 500
        rimLight.light!.color = NSColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1)
        rimLight.eulerAngles = SCNVector3(Double.pi / 7, Double.pi - 0.4, 0)
        scene.rootNode.addChildNode(rimLight)

        // 环境光压低：太强会把形体明暗洗平，细节全糊掉
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 300
        scene.rootNode.addChildNode(ambient)
    }

    static func loadAsset(completion: @escaping (Result<GLTFAsset, Error>) -> Void) {
        guard let url = Bundle.module.url(forResource: "cat", withExtension: "glb") else {
            completion(.failure(NSError(domain: "DeskCat", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到 cat.glb 资源"])))
            return
        }
        GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, maybeError, _ in
            DispatchQueue.main.async {
                if status == .complete, let asset = maybeAsset {
                    completion(.success(asset))
                } else {
                    completion(.failure(maybeError ?? NSError(domain: "DeskCat", code: 2, userInfo: [NSLocalizedDescriptionKey: "模型加载失败"])))
                }
            }
        }
    }

    /// 按形象类型构建场景（小猫需异步加载 GLB，泰迪熊同步生成）
    static func make(kind: CompanionKind, completion: @escaping (Result<CatScene, Error>) -> Void) {
        switch kind {
        case .teddy:
            completion(.success(CatScene(teddy: TeddyBuilder.build())))
        case .cat:
            loadAsset { result in
                completion(result.map { CatScene(asset: $0) })
            }
        }
    }
}
