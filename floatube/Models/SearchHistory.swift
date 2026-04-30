import Foundation

@Observable
class SearchHistory {
    private static let storageKey = "floatube.searchHistory"
    private static let maxItems = 50

    var queries: [String]

    init() {
        queries = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
    }

    func add(_ query: String) {
        queries.removeAll { $0 == query }
        queries.insert(query, at: 0)
        if queries.count > Self.maxItems {
            queries = Array(queries.prefix(Self.maxItems))
        }
        save()
    }

    func clear() {
        queries.removeAll()
        save()
    }

    private func save() {
        UserDefaults.standard.set(queries, forKey: Self.storageKey)
    }
}
