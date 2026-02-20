import Foundation

/// UserDefaults-backed sync cursor. Stores the last `seq` value seen from the server.
/// The client passes this as `since=<value>` on every sync call and WebSocket reconnect.
public enum SyncCursor {
    private static let key = "clawclient.sync.cursor"

    public static var value: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Advance the cursor only if the new value is higher (never go backwards).
    public static func advance(to seq: Int) {
        if seq > value { value = seq }
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
