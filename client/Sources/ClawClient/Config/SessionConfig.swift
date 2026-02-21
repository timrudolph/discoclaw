import Foundation
import Security

/// Persists the server URL + auth token for the current device.
/// Stored in the Keychain (kSecClassGenericPassword) for security.
/// Migrates automatically from the legacy UserDefaults storage on first access.
public struct SessionConfig: Codable, Sendable {
    public var serverURL: URL
    public var token: String
    public var userId: String
    public var deviceId: String

    public init(serverURL: URL, token: String, userId: String, deviceId: String) {
        self.serverURL = serverURL
        self.token = token
        self.userId = userId
        self.deviceId = deviceId
    }
}

extension SessionConfig {
    private static let service = "app.discoclaw.client"
    private static let account = "session"
    private static let legacyKey = "clawclient.session"

    // MARK: - Public API

    public static func load() -> SessionConfig? {
        // Try Keychain first; migrate from UserDefaults if found there.
        if let data = keychainLoad() {
            return try? JSONDecoder().decode(SessionConfig.self, from: data)
        }
        // Legacy migration: move UserDefaults → Keychain, then delete from UserDefaults.
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let session = try? JSONDecoder().decode(SessionConfig.self, from: data) {
            session.save()
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return session
        }
        return nil
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        keychainSave(data: data)
    }

    public static func clear() {
        keychainDelete()
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    // MARK: - Keychain helpers

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func keychainLoad() -> Data? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private func keychainSave(data: Data) {
        var query = Self.keychainQuery()
        // Try update first; add if the item doesn't exist yet.
        let updateAttribs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttribs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private static func keychainDelete() {
        SecItemDelete(keychainQuery() as CFDictionary)
    }
}
