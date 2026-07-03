import SceneKit
import simd

/// Shell texturing 毛发：在 SDF 网格外沿法线挤出多层半透"壳"，每层按一张
/// 发丝高度图裁剪——发丝越高、越外层留存越少，由内到外逐渐稀疏，形成有体积、
/// 能透光的绒毛。布料（冷色顶点）整层丢弃。
///
/// 关键：高度图用 **cell 单元（每格一撮毛、圆形渐隐）** 而非连续高频噪声，
/// 否则发丝比像素还细、硬裁剪会变成"电视雪花"。再叠一个梳理方向让发丝下垂成股。
enum FurShell {
    /// - length: 毛发总长度（模型空间单位）
    /// - layers: 壳层数，越多越顺滑、越费
    /// - density: 发丝密度（每单位的撮数；越小撮越大越不像雪花）
    /// - color: 没有顶点色的几何体（如 SCNSphere 耳朵）需显式传底色；
    ///          SDF 网格自带顶点色，留 nil 即用白色与顶点色相乘
    static func add(to node: SCNNode, length: Float, layers: Int = 16, density: Float = 34, color: NSColor? = nil) {
        guard let base = node.geometry else { return }
        for i in 1...layers {
            let t = Float(i) / Float(layers) // 0..1：由内到外
            guard let shell = base.copy() as? SCNGeometry else { continue }
            let mat = SCNMaterial()
            mat.lightingModel = .lambert
            mat.diffuse.contents = color ?? NSColor.white // 与顶点色相乘（无顶点色时即纯底色）
            mat.isDoubleSided = true
            mat.setValue(NSNumber(value: t), forKey: "shellT")
            mat.setValue(NSNumber(value: length), forKey: "furLength")
            mat.setValue(NSNumber(value: density), forKey: "furDensity")
            mat.shaderModifiers = [
                .geometry: geometryModifier,
                .surface: surfaceModifier,
            ]
            shell.materials = [mat]
            let shellNode = SCNNode(geometry: shell)
            shellNode.castsShadow = false // 多层叠加投影会糊成一团，交给底层皮肤投影
            node.addChildNode(shellNode)
        }
    }

    /// 顶点沿法线外推，并随高度向重力方向横向偏移 → 发丝下垂成股
    private static let geometryModifier = """
    #pragma arguments
    float shellT;
    float furLength;
    #pragma body
    float h = shellT * furLength;
    float3 up = normalize(_geometry.normal);
    float3 grav = float3(0.0, -1.0, 0.0);
    float3 comb = grav - up * dot(grav, up);          // 重力在切平面上的分量
    _geometry.position.xyz += up * h + comb * (furLength * 0.5 * shellT * shellT);
    """

    /// 按"一撮一撮"的高度图裁剪 + 根暗梢亮的体积明暗
    private static let surfaceModifier = """
    #pragma arguments
    float shellT;
    float furDensity;
    #pragma declarations
    float dc_fs_hash(float3 p) {
        return fract(sin(dot(p, float3(12.9898, 78.233, 37.719))) * 43758.5453);
    }
    // 一撮毛的"凸起"：cell 中心高、边缘渐隐为 0（圆形轮廓），0..1 稀疏
    float dc_bump(float3 q) {
        float3 cell = floor(q);
        float3 f = fract(q) - 0.5;
        float rnd = dc_fs_hash(cell);
        return rnd * (1.0 - smoothstep(0.12, 0.5, length(f)));
    }
    #pragma body
    // 世界空间采样（模型基本不平移，纹理稳定）
    float3 mp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    // 布料（蓝>红）不长毛：整层丢弃
    float cloth = clamp((_surface.diffuse.b - _surface.diffuse.r) * 20.0, 0.0, 1.0);
    if (cloth > 0.4) { discard_fragment(); }
    // 域扭曲打散轴对齐的网格规则感（否则成撮会排成织纹）
    float3 warp = float3(dc_fs_hash(floor(mp * 8.0)),
                         dc_fs_hash(floor(mp * 8.0) + 5.0),
                         dc_fs_hash(floor(mp * 8.0) + 9.0)) - 0.5;
    float3 q = mp * furDensity + warp * 1.5;
    // 适中基线 + 明显凸起：内层成片软毛底，外层稀疏长发丝飘出 → 看得见的绒毛
    float bump = max(dc_bump(q), dc_bump(q * 1.7 + float3(13.0, 7.0, 21.0)));
    float height = 0.34 + 0.66 * bump;   // 0.34..1.0
    if (shellT > height) { discard_fragment(); }
    // 体积明暗：发根暗、发梢亮，对比拉开才看得出一根根
    _surface.diffuse.rgb *= mix(0.55, 1.18, shellT);
    // 发梢逆光背散射，绒毛通透感
    float rim = pow(1.0 - max(0.0, dot(normalize(_surface.view), _surface.normal)), 2.0);
    _surface.diffuse.rgb += rim * 0.25 * shellT * _surface.diffuse.rgb;
    """
}
