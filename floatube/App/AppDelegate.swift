import AppKit
import SwiftUI
import YouTubePlayerKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var floatPanel: FloatPanel!
    private var playerWindows: [PlayerWindow] = []
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var playlistQueue: [(videoId: String, title: String)] = []
    private var currentQueueIndex: Int = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSWindow.allowsAutomaticWindowTabbing = false

        for window in NSApp.windows {
            window.close()
        }

        setupStatusItem()
        setupFloatPanel()
        setupGlobalHotkey()

        NotificationCenter.default.addObserver(
            forName: .floatubeSetPlaylistQueue,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let queue = notification.userInfo?["queue"] as? [[String: String]],
               let currentVideoId = notification.userInfo?["currentVideoId"] as? String {
                self?.playlistQueue = queue.compactMap { dict in
                    guard let videoId = dict["videoId"], let title = dict["title"] else { return nil }
                    return (videoId: videoId, title: title)
                }
                self?.currentQueueIndex = self?.playlistQueue.firstIndex(where: { $0.videoId == currentVideoId }) ?? 0
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            }
            button.toolTip = "Floatube"
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        if let playerWindow = playerWindows.first {
            let isActive = playerWindow.isVisible
            let playPauseItem = NSMenuItem(
                title: isActive ? "Pause" : "Play",
                action: #selector(playPauseClicked),
                keyEquivalent: ""
            )
            playPauseItem.image = NSImage(systemSymbolName: isActive ? "pause.fill" : "play.fill", accessibilityDescription: nil)
            playPauseItem.target = self
            menu.addItem(playPauseItem)

            if hasNextInQueue {
                let nextItem = NSMenuItem(title: "Next", action: #selector(playNextClicked), keyEquivalent: "")
                nextItem.image = NSImage(systemSymbolName: "forward.fill", accessibilityDescription: nil)
                nextItem.target = self
                menu.addItem(nextItem)
            }

            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About", action: #selector(openAbout), keyEquivalent: "i")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private var hasNextInQueue: Bool {
        !playlistQueue.isEmpty && currentQueueIndex + 1 < playlistQueue.count
    }

    @objc private func playNextClicked() {
        playNextInQueue()
    }

    private func playNextInQueue() {
        guard hasNextInQueue else { return }
        currentQueueIndex += 1
        let next = playlistQueue[currentQueueIndex]
        detachVideo(videoId: next.videoId, title: next.title, startTime: 0)
    }

    @objc private func playPauseClicked() {
        guard let playerWindow = playerWindows.first else { return }
        Task {
            await togglePlayPause(playerWindow: playerWindow)
        }
    }

    private func setupFloatPanel() {
        floatPanel = FloatPanel()
        let searchView = SearchView { [weak self] videoId, title, startTime, duration in
            self?.detachVideo(videoId: videoId, title: title, startTime: startTime, duration: duration)
        }
        floatPanel.contentView = NSHostingView(rootView: searchView)
    }

    private func setupGlobalHotkey() {
        installHotkeyMonitors()

        NotificationCenter.default.addObserver(
            forName: .floatubeHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.installHotkeyMonitors()
        }
    }

    private func installHotkeyMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }

        let savedKeyCode = UserDefaults.standard.integer(forKey: "floatube.hotkeyKeyCode")
        let savedMods = UserDefaults.standard.integer(forKey: "floatube.hotkeyModifiers")

        let targetKeyCode: UInt16
        let targetModifiers: NSEvent.ModifierFlags

        if savedKeyCode == 0 && savedMods == 0 {
            targetKeyCode = 16
            targetModifiers = [.command, .shift]
        } else {
            targetKeyCode = UInt16(savedKeyCode)
            targetModifiers = NSEvent.ModifierFlags(rawValue: UInt(savedMods))
                .intersection([.command, .shift, .option, .control])
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if eventMods == targetModifiers && event.keyCode == targetKeyCode {
                DispatchQueue.main.async {
                    self?.togglePanel()
                }
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if eventMods == targetModifiers && event.keyCode == targetKeyCode {
                DispatchQueue.main.async {
                    self?.togglePanel()
                }
                return nil
            }
            return event
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePanel()
        }
    }

    private func togglePlayPause(playerWindow: PlayerWindow) async {
        if playerWindow.isVisible {
            try? await playerWindow.player.pause()
            playerWindow.orderOut(nil)
            await saveCurrentTime(for: playerWindow)
        } else {
            playerWindow.orderFrontRegardless()
            playerWindow.makeKey()
            try? await playerWindow.player.play()
        }
    }

    private func saveCurrentTime(for playerWindow: PlayerWindow) async {
        let seconds = (try? await playerWindow.player.getCurrentTime())?.converted(to: .seconds).value ?? 0
        let duration = (try? await playerWindow.player.getDuration())?.converted(to: .seconds).value ?? 0

        if duration > 0 && (duration - seconds) < 60 {
            clearLastPlayed()
        } else {
            UserDefaults.standard.set(seconds, forKey: "floatube.lastVideoTime")
            if duration > 0 {
                UserDefaults.standard.set(duration, forKey: "floatube.lastVideoDuration")
            }
        }
    }

    private func clearLastPlayed() {
        UserDefaults.standard.removeObject(forKey: "floatube.lastVideoId")
        UserDefaults.standard.removeObject(forKey: "floatube.lastVideoTitle")
        UserDefaults.standard.removeObject(forKey: "floatube.lastVideoTime")
        UserDefaults.standard.removeObject(forKey: "floatube.lastVideoDuration")
    }

    @objc private func openAbout() {
        if let existing = aboutWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.contentView = NSHostingView(rootView: AboutView())
        window.title = "About Floatube"
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        aboutWindow = window
    }

    @objc private func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.contentView = NSHostingView(rootView: SettingsView())
        window.title = "Floatube Settings"
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func togglePanel() {
        floatPanel.toggleVisibility()
    }

    func detachVideo(videoId: String, title: String, startTime: Double, duration: String? = nil) {
        for window in playerWindows {
            window.delegate = nil
            window.close()
        }
        playerWindows.removeAll()

        floatPanel.hidePanel()
        saveLastPlayed(videoId: videoId, title: title, time: startTime)
        NotificationCenter.default.post(name: .floatubeDetachedPlayerActive, object: nil, userInfo: ["active": true])
        PlayerWindow.pauseSystemMedia()

        let window = PlayerWindow(videoId: videoId, videoTitle: title, startTime: startTime, duration: duration)
        window.delegate = self
        window.onAttach = { [weak self] vid, time in
            self?.attachVideo(videoId: vid, time: time)
        }
        window.onVideoEnded = { [weak self] in
            self?.playNextInQueue()
        }
        playerWindows.append(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func saveLastPlayed(videoId: String, title: String, time: Double) {
        UserDefaults.standard.set(videoId, forKey: "floatube.lastVideoId")
        UserDefaults.standard.set(title, forKey: "floatube.lastVideoTitle")
        UserDefaults.standard.set(time, forKey: "floatube.lastVideoTime")
    }

    func attachVideo(videoId: String, time: Double) {
        NotificationCenter.default.post(
            name: .floatubeAttachVideo,
            object: nil,
            userInfo: ["videoId": videoId, "time": time]
        )
        floatPanel.resizeForMode(isPlayer: true)
        floatPanel.showPanel()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender is PlayerWindow else { return frameSize }
        return NSSize(width: max(frameSize.width, 320), height: max(frameSize.height, 210))
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? PlayerWindow {
            let wasAttaching = window.isAttaching
            Task {
                await saveCurrentTime(for: window)
                playerWindows.removeAll { $0 === window }
                if playerWindows.isEmpty {
                    NotificationCenter.default.post(name: .floatubeDetachedPlayerActive, object: nil, userInfo: ["active": false])
                }
                if !wasAttaching {
                    floatPanel.resizeForMode(isPlayer: false)
                    floatPanel.showPanel()
                }
            }
        }
    }
}
