import AppKit
import SceneKit

/// 透明 SCNView：支持按住拖动，点击触发互动；拖动时窗口被限制在屏幕内。
final class CatView: SCNView {
    var onMoved: ((CGRect) -> Void)?
    var onPet: (() -> Void)?

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
        window.setFrameOrigin(Self.clamp(origin: target, size: window.frame.size, near: window))
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

    /// 边缘检测：把窗口原点限制在最近屏幕的可见范围内（不遮挡菜单栏/程序坞）
    static func clamp(origin: CGPoint, size: CGSize, near window: NSWindow?) -> CGPoint {
        let screen = window?.screen
            ?? NSScreen.screens.first { $0.frame.contains(origin) }
            ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return origin }
        return CGPoint(
            x: min(max(origin.x, bounds.minX), bounds.maxX - size.width),
            y: min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        )
    }
}
