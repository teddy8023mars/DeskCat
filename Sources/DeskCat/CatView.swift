import AppKit
import SceneKit

/// 透明 SCNView：支持按住拖动小猫，点击触发互动。
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
        window.setFrameOrigin(CGPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
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
}
