import AppKit
import SwiftUI

extension Notification.Name {
    static let floatubePlayerModeChanged = Notification.Name("floatubePlayerModeChanged")
    static let floatubeAttachVideo = Notification.Name("floatubeAttachVideo")
    static let floatubeHotkeyChanged = Notification.Name("floatubeHotkeyChanged")
    static let floatubeOpacityChanged = Notification.Name("floatubeOpacityChanged")
    static let floatubeSetPlaylistQueue = Notification.Name("floatubeSetPlaylistQueue")
    static let floatubePlaylistChanged = Notification.Name("floatubePlaylistChanged")
    static let floatubePanelWillHide = Notification.Name("floatubePanelWillHide")
    static let floatubeDetachedPlayerActive = Notification.Name("floatubeDetachedPlayerActive")
}

class FloatPanel: NSPanel {
    static let searchSize = NSSize(width: 600, height: 600)
    static let toolbarHeight: CGFloat = 49
    static let playerSize = NSSize(width: 600, height: 600 * 9.0 / 16.0 + toolbarHeight)

    private var clickOutsideMonitor: Any?
    private var modeObserver: NSObjectProtocol?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.searchSize),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.transient, .ignoresCycle]
        isRestorable = false

        minSize = Self.searchSize
        maxSize = Self.searchSize

        setContentSize(Self.searchSize)
        centerOnScreen()

        modeObserver = NotificationCenter.default.addObserver(
            forName: .floatubePlayerModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let isPlayer = (notification.userInfo?["isPlayer"] as? Bool) ?? false
            self?.resizeForMode(isPlayer: isPlayer)
        }
    }

    deinit {
        if let observer = modeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func resizeForMode(isPlayer: Bool) {
        let newSize = isPlayer ? Self.playerSize : Self.searchSize
        let currentFrame = frame
        let newY = currentFrame.origin.y + (currentFrame.height - newSize.height) / 2
        let newX = currentFrame.origin.x + (currentFrame.width - newSize.width) / 2
        let newFrame = NSRect(origin: NSPoint(x: newX, y: newY), size: newSize)

        minSize = newSize
        maxSize = newSize

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(newFrame, display: true)
        }
    }

    private func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let currentSize = frame.size
        let x = screenFrame.origin.x + (screenFrame.width - currentSize.width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - currentSize.height) / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        if isVisible {
            NotificationCenter.default.post(name: .floatubePanelWillHide, object: nil)
            hidePanel()
        }
    }

    func toggleVisibility() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        centerOnScreen()
        alphaValue = 0
        orderFrontRegardless()
        makeKey()

        startMonitoringClicks()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    func hidePanel() {
        stopMonitoringClicks()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }

    private func startMonitoringClicks() {
        stopMonitoringClicks()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            DispatchQueue.main.async {
                self.hidePanel()
            }
        }
    }

    private func stopMonitoringClicks() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
