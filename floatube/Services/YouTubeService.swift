import Foundation

@Observable
class YouTubeService {
    var results: [YouTubeItem] = []
    var isLoading = false
    var errorMessage: String?
    var nextPageToken: String?

    private var apiKeys: [String] {
        KeychainService.loadAPIKeys()
    }

    func search(query: String, pageToken: String? = nil, videoCategoryId: String? = nil) async {
        let keys = apiKeys
        guard !keys.isEmpty else {
            errorMessage = "No API keys configured. Open Settings to add one."
            return
        }

        isLoading = true
        errorMessage = nil

        for (index, key) in keys.enumerated() {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
            components.queryItems = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "video"),
                URLQueryItem(name: "maxResults", value: "20"),
                URLQueryItem(name: "key", value: key)
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            if let videoCategoryId {
                components.queryItems?.append(URLQueryItem(name: "videoCategoryId", value: videoCategoryId))
            }

            guard let url = components.url else { continue }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    let isLastKey = index == keys.count - 1
                    let shouldRetry = (httpResponse.statusCode == 403 || httpResponse.statusCode == 429) && !isLastKey

                    if shouldRetry { continue }

                    if let apiError = try? JSONDecoder().decode(YouTubeAPIError.self, from: data) {
                        errorMessage = apiError.error.message
                    } else {
                        errorMessage = "YouTube API returned status \(httpResponse.statusCode)"
                    }
                    isLoading = false
                    return
                }

                let searchResponse = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)

                let dateFormatter = ISO8601DateFormatter()
                var items = searchResponse.items.map { item in
                    YouTubeItem(
                        id: item.id.videoId,
                        title: item.snippet.title.decodingHTMLEntities(),
                        channelTitle: item.snippet.channelTitle,
                        thumbnailURL: URL(string: item.snippet.thumbnails.medium.url),
                        publishedAt: dateFormatter.date(from: item.snippet.publishedAt),
                        duration: nil
                    )
                }

                let durations = await fetchDurations(videoIds: items.map(\.id), apiKey: key)
                items = items.map { item in
                    YouTubeItem(
                        id: item.id, title: item.title, channelTitle: item.channelTitle,
                        thumbnailURL: item.thumbnailURL, publishedAt: item.publishedAt,
                        duration: durations[item.id]
                    )
                }

                if pageToken != nil {
                    results.append(contentsOf: items)
                } else {
                    results = items
                }
                nextPageToken = searchResponse.nextPageToken
                isLoading = false
                return
            } catch {
                if index == keys.count - 1 {
                    errorMessage = error.localizedDescription
                }
            }
        }

        isLoading = false
    }

    // MARK: - Duration helpers

    private func fetchDurations(videoIds: [String], apiKey: String) async -> [String: String] {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails"),
            URLQueryItem(name: "id", value: videoIds.joined(separator: ",")),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(YouTubeVideosResponse.self, from: data) else {
            return [:]
        }
        var result: [String: String] = [:]
        for item in response.items {
            if let d = Self.parseDuration(item.contentDetails.duration) {
                result[item.id] = d
            }
        }
        return result
    }

    static func parseDuration(_ iso: String) -> String? {
        guard iso.hasPrefix("PT") else { return nil }
        var s = String(iso.dropFirst(2))
        var hours = 0, minutes = 0, seconds = 0
        if let r = s.range(of: "H") {
            hours = Int(s[s.startIndex..<r.lowerBound]) ?? 0
            s = String(s[r.upperBound...])
        }
        if let r = s.range(of: "M") {
            minutes = Int(s[s.startIndex..<r.lowerBound]) ?? 0
            s = String(s[r.upperBound...])
        }
        if let r = s.range(of: "S") {
            seconds = Int(s[s.startIndex..<r.lowerBound]) ?? 0
        }
        guard hours + minutes + seconds > 0 else { return nil }
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

private extension String {
    func decodingHTMLEntities() -> String {
        var result = self
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
    }
}

// MARK: - API Response Models

private struct YouTubeSearchResponse: Codable {
    let items: [YouTubeSearchItem]
    let nextPageToken: String?
}

private struct YouTubeSearchItem: Codable {
    let id: YouTubeVideoId
    let snippet: YouTubeSnippet
}

private struct YouTubeVideoId: Codable {
    let videoId: String
}

private struct YouTubeSnippet: Codable {
    let title: String
    let channelTitle: String
    let thumbnails: YouTubeThumbnails
    let publishedAt: String
}

private struct YouTubeThumbnails: Codable {
    let medium: YouTubeThumbnail
}

private struct YouTubeThumbnail: Codable {
    let url: String
}

private struct YouTubeVideosResponse: Codable {
    let items: [YouTubeVideoDetail]
}

private struct YouTubeVideoDetail: Codable {
    let id: String
    let contentDetails: YouTubeContentDetails
}

private struct YouTubeContentDetails: Codable {
    let duration: String
}

// MARK: - API Error Models

private struct YouTubeAPIError: Codable {
    let error: YouTubeAPIErrorDetail
}

private struct YouTubeAPIErrorDetail: Codable {
    let code: Int
    let message: String
}
