import AppKit
import SceneKit
import GLTFKit2

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var catView: CatView?
    private var brain: CatBrain?
    private var catScene: CatScene?
    private var statusItem: NSStatusItem?

    private static let windowSize: CGFloat = 260
    private static let posXKey = "DeskCatX"
    private static let posYKey = "DeskCatY"

    func applicationDidFinishLaunching(_ notification: Notification) {
        CatScene.loadAsset { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let asset):
                do {
                    let catScene = try CatScene(asset: asset)
                    self.catScene = catScene
                    if let path = Self.snapshotPath() {
                        Snapshot.render(scene: catScene, to: path)
                        NSApp.terminate(nil)
                    } else {
                        self.setUpWindow(with: catScene)
                        self.setUpStatusItem()
                    }
                } catch {
                    self.fail(error)
                }
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "DeskCat 启动失败"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApp.terminate(nil)
    }

    private static func snapshotPath() -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private func setUpWindow(with catScene: CatScene) {
        let size = Self.windowSize
        let origin = savedOrigin() ?? defaultOrigin(size: size)
        let window = NSWindow(
            contentRect: CGRect(x: origin.x, y: origin.y, width: size, height: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.delegate = self

        let view = CatView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.scene = catScene.scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.isPlaying = true

        let brain = CatBrain(cat: catScene)
        brain.windowFrame = window.frame
        view.delegate = brain

        view.onMoved = { [weak self] frame in
            self?.brain?.windowFrame = frame
            self?.saveOrigin(frame.origin)
        }
        view.onPet = { [weak catScene] in
            catScene?.hopNode.runAction(CatBrain.hopAction())
        }

        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.catView = view
        self.brain = brain
    }

    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        brain?.windowFrame = window.frame
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "🐱"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示/隐藏小猫", action: #selector(toggleCat), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重置位置", action: #selector(resetPosition), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 DeskCat", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleCat() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func resetPosition() {
        guard let window else { return }
        let origin = defaultOrigin(size: Self.windowSize)
        window.setFrameOrigin(origin)
        brain?.windowFrame = window.frame
        saveOrigin(origin)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func defaultOrigin(size: CGFloat) -> CGPoint {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: screen.maxX - size - 40, y: screen.minY + 40)
    }

    private func savedOrigin() -> CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.posXKey) != nil else { return nil }
        return CGPoint(
            x: defaults.double(forKey: Self.posXKey),
            y: defaults.double(forKey: Self.posYKey)
        )
    }

    private func saveOrigin(_ origin: CGPoint) {
        let defaults = UserDefaults.standard
        defaults.set(origin.x, forKey: Self.posXKey)
        defaults.set(origin.y, forKey: Self.posYKey)
    }
}
