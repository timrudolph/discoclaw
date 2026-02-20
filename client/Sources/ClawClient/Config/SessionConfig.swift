import Foundation

/// Persists the server URL + auth token for the current device.
/// Stored in UserDefaults — not in the Keychain for simplicity, since this is
/// a personal tool on a trusted device. Move to Keychain later if needed.
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
    private static let key = "clawclient.session"

    public static func load() -> SessionConfig? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SessionConfig.self, from: data)
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: SessionConfig.key)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
