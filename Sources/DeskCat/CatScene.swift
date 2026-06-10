import AppKit
import SceneKit
import GLTFKit2

/// 负责加载 GLB 模型、搭建场景（相机/灯光）、定位骨骼节点。
final class CatScene {
    let scene: SCNScene

    /// 层级：root → hopNode(跳跃/挤压) → yawNode(身体转向) → modelRoot(归一化缩放) → glTF 内容
    let hopNode = SCNNode()
    let yawNode = SCNNode()
    let modelRoot = SCNNode()

    let headBone: SCNNode?
    let tailBone: SCNNode?
    let bodyBone: SCNNode?

    let headRest: simd_quatf
    let tailRest: simd_quatf

    init(asset: GLTFAsset) throws {
        let gltfScene = SCNScene(gltfAsset: asset)

        scene = SCNScene()
        scene.background.contents = NSColor.clear

        for child in gltfScene.rootNode.childNodes {
            modelRoot.addChildNode(child)
        }

        // 漫画感：扁平着色，避免 PBR 在简单灯光下显脏
        modelRoot.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] {
                material.lightingModel = .lambert
            }
        }

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

        headBone = modelRoot.childNode(withName: "Head", recursively: true)
        tailBone = modelRoot.childNode(withName: "Tail", recursively: true)
        bodyBone = modelRoot.childNode(withName: "Body", recursively: true)
        headRest = headBone?.simdOrientation ?? simd_quatf(angle: 0, axis: [0, 1, 0])
        tailRest = tailBone?.simdOrientation ?? simd_quatf(angle: 0, axis: [0, 1, 0])

        // 相机：正面略偏上，营造"小猫坐在桌面看你"的视角
        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.01
        camera.zFar = 50
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.55, 3.4)
        cameraNode.look(at: SCNVector3(0, 0.1, 0))
        scene.rootNode.addChildNode(cameraNode)

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light!.type = .directional
        keyLight.light!.intensity = 900
        keyLight.eulerAngles = SCNVector3(-Double.pi / 5, Double.pi / 8, 0)
        scene.rootNode.addChildNode(keyLight)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 550
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
}
