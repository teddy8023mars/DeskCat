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
    private static let companionKey = "DeskCatCompanion"

    private var kind: CompanionKind = .teddy

    func applicationDidFinishLaunching(_ notification: Notification) {
        kind = Self.initialKind()
        CatScene.make(kind: kind) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let catScene):
                self.catScene = catScene
                if let path = Self.snapshotPath() {
                    Snapshot.render(scene: catScene, to: path)
                    NSApp.terminate(nil)
                } else {
                    self.setUpWindow(with: catScene)
                    self.setUpStatusItem()
                }
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    /// 形象优先级：命令行参数 > 上次选择 > 默认泰迪熊
    private static func initialKind() -> CompanionKind {
        let args = CommandLine.arguments
        if args.contains("--cat") { return .cat }
        if args.contains("--teddy") { return .teddy }
        if let saved = UserDefaults.standard.string(forKey: companionKey),
           let kind = CompanionKind(rawValue: saved) {
            return kind
        }
        return .teddy
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
        // 恢复的位置也要做边缘检测（防止分辨率变化后留在屏幕外）
        let origin = CatView.clamp(
            origin: savedOrigin() ?? defaultOrigin(size: size),
            size: CGSize(width: size, height: size),
            near: nil
        )
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
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.isPlaying = true

        view.onMoved = { [weak self] frame in
            self?.brain?.windowFrame = frame
            self?.saveOrigin(frame.origin)
        }
        view.onPet = { [weak self] in
            self?.catScene?.hopNode.runAction(CatBrain.hopAction())
        }

        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.catView = view
        attach(catScene)

        if ProcessInfo.processInfo.environment["DC_DEBUG"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak view] in
                _ = view?.modelInsets()
            }
        }
    }

    /// 把场景接到视图上并重建大脑（首次启动和切换形象共用）
    private func attach(_ catScene: CatScene) {
        guard let view = catView, let window else { return }
        self.catScene = catScene
        let brain = CatBrain(cat: catScene)
        brain.windowFrame = window.frame
        view.scene = catScene.scene
        view.invalidateInsets()
        view.delegate = brain
        self.brain = brain
    }

    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        brain?.windowFrame = window.frame
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = kind == .teddy ? "🧸" : "🐱"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示/隐藏", action: #selector(toggleCat), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "切换形象（小猫/泰迪熊）", action: #selector(switchCompanion), keyEquivalent: ""))
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

    @objc private func switchCompanion() {
        kind = kind == .teddy ? .cat : .teddy
        UserDefaults.standard.set(kind.rawValue, forKey: Self.companionKey)
        statusItem?.button?.title = kind == .teddy ? "🧸" : "🐱"
        CatScene.make(kind: kind) { [weak self] result in
            switch result {
            case .success(let catScene):
                self?.attach(catScene)
            case .failure(let error):
                self?.fail(error)
            }
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
