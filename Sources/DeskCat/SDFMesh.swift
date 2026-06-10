import SceneKit
import simd

/// SDF（有向距离场）建模：把球体/胶囊用 smooth-minimum 融合成一个有机整体，
/// 再用 Surface Nets 网格化。部件衔接处是柔和的肉感过渡，而非生硬交线——
/// 这是程序化生成可爱角色的标准做法。颜色按距离场权重在顶点间平滑混合。
struct SDFBlob {
    enum Mode {
        case union    // 平滑并集（加形体）
        case subtract // 平滑减法（挖凹腔，比如嘴）
    }

    struct Part {
        let sdf: (SIMD3<Float>) -> Float
        let color: SIMD3<Float>
        let blend: Float // smooth-min 的 k：越大过渡越肉
        let mode: Mode
    }

    private(set) var parts: [Part] = []

    mutating func add(blend: Float, color: SIMD3<Float>, _ sdf: @escaping (SIMD3<Float>) -> Float) {
        parts.append(Part(sdf: sdf, color: color, blend: blend, mode: .union))
    }

    mutating func subtract(blend: Float, color: SIMD3<Float>, _ sdf: @escaping (SIMD3<Float>) -> Float) {
        parts.append(Part(sdf: sdf, color: color, blend: blend, mode: .subtract))
    }

    /// 距离 + 混合色（smooth-min/smooth-max 链式折叠）
    func eval(_ p: SIMD3<Float>) -> (d: Float, c: SIMD3<Float>) {
        var d = Float.greatestFiniteMagnitude
        var c = SIMD3<Float>(1, 1, 1)
        for part in parts {
            let pd = part.sdf(p)
            if d == .greatestFiniteMagnitude {
                d = pd
                c = part.color
                continue
            }
            let k = part.blend
            switch part.mode {
            case .union:
                let h = max(0, min(1, 0.5 + 0.5 * (pd - d) / k))
                d = pd * (1 - h) + d * h - k * h * (1 - h)
                c = part.color * (1 - h) + c * h
            case .subtract:
                // smax(d, -pd, k)：挖去 part 的形体；被挖出的内壁染成 part 的颜色
                let h = max(0, min(1, 0.5 + 0.5 * (d + pd) / k))
                d = -pd * (1 - h) + d * h + k * h * (1 - h)
                c = part.color * (1 - h) + c * h
            }
        }
        return (d, c)
    }

    func distance(_ p: SIMD3<Float>) -> Float {
        eval(p).d
    }

    /// 从 startZ 沿 -z 方向找表面 z 坐标（用于把眼睛/鼻子等配件贴在融合后的曲面上）
    func surfaceZ(x: Float, y: Float, from startZ: Float = 1.5) -> Float {
        var z = startZ
        var prev = distance(SIMD3(x, y, z))
        while z > -1.5 {
            let next = z - 0.02
            let d = distance(SIMD3(x, y, next))
            if d < 0 {
                // 二分细化
                var lo = next, hi = z
                for _ in 0..<8 {
                    let mid = (lo + hi) / 2
                    if distance(SIMD3(x, y, mid)) < 0 { lo = mid } else { hi = mid }
                }
                return (lo + hi) / 2
            }
            prev = d
            z = next
        }
        _ = prev
        return 0
    }
}

// MARK: - SDF 原语

enum SDF {
    static func sphere(center: SIMD3<Float>, radius: Float) -> (SIMD3<Float>) -> Float {
        { p in simd_length(p - center) - radius }
    }

    /// 椭球（iq 的近似距离公式，足够网格化使用）
    static func ellipsoid(center: SIMD3<Float>, radii: SIMD3<Float>) -> (SIMD3<Float>) -> Float {
        { p in
            let q = p - center
            let k0 = simd_length(q / radii)
            let k1 = simd_length(q / (radii * radii))
            return k0 * (k0 - 1.0) / max(k1, 1e-6)
        }
    }

    static func capsule(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float) -> (SIMD3<Float>) -> Float {
        { p in
            let pa = p - a
            let ba = b - a
            let h = max(0, min(1, simd_dot(pa, ba) / simd_dot(ba, ba)))
            return simd_length(pa - ba * h) - radius
        }
    }
}

// MARK: - Surface Nets 网格化

