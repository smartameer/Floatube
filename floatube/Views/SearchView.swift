import SwiftUI
import YouTubePlayerKit

struct SearchView: View {
    @State private var youtubeService = YouTubeService()
    @State private var searchHistory = SearchHistory()
    @State private var playlistStore = PlaylistStore()
    @State private var searchText = ""
    @State private var isMusicMode = false
    @State private var hasSearched = false
    @State private var playingVideoId: String?
    @State private var playingVideoTitle = ""
    @State private var youtubePlayer: YouTubePlayer?
    @State private var showingPlaylist = (UserDefaults.standard.string(forKey: "floatube.defaultMode") ?? "Search") == "Playlist"
    @State private var isIconHovered = false
    @State private var isAddingPlaylist = false
    @State private var newPlaylistName = ""
    @State private var selectedPlaylistId: UUID?
    @State private var isRenamingPlaylist = false
    @State private var isDeletingPlaylist = false
    @State private var renamePlaylistName = ""
    @State private var searchClearTask: Task<Void, Never>?
    @State private var hasDetachedPlayer = false

    var onDetachVideo: (String, String, Double) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let videoId = playingVideoId, let player = youtubePlayer {
                inlinePlayerView(videoId: videoId, player: player)
            } else if showingPlaylist {
                playlistBarView
                Divider()
                PlaylistView(store: playlistStore, selectedPlaylistId: $selectedPlaylistId) { videoId, title in
                    playVideo(id: videoId, title: title)
                }
            } else {
                searchBarView
                Divider()
                searchContentView
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: searchText) { _, newValue in
            searchClearTask?.cancel()
            searchClearTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, newValue.isEmpty else { return }
                youtubeService.results = []
                youtubeService.nextPageToken = nil
                hasSearched = false
            }
        }
        .onChange(of: playingVideoId) { _, newValue in
            NotificationCenter.default.post(
                name: .floatubePlayerModeChanged,
                object: nil,
                userInfo: ["isPlayer": newValue != nil]
            )
        }
        .task {
            for await notification in NotificationCenter.default.notifications(named: .floatubeAttachVideo) {
                if let videoId = notification.userInfo?["videoId"] as? String,
                   let time = notification.userInfo?["time"] as? Double {
                    youtubePlayer = makePlayer(videoId: videoId, startTime: time)
                    playingVideoId = videoId
                }
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .floatubePanelWillHide) {
                guard let videoId = playingVideoId, let player = youtubePlayer else { continue }
                let seconds = (try? await player.getCurrentTime())?.converted(to: .seconds).value ?? 0
                let title = playingVideoTitle
                playingVideoId = nil
                playingVideoTitle = ""
                youtubePlayer = nil
                onDetachVideo(videoId, title, seconds)
            }
        }
        .task {
            for await notification in NotificationCenter.default.notifications(named: .floatubeDetachedPlayerActive) {
                hasDetachedPlayer = notification.userInfo?["active"] as? Bool ?? false
            }
        }
    }

    private var searchBarView: some View {
        HStack(spacing: 14) {
            Button {
                showingPlaylist = true
                isIconHovered = false
            } label: {
                Image(systemName: isIconHovered ? "list.bullet" : "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.title)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Show Playlists")
            .onHover { hovering in
                isIconHovered = hovering
            }

            TextField("Search ...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .onSubmit { performSearch() }

            HStack(spacing: 4) {
                Button {
                    isMusicMode = false
                    if !searchText.isEmpty { performSearch() }
                } label: {
                    Image(systemName: "video.fill")
                        .font(.title3)
                        .frame(width: 34, height: 28)
                        .contentShape(Rectangle())
                        .foregroundStyle(isMusicMode ? .secondary : .primary)
                        .background(isMusicMode ? Color.clear : Color.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Search Videos")

                Button {
                    isMusicMode = true
                    if !searchText.isEmpty { performSearch() }
                } label: {
                    Image(systemName: "music.note")
                        .font(.title3)
                        .frame(width: 34, height: 28)
                        .contentShape(Rectangle())
                        .foregroundStyle(isMusicMode ? .primary : .secondary)
                        .background(isMusicMode ? Color.secondary.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Search Music")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private var isInlineMode: Bool {
        (UserDefaults.standard.string(forKey: "floatube.playerMode") ?? "Inline") == "Inline"
    }

    private var isInsidePlaylist: Bool {
        playlistStore.playlists.count == 1 || selectedPlaylistId != nil
    }

    private var currentPlaylistName: String {
        if isInsidePlaylist {
            if playlistStore.playlists.count == 1 {
                return "Playlist"
            }
            if let id = selectedPlaylistId {
                return playlistStore.playlists.first(where: { $0.id == id })?.name ?? "Playlist"
            }
        }
        return "Playlists"
    }

    private var currentPlaylistItems: [PlaylistItem] {
        if playlistStore.playlists.count == 1 {
            return playlistStore.playlists.first?.items ?? []
        }
        guard let id = selectedPlaylistId else { return [] }
        return playlistStore.playlists.first(where: { $0.id == id })?.items ?? []
    }

    private var currentPlaylistId: UUID? {
        if playlistStore.playlists.count == 1 {
            return playlistStore.playlists.first?.id
        }
        return selectedPlaylistId
    }

    private var currentPlaylistActualName: String {
        guard let id = currentPlaylistId else { return "" }
        return playlistStore.playlists.first(where: { $0.id == id })?.name ?? ""
    }

    private var playlistBarView: some View {
        HStack(spacing: 14) {
            if isAddingPlaylist {
                TextField("Playlist name", text: $newPlaylistName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .onSubmit { commitNewPlaylist() }

                Spacer()

                HStack(spacing: 8) {
                    Button(role: .cancel) {
                        isAddingPlaylist = false
                        newPlaylistName = ""
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("Cancel")

                    Button(role: .confirm) {
                        commitNewPlaylist()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Create Playlist")
                }
            } else if isDeletingPlaylist {
                Text("Delete \(currentPlaylistActualName)?")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 8) {
                    Button(role: .cancel) {
                        isDeletingPlaylist = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("Cancel")

                    Button(role: .destructive) {
                        if let id = currentPlaylistId {
                            playlistStore.removePlaylist(id: id)
                            selectedPlaylistId = nil
                        }
                        isDeletingPlaylist = false
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .help("Confirm Delete")
                }
            } else if isRenamingPlaylist {
                TextField("Playlist name", text: $renamePlaylistName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .onSubmit { commitRenamePlaylist() }

                Spacer()

                HStack(spacing: 8) {
                    Button(role: .cancel) {
                        isRenamingPlaylist = false
                        renamePlaylistName = ""
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("Cancel")

                    Button(role: .confirm) {
                        commitRenamePlaylist()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(renamePlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Rename Playlist")
                }
            } else {
                if isInsidePlaylist && playlistStore.playlists.count > 1 {
                    Button {
                        selectedPlaylistId = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.secondary)
                            .font(.title)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Back to Playlists")
                } else {
                    Button {
                        showingPlaylist = false
                        isIconHovered = false
                    } label: {
                        Image(systemName: isIconHovered ? "magnifyingglass" : "list.bullet")
                            .foregroundStyle(.secondary)
                            .font(.title)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Show Search")
                    .onHover { hovering in
                        isIconHovered = hovering
                    }
                }

                Text(currentPlaylistName)
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if isInsidePlaylist {
                    let currentPlaylist = currentPlaylistItems
                    HStack(spacing: 12) {
                        if playlistStore.playlists.count == 1 {
                            Button {
                                isAddingPlaylist = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!playlistStore.canAddPlaylist)
                            .help("New Playlist")
                        }

                        Button {
                            guard playingVideoId == nil else { return }
                            let shuffled = currentPlaylist.shuffled()
                            guard let item = shuffled.first else { return }
                            postPlaylistQueue(items: shuffled, currentVideoId: item.videoId)
                            onDetachVideo(item.videoId, item.title, 0)
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(currentPlaylist.isEmpty || playingVideoId != nil)
                        .help("Shuffle")

                        Button {
                            guard playingVideoId == nil else { return }
                            guard let item = currentPlaylist.first else { return }
                            postPlaylistQueue(items: currentPlaylist, currentVideoId: item.videoId)
                            onDetachVideo(item.videoId, item.title, 0)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(currentPlaylist.isEmpty || playingVideoId != nil)
                        .help("Play All")

                        Button {
                            showPlaylistMoreMenu()
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("More Options")
                    }
                } else {
                    Button {
                        isAddingPlaylist = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!playlistStore.canAddPlaylist)
                    .help("New Playlist")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(isDeletingPlaylist ? AnyShapeStyle(Color.red) : AnyShapeStyle(.ultraThinMaterial))
    }

    @ViewBuilder
    private var searchContentView: some View {
        if youtubeService.isLoading && youtubeService.results.isEmpty {
            Spacer()
            ProgressView("Searching...")
            Spacer()
        } else if let error = youtubeService.errorMessage {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
        } else if youtubeService.results.isEmpty && hasSearched {
            ContentUnavailableView.search(text: searchText)
                .frame(maxHeight: .infinity)
        } else if youtubeService.results.isEmpty {
            emptyStateView
        } else {
            resultsView
        }
    }

    private var showLastPlayed: Bool {
        UserDefaults.standard.object(forKey: "floatube.showLastPlayed") == nil ? true : UserDefaults.standard.bool(forKey: "floatube.showLastPlayed")
    }

    private var lastPlayedId: String? {
        guard showLastPlayed else { return nil }
        let id = UserDefaults.standard.string(forKey: "floatube.lastVideoId") ?? ""
        return id.isEmpty ? nil : id
    }

    @ViewBuilder
    private var lastPlayedView: some View {
        if let videoId = lastPlayedId,
           let title = UserDefaults.standard.string(forKey: "floatube.lastVideoTitle") {
            let time = UserDefaults.standard.double(forKey: "floatube.lastVideoTime")
            let duration = UserDefaults.standard.double(forKey: "floatube.lastVideoDuration")
            let progress = duration > 0 ? time / duration : 0

            VStack(alignment: .leading, spacing: 0) {
                Text("Last Played")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                Button {
                    onDetachVideo(videoId, title, time)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.white)
                        Text(title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 24, height: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Resume Playback")

                Divider()
            }
        }
    }

    private func inlinePlayerView(videoId: String, player: YouTubePlayer) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    playingVideoId = nil
                    playingVideoTitle = ""
                    youtubePlayer = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Back")

                Spacer()

                Button {
                    addToPlaylistFromInline(videoId: videoId)
                } label: {
                    Image(systemName: "text.badge.plus")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add to Playlist")

                Button {
                    Task {
                        let seconds = (try? await player.getCurrentTime())?.converted(to: .seconds).value ?? 0
                        let title = playingVideoTitle
                        playingVideoId = nil
                        youtubePlayer = nil
                        DispatchQueue.main.async {
                            onDetachVideo(videoId, title, seconds)
                        }
                    }
                } label: {
                    Image(systemName: "pip")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Detach Player")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            VideoPlayerView(player: player)
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if searchHistory.queries.isEmpty && lastPlayedId == nil {
            Spacer()
            VStack(spacing: 8) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .frame(width: 64, height: 64)
                    .opacity(0.5)
                Text("Search for YouTube videos")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    lastPlayedView

                    if !searchHistory.queries.isEmpty {
                        Text("Recent Searches")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.top, 14)
                            .padding(.bottom, 8)

                        ForEach(searchHistory.queries, id: \.self) { query in
                            Button {
                                searchText = query
                                performSearch()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock")
                                        .foregroundStyle(.secondary)
                                    Text(query)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .font(.body)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading, 46)
                        }

                        Button {
                            searchHistory.clear()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Clear History")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Clear Search History")
                    }
                }
            }
        }
    }

    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(youtubeService.results) { item in
                    ResultRowView(item: item) {
                        playVideo(id: item.id, title: item.title)
                    }
                    Divider()
                }

                if youtubeService.nextPageToken != nil {
                    Button("Load More") {
                        Task {
                            await youtubeService.search(
                                query: searchText,
                                pageToken: youtubeService.nextPageToken,
                                videoCategoryId: musicCategoryId
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .padding()
                    .help("Load More Results")
                }

                if youtubeService.isLoading {
                    ProgressView()
                        .padding()
                }
            }
        }
    }

    private var musicCategoryId: String? {
        isMusicMode ? "10" : nil
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        hasSearched = true
        searchHistory.add(query)
        Task {
            await youtubeService.search(query: query, videoCategoryId: musicCategoryId)
        }
    }

    private func playVideo(id: String, title: String) {
        if hasDetachedPlayer {
            onDetachVideo(id, title, 0)
        } else if isInlineMode {
            PlayerWindow.pauseSystemMedia()
            youtubePlayer = makePlayer(videoId: id)
            playingVideoTitle = title
            playingVideoId = id
        } else {
            onDetachVideo(id, title, 0)
        }
    }

    private func addToPlaylistFromInline(videoId: String) {
        let item = PlaylistItem(
            videoId: videoId,
            title: playingVideoTitle,
            channelTitle: "",
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg")
        )
        if playlistStore.playlists.count == 1, let playlist = playlistStore.playlists.first {
            playlistStore.addItem(item, to: playlist.id)
        } else {
            let handler = PlaylistMenuHandler(store: playlistStore, item: item)
            let menu = NSMenu()
            for playlist in playlistStore.playlists {
                let menuItem = NSMenuItem(title: playlist.name, action: #selector(PlaylistMenuHandler.addItem(_:)), keyEquivalent: "")
                menuItem.target = handler
                menuItem.representedObject = playlist.id
                menu.addItem(menuItem)
            }
            objc_setAssociatedObject(menu, "handler", handler, .OBJC_ASSOCIATION_RETAIN)
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func showPlaylistMoreMenu() {
        let handler = PlaylistActionHandler(
            onRename: {
                renamePlaylistName = currentPlaylistActualName
                isRenamingPlaylist = true
            },
            onDelete: {
                isDeletingPlaylist = true
            }
        )
        let menu = NSMenu()

        let renameItem = NSMenuItem(title: "Rename", action: #selector(PlaylistActionHandler.renamePlaylist(_:)), keyEquivalent: "")
        renameItem.target = handler
        renameItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        menu.addItem(renameItem)

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(PlaylistActionHandler.deletePlaylist(_:)), keyEquivalent: "")
        deleteItem.target = handler
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(deleteItem)

        objc_setAssociatedObject(menu, "playlistActionHandler", handler, .OBJC_ASSOCIATION_RETAIN)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func commitRenamePlaylist() {
        let name = renamePlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, let id = currentPlaylistId {
            playlistStore.renamePlaylist(id: id, name: name)
        }
        renamePlaylistName = ""
        isRenamingPlaylist = false
    }

    private func commitNewPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            playlistStore.addPlaylist(name: name)
        }
        newPlaylistName = ""
        isAddingPlaylist = false
    }

    private func postPlaylistQueue(items: [PlaylistItem], currentVideoId: String) {
        let queue = items.map { ["videoId": $0.videoId, "title": $0.title] }
        NotificationCenter.default.post(
            name: .floatubeSetPlaylistQueue,
            object: nil,
            userInfo: ["queue": queue, "currentVideoId": currentVideoId]
        )
    }

    private func makePlayer(videoId: String, startTime: Double = 0) -> YouTubePlayer {
        let player = YouTubePlayer(
            source: .video(id: videoId),
            parameters: .init(
                autoPlay: true,
                startTime: startTime > 1 ? .init(value: startTime, unit: .seconds) : nil,
                showFullscreenButton: false
            ),
            configuration: .init(
                fullscreenMode: .system
            )
        )
        Task {
            for _ in 0..<30 {
                if player.state == .ready {
                    try? await player.play()
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        return player
    }
}

private class PlaylistActionHandler: NSObject {
    let onRename: () -> Void
    let onDelete: () -> Void

    init(onRename: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.onRename = onRename
        self.onDelete = onDelete
    }

    @objc func renamePlaylist(_ sender: NSMenuItem) { onRename() }
    @objc func deletePlaylist(_ sender: NSMenuItem) { onDelete() }
}

private class PlaylistMenuHandler: NSObject {
    let store: PlaylistStore
    let item: PlaylistItem

    init(store: PlaylistStore, item: PlaylistItem) {
        self.store = store
        self.item = item
    }

    @objc func addItem(_ sender: NSMenuItem) {
        guard let playlistId = sender.representedObject as? UUID else { return }
        store.addItem(item, to: playlistId)
    }
}
