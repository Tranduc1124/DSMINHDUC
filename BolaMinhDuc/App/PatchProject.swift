import Foundation

/// Lifecycle of a patch project (mirrors Astra's transaction states).
enum PatchStatus: String, Codable {
    case prepared
    case applied
    case restored
    case failed

    var title: String {
        switch self {
        case .prepared: return "Sẵn sàng"
        case .applied: return "Đang áp dụng"
        case .restored: return "Đã khôi phục"
        case .failed: return "Lỗi"
        }
    }
}

/// One file replacement:
///   target = <data container of bundleID>/<relativePath>
/// Astra never stores a container UUID, only the bundle identifier.
struct PatchRule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var bundleID: String
    var relativePath: String
    var fileName: String      // stored copy inside the project folder
    var sha256: String
    var size: Int
}

/// A patch project: a named set of rules applied atomically.
struct PatchProject: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var author: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var rules: [PatchRule] = []
    var status: PatchStatus = .prepared
    var appliedAt: Date?

    /// Distinct bundle identifiers, in rule order.
    var bundles: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in rules where !seen.contains(r.bundleID) {
            seen.insert(r.bundleID)
            out.append(r.bundleID)
        }
        return out
    }

    var totalBytes: Int {
        rules.reduce(0) { $0 + $1.size }
    }
}

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