enum SDFMesh {
    /// 把 SDF 网格化成 SCNGeometry：顶点色 + 距离场梯度法线 + 绒毛边缘光着色器
    static func geometry(
        blob: SDFBlob,
        boundsMin: SIMD3<Float>,
        boundsMax: SIMD3<Float>,
        resolution n: Int
    ) -> SCNGeometry {
        let ns = n + 1 // 每轴采样数
        let step = (boundsMax - boundsMin) / Float(n)

        // 采样距离场
        var field = [Float](repeating: 0, count: ns * ns * ns)
        for x in 0..<ns {
            for y in 0..<ns {
                for z in 0..<ns {
                    let p = boundsMin + SIMD3(Float(x), Float(y), Float(z)) * step
                    field[(x * ns + y) * ns + z] = blob.distance(p)
                }
            }
        }
        func sample(_ x: Int, _ y: Int, _ z: Int) -> Float {
            field[(x * ns + y) * ns + z]
        }

        // 第一遍：有符号变化的体素放一个顶点（取棱上零交点的平均）
        var cellVertex = [Int32](repeating: -1, count: n * n * n)
        var positions: [SIMD3<Float>] = []
        let edges: [(SIMD3<Int>, SIMD3<Int>)] = {
            var result: [(SIMD3<Int>, SIMD3<Int>)] = []
            let corners = (0..<8).map { SIMD3<Int>($0 & 1, ($0 >> 1) & 1, ($0 >> 2) & 1) }
            for i in 0..<8 {
                for j in (i + 1)..<8 {
                    let d = corners[i] &- corners[j]
                    if abs(d.x) + abs(d.y) + abs(d.z) == 1 {
                        result.append((corners[i], corners[j]))
                    }
                }
            }
            return result
        }()

        for x in 0..<n {
            for y in 0..<n {
                for z in 0..<n {
                    var inside = 0
                    for c in 0..<8 {
                        let v = sample(x + (c & 1), y + ((c >> 1) & 1), z + ((c >> 2) & 1))
                        if v < 0 { inside += 1 }
                    }
                    guard inside > 0 && inside < 8 else { continue }

                    var sum = SIMD3<Float>(0, 0, 0)
                    var count: Float = 0
                    for (a, b) in edges {
                        let va = sample(x + a.x, y + a.y, z + a.z)
                        let vb = sample(x + b.x, y + b.y, z + b.z)
                        guard (va < 0) != (vb < 0) else { continue }
                        let t = va / (va - vb)
                        let pa = SIMD3<Float>(Float(x + a.x), Float(y + a.y), Float(z + a.z))
                        let pb = SIMD3<Float>(Float(x + b.x), Float(y + b.y), Float(z + b.z))
                        sum += pa + (pb - pa) * t
                        count += 1
                    }
                    cellVertex[(x * n + y) * n + z] = Int32(positions.count)
                    positions.append(boundsMin + (sum / count) * step)
                }
            }
        }

        // 第二遍：每条符号变化的样本棱，连接周围 4 个体素的顶点成 2 个三角形
        var indices: [Int32] = []
        func cellIndex(_ x: Int, _ y: Int, _ z: Int) -> Int32 {
            cellVertex[(x * n + y) * n + z]
        }
        func emitQuad(_ a: Int32, _ b: Int32, _ c: Int32, _ d: Int32, flip: Bool) {
            guard a >= 0, b >= 0, c >= 0, d >= 0 else { return }
            if flip {
                indices.append(contentsOf: [a, c, b, a, d, c])
            } else {
                indices.append(contentsOf: [a, b, c, a, c, d])
            }
        }
        for x in 1..<n {
            for y in 1..<n {
                for z in 1..<n {
                    let v0 = sample(x, y, z)
                    // x 方向棱（绕向推导：B-A=+y, C-B=+z, ŷ×ẑ=+x̂ → v0 在内侧时原序即朝外）
                    if x + 1 <= n {
                        let v1 = sample(x + 1, y, z)
                        if (v0 < 0) != (v1 < 0) {
                            emitQuad(
                                cellIndex(x, y - 1, z - 1), cellIndex(x, y, z - 1),
                                cellIndex(x, y, z), cellIndex(x, y - 1, z),
                                flip: v0 > 0
                            )
                        }
                    }
                    // y 方向棱（ẑ×x̂=+ŷ）
                    if y + 1 <= n {
                        let v1 = sample(x, y + 1, z)
                        if (v0 < 0) != (v1 < 0) {
                            emitQuad(
                                cellIndex(x - 1, y, z - 1), cellIndex(x - 1, y, z),
                                cellIndex(x, y, z), cellIndex(x, y, z - 1),
                                flip: v0 > 0
                            )
                        }
                    }
                    // z 方向棱
                    if z + 1 <= n {
                        let v1 = sample(x, y, z + 1)
                        if (v0 < 0) != (v1 < 0) {
                            emitQuad(
                                cellIndex(x - 1, y - 1, z), cellIndex(x, y - 1, z),
                                cellIndex(x, y, z), cellIndex(x - 1, y, z),
                                flip: v0 > 0
                            )
                        }
                    }
                }
            }
        }

        // 拉普拉斯平滑：消除顶点沿采样网格分层造成的阶梯环纹
        var neighbors = [[Int32]](repeating: [], count: positions.count)
        var t = 0
        while t < indices.count {
            let (a, b, c) = (indices[t], indices[t + 1], indices[t + 2])
            neighbors[Int(a)].append(contentsOf: [b, c])
            neighbors[Int(b)].append(contentsOf: [a, c])
            neighbors[Int(c)].append(contentsOf: [a, b])
            t += 3
        }
        for _ in 0..<3 {
            var smoothed = positions
            for i in 0..<positions.count where !neighbors[i].isEmpty {
                var avg = SIMD3<Float>(0, 0, 0)
                for nb in neighbors[i] { avg += positions[Int(nb)] }
                avg /= Float(neighbors[i].count)
                smoothed[i] = positions[i] + (avg - positions[i]) * 0.55
            }
            positions = smoothed
        }

        // 法线：先算每顶点的距离场梯度作为朝向参考
        var gradients = [SIMD3<Float>](repeating: .zero, count: positions.count)
        let geps: Float = step.x
        for i in 0..<positions.count {
            let p = positions[i]
            gradients[i] = SIMD3(
                blob.distance(p + SIMD3(geps, 0, 0)) - blob.distance(p - SIMD3(geps, 0, 0)),
                blob.distance(p + SIMD3(0, geps, 0)) - blob.distance(p - SIMD3(0, geps, 0)),
                blob.distance(p + SIMD3(0, 0, geps)) - blob.distance(p - SIMD3(0, 0, geps))
            )
        }
        // 三角形面法线按面积加权累积；环绕方向不保证一致，
        // 累积前先按梯度统一每个面的朝向（否则相互抵消）
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        t = 0
        while t < indices.count {
            let ia = Int(indices[t]), ib = Int(indices[t + 1]), ic = Int(indices[t + 2])
            var faceN = simd_cross(positions[ib] - positions[ia], positions[ic] - positions[ia])
            if simd_dot(faceN, gradients[ia] + gradients[ib] + gradients[ic]) < 0 {
                faceN = -faceN
            }
            normals[ia] += faceN
            normals[ib] += faceN
            normals[ic] += faceN
            t += 3
        }
        for i in 0..<normals.count {
            normals[i] = simd_length_squared(normals[i]) < 1e-12
                ? simd_normalize(gradients[i])
                : simd_normalize(normals[i])
        }

        // 顶点色（含轻微纤维明暗变化，模拟绒毛布料）
        var colors: [SIMD3<Float>] = []
        colors.reserveCapacity(positions.count)
        for (i, p) in positions.enumerated() {
            var c = blob.eval(p).c
            // 按顶点序号哈希的纤维噪声（基于位置会和网格化顶点的规则分布产生摩尔纹）
            let h = sin(Float(i) * 12.9898 + 78.233) * 43758.5453
            let grain = (h - h.rounded(.down)) * 2 - 1
            c *= 1 + 0.03 * grain
            c = simd_clamp(c, SIMD3(0, 0, 0), SIMD3(1, 1, 1))
            // SceneKit 顶点色按线性空间解读，需要 sRGB → 线性转换，否则发白
            colors.append(SIMD3(pow(c.x, 2.2), pow(c.y, 2.2), pow(c.z, 2.2)))
        }

        if ProcessInfo.processInfo.environment["DC_MESHSTATS"] != nil {
            var maxAbs: Float = 0
            var sum: Float = 0
            for p in positions {
                let d = abs(blob.distance(p))
                maxAbs = max(maxAbs, d)
                sum += d
            }
            print(String(
                format: "网格统计: 顶点 %d 三角形 %d | 顶点偏离表面 平均 %.4f 最大 %.4f (体素 %.4f)",
                positions.count, indices.count / 3, sum / Float(positions.count), maxAbs, step.x
            ))
        }

        return makeGeometry(positions: positions, normals: normals, colors: colors, indices: indices)
    }

    private static func makeGeometry(
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        colors: [SIMD3<Float>],
        indices: [Int32]
    ) -> SCNGeometry {
        func source(_ values: [SIMD3<Float>], semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
            var flat: [Float] = []
            flat.reserveCapacity(values.count * 3)
            for v in values { flat.append(contentsOf: [v.x, v.y, v.z]) }
            let data = flat.withUnsafeBufferPointer { Data(buffer: $0) }
            return SCNGeometrySource(
                data: data,
                semantic: semantic,
                vectorCount: values.count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<Float>.size * 3
            )
        }
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        let geometry = SCNGeometry(
            sources: [
                source(positions, semantic: .vertex),
                source(normals, semantic: .normal),
                source(colors, semantic: .color),
            ],
            elements: [element]
        )

        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = NSColor.white // 与顶点色相乘
        material.isDoubleSided = true // 法线来自距离场梯度，与三角形环绕方向无关
        material.shaderModifiers = [
            .surface: """
            float fuzz = pow(1.0 - max(0.0, dot(normalize(_surface.view), _surface.normal)), 2.2);
            _surface.diffuse.rgb += fuzz * 0.28 * _surface.diffuse.rgb;
            """
        ]
        geometry.materials = [material]
        return geometry
    }
}
