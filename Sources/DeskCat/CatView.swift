import AppKit
import SceneKit

/// 透明 SCNView：支持按住拖动，点击触发互动；拖动时把"模型可见轮廓"（而非
/// 整个带透明边距的窗口）限制在屏幕内。
final class CatView: SCNView {
    var onMoved: ((CGRect) -> Void)?
    var onPet: (() -> Void)?

    private var cachedInsets: NSEdgeInsets?
    private var dragStartMouse = CGPoint.zero
    private var dragStartOrigin = CGPoint.zero
    private var dragged = false

    /// 切换形象后调用：透明边距需要按新模型重算
    func invalidateInsets() {
        cachedInsets = nil
    }

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

    /// 模型在视图里的透明边距：截取当前帧，逐像素扫描 alpha 求可见轮廓的精确范围
    func modelInsets() -> NSEdgeInsets {
        if let cachedInsets { return cachedInsets }
        guard bounds.width > 1 else { return NSEdgeInsets() }

        let image = snapshot()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              rep.bitsPerSample == 8,
              rep.hasAlpha,
              let data = rep.bitmapData else {
            return NSEdgeInsets()
        }

        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let spp = rep.samplesPerPixel
        let bpr = rep.bytesPerRow
        let alphaOffset = spp - 1 // RGBA，alpha 在末位

        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            let row = data + y * bpr
            for x in 0..<width {
                if row[x * spp + alphaOffset] > 8 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= 0 else { return NSEdgeInsets() }

        // 像素 → 视图点（位图 y=0 是顶部）
        let sx = bounds.width / CGFloat(width)
        let sy = bounds.height / CGFloat(height)
        let insets = NSEdgeInsets(
            top: CGFloat(minY) * sy,
            left: CGFloat(minX) * sx,
            bottom: bounds.height - CGFloat(maxY + 1) * sy,
            right: bounds.width - CGFloat(maxX + 1) * sx
        )
        cachedInsets = insets
        if ProcessInfo.processInfo.environment["DC_DEBUG"] != nil {
            NSLog("DeskCat insets: top %.1f left %.1f bottom %.1f right %.1f",
                  insets.top, insets.left, insets.bottom, insets.right)
        }
        return insets
    }

    /// 边缘检测：模型可见轮廓不能超出屏幕；窗口可以超出透明边距那部分
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
