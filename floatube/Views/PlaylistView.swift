import SwiftUI

struct PlaylistView: View {
    var store: PlaylistStore
    @Binding var selectedPlaylistId: UUID?
    var onPlay: (String, String) -> Void
    @State private var visibleItemCount = 20

    var body: some View {
        if store.playlists.count == 1, let playlist = store.playlists.first {
            playlistItemsList(playlist: playlist)
        } else if let selectedId = selectedPlaylistId,
                  let playlist = store.playlists.first(where: { $0.id == selectedId }) {
            playlistItemsList(playlist: playlist)
        } else if store.playlists.count > 1 {
            playlistGrid
        } else {
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No playlists")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var playlistGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                ForEach(store.playlists) { playlist in
                    Button {
                        selectedPlaylistId = playlist.id
                    } label: {
                        playlistCard(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
            }
            .padding(16)
        }
    }

    private func playlistCard(playlist: Playlist) -> some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))

                if playlist.items.isEmpty {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                } else if playlist.items.count == 1 {
                    thumbnailCell(url: playlist.items[0].thumbnailURL)
                } else {
                    thumbnailCollage(items: playlist.items)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(playlist.name)
                .font(.caption)
                .lineLimit(1)
                .padding(.top, 6)
        }
    }

    private func thumbnailCollage(items: [PlaylistItem]) -> some View {
        let count = min(items.count, 4)
        let urls = items.prefix(count).map(\.thumbnailURL)
        return VStack(spacing: 1) {
            HStack(spacing: 1) {
                thumbnailCell(url: urls[0])
                if count > 1 {
                    thumbnailCell(url: urls[1])
                }
            }
            if count > 2 {
                HStack(spacing: 1) {
                    thumbnailCell(url: urls[2])
                    if count > 3 {
                        thumbnailCell(url: urls[3])
                    }
                }
            }
        }
    }

    private func thumbnailCell(url: URL?) -> some View {
        GeometryReader { geo in
            AsyncImage(url: url) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
            } placeholder: {
                Color.secondary.opacity(0.2)
            }
        }
        .clipped()
    }

    private func playlistItemsList(playlist: Playlist) -> some View {
        Group {
            if playlist.items.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No items in playlist")
                            .foregroundStyle(.secondary)
                        Text("Add videos from search results")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            } else {
                let visibleItems = Array(playlist.items.prefix(visibleItemCount))
                List {
                    ForEach(visibleItems) { item in
                        Button {
                            onPlay(item.videoId, item.title)
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: item.thumbnailURL) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.secondary.opacity(0.2)
                                }
                                .frame(width: 64, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .lineLimit(1)
                                        .font(.body)
                                    HStack(spacing: 4) {
                                        if !item.channelTitle.isEmpty {
                                            Text(item.channelTitle)
                                                .lineLimit(1)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let duration = item.duration {
                                            if !item.channelTitle.isEmpty {
                                                Text("·")
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            Text(duration)
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }

                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.removeItem(id: item.id, from: playlist.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove { source, destination in
                        store.moveItems(from: source, to: destination, in: playlist.id)
                    }

                    if playlist.items.count > visibleItemCount {
                        Button("Show More") {
                            visibleItemCount += 20
                        }
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .help("Show More Items")
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}
