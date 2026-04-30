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
                let items = searchResponse.items.map { item in
                    YouTubeItem(
                        id: item.id.videoId,
                        title: item.snippet.title.decodingHTMLEntities(),
                        channelTitle: item.snippet.channelTitle,
                        thumbnailURL: URL(string: item.snippet.thumbnails.medium.url),
                        publishedAt: dateFormatter.date(from: item.snippet.publishedAt)
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

// MARK: - API Error Models

private struct YouTubeAPIError: Codable {
    let error: YouTubeAPIErrorDetail
}

private struct YouTubeAPIErrorDetail: Codable {
    let code: Int
    let message: String
}
