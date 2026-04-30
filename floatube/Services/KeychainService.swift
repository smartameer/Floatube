import Foundation
import Security

enum KeychainService {
    private static let service = "floatubeApiKeys"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func loadAPIKeys() -> [String] {
        guard let json = load(key: "youtubeAPIKeys"),
              let data = json.data(using: .utf8),
              let keys = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return keys
    }

    static func saveAPIKeys(_ keys: [String]) {
        guard let data = try? JSONEncoder().encode(keys),
              let json = String(data: data, encoding: .utf8) else { return }
        save(key: "youtubeAPIKeys", value: json)
    }

    static func addAPIKey(_ key: String) {
        var keys = loadAPIKeys()
        guard !keys.contains(key) else { return }
        keys.append(key)
        saveAPIKeys(keys)
    }

    static func removeAPIKey(at index: Int) {
        var keys = loadAPIKeys()
        guard index < keys.count else { return }
        keys.remove(at: index)
        saveAPIKeys(keys)
    }
}
