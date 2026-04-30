import AppKit
import Combine
import SwiftUI
import YouTubePlayerKit

class PlayerWindow: NSPanel {
    let videoId: String
    let player: YouTubePlayer
    var onAttach: ((String, Double) -> Void)?
    var onVideoEnded: (() -> Void)?
    var isAttaching = false
    private var opacityObserver: NSObjectProtocol?
    private var playbackEndObserver: AnyCancellable?
    let videoTitle: String
    let duration: String?

    init(videoId: String, videoTitle: String, startTime: Double = 0, duration: String? = nil) {
        self.duration = duration
        self.videoId = videoId
        self.videoTitle = videoTitle
        self.player = YouTubePlayer(
            source: .video(id: videoId),
            parameters: .init(
                autoPlay: true,
                startTime: startTime > 1 ? .init(value: startTime, unit: .seconds) : nil,
                showFullscreenButton: false
            ),
            configuration: .init(fullscreenMode: .system)
        )
        let playerRef = self.player
        Task {
            for _ in 0..<30 {
                if playerRef.state == .ready {
                    try? await playerRef.play()
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 390),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Floatube"
        titlebarAppearsTransparent = true
        level = .floating
        isFloatingPanel = true
        isMovableByWindowBackground = true
        backgroundColor = .black
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 320, height: 210)

        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        setupAccessoryButtons()

        contentView = NSHostingView(rootView: VideoPlayerView(player: player))
        applyPlacement()

        let storedOpacity = UserDefaults.standard.double(forKey: "floatube.playerOpacity")
        alphaValue = storedOpacity > 0 ? storedOpacity : 1.0

        opacityObserver = NotificationCenter.default.addObserver(
            forName: .floatubeOpacityChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let newOpacity = UserDefaults.standard.double(forKey: "floatube.playerOpacity")
            self?.animator().alphaValue = newOpacity > 0 ? newOpacity : 1.0
        }

        observePlaybackCompletion()
    }

    private func observePlaybackCompletion() {
        playbackEndObserver = player.playbackStatePublisher
            .filter { $0 == .ended }
            .first()
            .sink { [weak self] _ in self?.onVideoEnded?() }
    }

    static func pauseSystemMedia() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let sym = dlsym(handle, "MRMediaRemoteSendCommand") else { return }
        typealias SendCommand = @convention(c) (UInt32, AnyObject?) -> Void
        unsafeBitCast(sym, to: SendCommand.self)(1, nil)
    }

    private func setupAccessoryButtons() {
        let isDetachedMode = (UserDefaults.standard.string(forKey: "floatube.playerMode") ?? "Inline") == "Detached"

        let moreButton = NSButton(
            image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More")!,
            target: self,
            action: #selector(moreButtonClicked(_:))
        )
        moreButton.bezelStyle = .accessoryBarAction
        moreButton.isBordered = false
        moreButton.toolTip = "More Options"

        if isDetachedMode {
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 28))
            moreButton.frame = NSRect(x: 12, y: 0, width: 28, height: 28)
            container.addSubview(moreButton)

