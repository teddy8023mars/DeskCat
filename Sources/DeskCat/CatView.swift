import AppKit
import SceneKit

/// 透明 SCNView：支持按住拖动，点击触发互动；拖动时把"模型本体"（而非整个
/// 带透明边距的窗口）限制在屏幕内。
final class CatView: SCNView {
    var onMoved: ((CGRect) -> Void)?
    var onPet: (() -> Void)?

    /// 模型内容根节点（用于计算实际可见包围盒），切换形象时重新赋值
    var contentRoot: SCNNode? {
        didSet { cachedInsets = nil }
    }

    private var cachedInsets: NSEdgeInsets?
    private var dragStartMouse = CGPoint.zero
    private var dragStartOrigin = CGPoint.zero
    private var dragged = false

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStartMouse.x
        let dy = now.y - dragStartMouse.y
        if abs(dx) > 2 || abs(dy) > 2 { dragged = true }
        let target = CGPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy)
        window.setFrameOrigin(Self.clamp(
            origin: target,
            size: window.frame.size,
            near: window,
            insets: modelInsets()
        ))
        onMoved?(window.frame)
    }

    override func mouseUp(with event: NSEvent) {
        if let window {
            onMoved?(window.frame)
        }
        if !dragged {
            onPet?()
        }
    }

    /// 模型在视图里的透明边距：把模型包围盒 8 个角投影到视图坐标取范围
    private func modelInsets() -> NSEdgeInsets {
        if let cachedInsets { return cachedInsets }
        guard let contentRoot, bounds.width > 1 else { return NSEdgeInsets() }

        let (bbMin, bbMax) = contentRoot.boundingBox
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for x in [bbMin.x, bbMax.x] {
            for y in [bbMin.y, bbMax.y] {
                for z in [bbMin.z, bbMax.z] {
                    let world = contentRoot.convertPosition(SCNVector3(x, y, z), to: nil)
                    let p = projectPoint(world)
                    minX = min(minX, CGFloat(p.x)); maxX = max(maxX, CGFloat(p.x))
                    minY = min(minY, CGFloat(p.y)); maxY = max(maxY, CGFloat(p.y))
                }
            }
        }
        let insets = NSEdgeInsets(
            top: max(0, bounds.height - maxY),
            left: max(0, minX),
            bottom: max(0, minY),
            right: max(0, bounds.width - maxX)
        )
        cachedInsets = insets
        return insets
    }

    /// 边缘检测：模型本体不能超出屏幕；窗口可以超出透明边距那部分
    static func clamp(
        origin: CGPoint,
        size: CGSize,
        near window: NSWindow?,
        insets: NSEdgeInsets = NSEdgeInsets()
    ) -> CGPoint {
        let screen = window?.screen
            ?? NSScreen.screens.first { $0.frame.contains(origin) }
            ?? NSScreen.main
        guard let bounds = screen?.frame else { return origin }
        return CGPoint(
            x: min(max(origin.x, bounds.minX - insets.left), bounds.maxX - size.width + insets.right),
            y: min(max(origin.y, bounds.minY - insets.bottom), bounds.maxY - size.height + insets.top)
        )
    }
}
