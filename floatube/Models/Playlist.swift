import Foundation
import SwiftUI

struct PlaylistItem: Identifiable, Codable, Hashable {
    let id: UUID
    let videoId: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?
    let addedAt: Date

    init(videoId: String, title: String, channelTitle: String, thumbnailURL: URL?) {
        self.id = UUID()
        self.videoId = videoId
        self.title = title
        self.channelTitle = channelTitle
        self.thumbnailURL = thumbnailURL
        self.addedAt = Date()
    }
}

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var items: [PlaylistItem]

    init(name: String, items: [PlaylistItem] = []) {
        self.id = UUID()
        self.name = name
        self.items = items
    }
}

@Observable
class PlaylistStore {
    private(set) var playlists: [Playlist] = []
    private let key = "floatube.playlists"
    private var observer: NSObjectProtocol?

    init() {
        load()
        observer = NotificationCenter.default.addObserver(
            forName: .floatubePlaylistChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func reload() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
    }

    var canAddPlaylist: Bool {
        playlists.count < 20
    }

    func addPlaylist(name: String) {
        guard canAddPlaylist else { return }
        let playlist = Playlist(name: name)
        playlists.append(playlist)
        save()
    }

    func removePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func renamePlaylist(id: UUID, name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = name
        save()
    }

    func addItem(_ item: PlaylistItem, to playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        guard !playlists[index].items.contains(where: { $0.videoId == item.videoId }) else { return }
        playlists[index].items.insert(item, at: 0)
        save()
    }

    func removeItem(id: UUID, from playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[index].items.removeAll { $0.id == id }
        save()
    }

    func removeItems(at offsets: IndexSet, from playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[index].items.remove(atOffsets: offsets)
        save()
    }

    func moveItems(from source: IndexSet, to destination: Int, in playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[index].items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: key)
            NotificationCenter.default.post(name: .floatubePlaylistChanged, object: nil)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
        if playlists.isEmpty {
            playlists = [Playlist(name: "Default")]
            save()
        }
    }
}