            let accessoryVC = NSTitlebarAccessoryViewController()
            accessoryVC.layoutAttribute = .trailing
            accessoryVC.view = container
            addTitlebarAccessoryViewController(accessoryVC)
        } else {
            let attachButton = NSButton(
                image: NSImage(systemSymbolName: "pip", accessibilityDescription: "Attach to inline player")!,
                target: self,
                action: #selector(attachButtonClicked)
            )
            attachButton.bezelStyle = .accessoryBarAction
            attachButton.isBordered = false
            attachButton.toolTip = "Attach to Inline Player"

            let container = NSView(frame: NSRect(x: 0, y: 0, width: 76, height: 28))
            moreButton.frame = NSRect(x: 12, y: 0, width: 28, height: 28)
            attachButton.frame = NSRect(x: 44, y: 0, width: 28, height: 28)
            container.addSubview(moreButton)
            container.addSubview(attachButton)

            let accessoryVC = NSTitlebarAccessoryViewController()
            accessoryVC.layoutAttribute = .trailing
            accessoryVC.view = container
            addTitlebarAccessoryViewController(accessoryVC)
        }
    }

    @objc private func attachButtonClicked() { handleAttach() }

    private func handleAttach() {
        Task {
            let seconds = (try? await player.getCurrentTime())?.converted(to: .seconds).value ?? 0
            isAttaching = true
            onAttach?(videoId, seconds)
            close()
        }
    }

    deinit {
        if let opacityObserver { NotificationCenter.default.removeObserver(opacityObserver) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func rightMouseDown(with event: NSEvent) {}

    @objc private func moreButtonClicked(_ sender: NSButton) {
        let menu = NSMenu()

        let shareItem = NSMenuItem(title: "Share", action: #selector(shareVideo(_:)), keyEquivalent: "")
        shareItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        shareItem.target = self
        shareItem.representedObject = sender
        menu.addItem(shareItem)

        let isFullscreen = styleMask.contains(.fullScreen)
        let fullscreenItem = NSMenuItem(
            title: isFullscreen ? "Exit Fullscreen" : "Fullscreen",
            action: #selector(enterFullscreen),
            keyEquivalent: ""
        )
        fullscreenItem.image = NSImage(
            systemSymbolName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: nil
        )
        fullscreenItem.target = self
        menu.addItem(fullscreenItem)

        let store = PlaylistStore()
        if store.playlists.count == 1 {
            let addItem = NSMenuItem(title: "Add to Playlist", action: #selector(addToDefaultPlaylist(_:)), keyEquivalent: "")
            addItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            addItem.target = self
            addItem.representedObject = store
            menu.addItem(addItem)
        } else {
            let addToPlaylistItem = NSMenuItem(title: "Add to Playlist", action: nil, keyEquivalent: "")
            addToPlaylistItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            addToPlaylistItem.submenu = buildPlaylistSubmenu(store: store)
            menu.addItem(addToPlaylistItem)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    private func buildPlaylistSubmenu(store: PlaylistStore) -> NSMenu {
        let submenu = NSMenu()
        for (index, playlist) in store.playlists.enumerated() {
            let item = NSMenuItem(title: playlist.name, action: #selector(addToPlaylistClicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.representedObject = store
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func addToDefaultPlaylist(_ sender: NSMenuItem) {
        guard let store = sender.representedObject as? PlaylistStore,
              let playlist = store.playlists.first else { return }
        store.addItem(PlaylistItem(
            videoId: videoId, title: videoTitle, channelTitle: "",
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg"),
            duration: duration
        ), to: playlist.id)
    }

    @objc private func addToPlaylistClicked(_ sender: NSMenuItem) {
        guard let store = sender.representedObject as? PlaylistStore else { return }
        let index = sender.tag
        guard index < store.playlists.count else { return }
        store.addItem(PlaylistItem(
            videoId: videoId, title: videoTitle, channelTitle: "",
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg"),
            duration: duration
        ), to: store.playlists[index].id)
    }

    @objc private func enterFullscreen() {
        collectionBehavior.insert(.fullScreenPrimary)
        toggleFullScreen(nil)
    }

    @objc private func shareVideo(_ sender: NSMenuItem) {
        let url = "https://youtu.be/\(videoId)"
        let picker = NSSharingServicePicker(items: [url])
        if let button = sender.representedObject as? NSView {
            picker.show(relativeTo: .zero, of: button, preferredEdge: .minY)
        }
    }

    private func applyPlacement() {
        guard let screen = NSScreen.main else { center(); return }
        let visibleFrame = screen.visibleFrame
        let padding: CGFloat = 20
        let stored = UserDefaults.standard.string(forKey: "floatube.playerPlacement") ?? "Center"
        let placement = PlayerPlacement(rawValue: stored) ?? .center

        let origin: NSPoint
        switch placement {
        case .center:
            origin = NSPoint(x: visibleFrame.midX - frame.width / 2,
                             y: visibleFrame.midY - frame.height / 2)
        case .topLeft:
            origin = NSPoint(x: visibleFrame.minX + padding,
                             y: visibleFrame.maxY - frame.height - padding)
        case .topRight:
            origin = NSPoint(x: visibleFrame.maxX - frame.width - padding,
                             y: visibleFrame.maxY - frame.height - padding)
        case .bottomLeft:
            origin = NSPoint(x: visibleFrame.minX + padding,
                             y: visibleFrame.minY + padding)
        case .bottomRight:
            origin = NSPoint(x: visibleFrame.maxX - frame.width - padding,
                             y: visibleFrame.minY + padding)
        }
        setFrameOrigin(origin)
    }
}
