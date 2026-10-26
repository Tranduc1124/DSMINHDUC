import Foundation

/// Human label for a bundle identifier (game names first).
enum BundleLabel {
    private static var cache: [String: String] = [:]

    static func name(for bundleID: String) -> String {
        if let hit = cache[bundleID] { return hit }
        var out: String
        switch bundleID {
        case "com.dts.freefireth": out = "Free Fire"
        case "com.dts.freefiremax": out = "Free Fire MAX"
        default:
            if let app = ContainerStore.installedApps().first(where: { $0.bundleID == bundleID }) {
                out = app.name
            } else {
                out = bundleID
            }
        }
        cache[bundleID] = out
        return out
    }

    static func short(_ bundleID: String) -> String {
        let n = name(for: bundleID)
        return n == bundleID ? bundleID : n
    }

    static func resetCache() {
        cache.removeAll()
    }
}
