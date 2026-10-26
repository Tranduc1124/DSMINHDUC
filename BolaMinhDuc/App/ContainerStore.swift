import Foundation
import UIKit
import Darwin

/// One app installed on the device (Astra-style "Container" list).
struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let container: String?

    var id: String { bundleID }
    var hasContainer: Bool { container != nil }
}

/// Resolve + enumerate app data containers.
///
/// Order (same as Astra):
///   1. MobileHouseArrest  -> container + sandbox extension (identity trust)
///   2. LSApplicationWorkspace / MobileInstallation  (listing only)
///   3. MCM metadata plist scan under
///      /var/mobile/Containers/Data/Application/<UUID>/
///      .com.apple.mobile_container_manager.metadata.plist -> MCMMetadataIdentifier
///
/// Nothing here injects code: we only read/write files inside another app's
/// data container, exactly like the game's own hot-update pipeline does.
enum ContainerStore {
    static let appsRoot = "/var/mobile/Containers/Data/Application"

    // MARK: - LaunchServices

    private static func loadLaunchServices() {
        if NSClassFromString("LSApplicationWorkspace") != nil { return }
        let paths = [
            "/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices",
            "/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices"
        ]
        for p in paths { _ = dlopen(p, RTLD_NOW) }
    }

    private static func workspace() -> NSObject? {
        loadLaunchServices()
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              let ws = cls.perform(NSSelectorFromString("defaultWorkspace"))?
                .takeUnretainedValue() as? NSObject
        else { return nil }
        return ws
    }

    private static func call(_ target: NSObject, _ name: String) -> AnyObject? {
        let sel = NSSelectorFromString(name)
        guard target.responds(to: sel) else { return nil }
        return target.perform(sel)?.takeUnretainedValue()
    }

    private static func str(_ target: NSObject, _ name: String) -> String? {
        if let s = call(target, name) as? String { return s }
        if let s = call(target, name) as? NSString { return s as String }
        return nil
    }

    // MARK: - listing

    static func installedApps() -> [InstalledApp] {
        var out: [InstalledApp] = []
        var seen = Set<String>()

        if let ws = workspace() {
            for listName in ["allInstalledApplications", "allApplications"] {
                guard let list = call(ws, listName) as? [NSObject] else { continue }
                for app in list {
                    let bid = str(app, "bundleIdentifier")
                        ?? str(app, "applicationIdentifier")
                        ?? ""
                    if bid.isEmpty || seen.contains(bid) { continue }
                    seen.insert(bid)

                    let name = str(app, "localizedName")
                        ?? str(app, "localizedShortName")
                        ?? bid

                    var container: String?
                    if let u = call(app, "dataContainerURL") as? URL { container = u.path }
                    if container == nil, let u = call(app, "containerURL") as? URL { container = u.path }

                    out.append(InstalledApp(bundleID: bid, name: name, container: container))
                }
                if !out.isEmpty { break }
            }
        }

        if out.isEmpty { out = metadataScan() }

        return out.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// MCM class-2 enumeration: works without LaunchServices / with only the
    /// sandbox escape active.
    static func metadataScan() -> [InstalledApp] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: appsRoot) else { return [] }
        var out: [InstalledApp] = []
        for entry in entries {
            let dir = appsRoot + "/" + entry
            guard let id = readBundleID(inContainer: dir), !id.isEmpty else { continue }
            out.append(InstalledApp(bundleID: id, name: id, container: dir))
        }
        return out
    }

    private static func readBundleID(inContainer dir: String) -> String? {
        let meta = dir + "/.com.apple.mobile_container_manager.metadata.plist"
        guard let data = FileManager.default.contents(atPath: meta),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist["MCMMetadataIdentifier"] as? String
    }

    // MARK: - resolve

    /// Data container path for a bundle identifier, or nil.
    /// MobileHouseArrest is tried first: it also activates the sandbox
    /// extension that grants read/write for the rest of the process lifetime.
    static func containerPath(for bundleID: String) -> String? {
        guard !bundleID.isEmpty else { return nil }

        if let p = mha_path_for_bundle(bundleID) {
            let s = String(cString: p)
            if !s.isEmpty { return s }
        }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: appsRoot) else { return nil }
        for entry in entries {
            let dir = appsRoot + "/" + entry
            if readBundleID(inContainer: dir) == bundleID { return dir }
        }
        return nil
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        if containerPath(for: bundleID) != nil { return true }
        return installedApps().contains { $0.bundleID == bundleID }
    }

    /// Real write test (create + delete a probe). No guessing.
    static func canWrite(container: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: container) else { return false }
        let probe = (container as NSString)
            .appendingPathComponent(".patchprobe-\(UUID().uuidString.prefix(8))")
        do {
            try Data("probe".utf8).write(to: URL(fileURLWithPath: probe), options: .atomic)
            try? fm.removeItem(atPath: probe)
            return true
        } catch {
            return false
        }
    }

    /// First foreign container we can actually write to (for the dashboard
    /// "sandbox access" check).
    static func firstWritableForeignContainer() -> String? {
        let own = Bundle.main.bundleIdentifier ?? ""
        for app in installedApps() where app.bundleID != own {
            if let c = app.container, canWrite(container: c) { return c }
        }
        return nil
    }

    // MARK: - path safety (Astra rules)

    /// Relative path inside the app's Data container. Rejects absolute paths,
    /// `..`, `.`, `~` and empty components.
    static func safeRelativePath(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("/") { s.removeFirst() }
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        for p in parts {
            let c = String(p)
            if c.isEmpty || c == "." || c == ".." || c.hasPrefix("~") { return nil }
        }
        return s
    }

    /// Joined + verified absolute target. nil when the path escapes the
    /// container or walks through a symlink.
    static func targetPath(container: String, relative: String) -> String? {
        guard let rel = safeRelativePath(relative) else { return nil }
        let target = ((container as NSString).appendingPathComponent(rel) as NSString).standardizingPath
        let base = (container as NSString).standardizingPath
        guard target == base || target.hasPrefix(base + "/") else { return nil }
        if walksThroughSymlink(base: base, target: target) { return nil }
        return target
    }

    private static func walksThroughSymlink(base: String, target: String) -> Bool {
        let fm = FileManager.default
        var cur = base
        let rel = target.hasPrefix(base) ? String(target.dropFirst(base.count)) : ""
        for comp in rel.split(separator: "/") {
            cur = (cur as NSString).appendingPathComponent(String(comp))
            guard let attrs = try? fm.attributesOfItem(atPath: cur) else { return false }
            if (attrs[.type] as? FileAttributeType) == .typeSymbolicLink { return true }
        }
        return false
    }
}
