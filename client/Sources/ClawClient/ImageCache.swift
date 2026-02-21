import Foundation

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#else
import AppKit
public typealias PlatformImage = NSImage
#endif

/// Thread-safe in-memory image cache.
/// Keys: "user" for the user avatar, "conv-{conversationId}" for assistant avatars.
public actor ImageCache {
    public static let shared = ImageCache()

    private let cache = NSCache<NSString, PlatformImage>()

    private init() {
        cache.countLimit = 50
    }

    public func get(_ key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)
    }

    public func set(_ image: PlatformImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    public func remove(_ key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}
