import Foundation

struct YouTubeItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?
    let publishedAt: Date?
}
