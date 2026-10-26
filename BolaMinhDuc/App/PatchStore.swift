import Foundation
import Combine

/// Local patch library (Astra's "Patch" tab).
///
/// Layout inside the app sandbox:
///   Documents/PatchProjects/<uuid>/project.json
///   Documents/PatchProjects/<uuid>/files/<stored-name>     replacement bytes
///   Documents/PatchProjects/<uuid>/backup/<rule>.bak       original file
///   Documents/PatchProjects/<uuid>/backup/<rule>.existed   "1" / "0"
///
/// Nothing here talks to the proxy: a project is fully self-contained, so the
/// game keeps working when the mitm server is gone.
final class PatchStore: ObservableObject {
    static let shared = PatchStore()

    @Published private(set) var projects: [PatchProject] = []

    private let fm = FileManager.default

    var root: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("PatchProjects", isDirectory: true)
    }

    private init() {
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
        seedBundledIfNeeded()
    }

    // MARK: - paths

    func dir(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func filesDir(_ id: UUID) -> URL { dir(id).appendingPathComponent("files", isDirectory: true) }
    func backupDir(_ id: UUID) -> URL { dir(id).appendingPathComponent("backup", isDirectory: true) }
    func projectFile(_ id: UUID) -> URL { dir(id).appendingPathComponent("project.json") }

    func replacementURL(_ project: PatchProject, _ rule: PatchRule) -> URL {
        filesDir(project.id).appendingPathComponent(rule.fileName)
    }
    func backupURL(_ project: PatchProject, _ rule: PatchRule) -> URL {
        backupDir(project.id).appendingPathComponent(rule.id.uuidString + ".bak")
    }
    func existedURL(_ project: PatchProject, _ rule: PatchRule) -> URL {
        backupDir(project.id).appendingPathComponent(rule.id.uuidString + ".existed")
    }

    // MARK: - load / save

    func reload() {
        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else {
            projects = []
            return
        }
        var out: [PatchProject] = []
        for d in entries {
            let f = d.appendingPathComponent("project.json")
            guard let data = fm.contents(atPath: f.path),
                  let p = try? JSONDecoder().decode(PatchProject.self, from: data)
            else { continue }
            out.append(p)
        }
        projects = out.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ project: PatchProject) {
        var p = project
        p.updatedAt = Date()

        // Disk write is thread-safe and happens on the caller thread so a
        // reload() right after (e.g. from PatchInstaller) sees the new data.
        try? fm.createDirectory(at: dir(p.id), withIntermediateDirectories: true)
        try? fm.createDirectory(at: filesDir(p.id), withIntermediateDirectories: true)
        try? fm.createDirectory(at: backupDir(p.id), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(p) {
            try? data.write(to: projectFile(p.id), options: .atomic)
        }

        // @Published mutation must be on the main thread.
        let publish = {
            if let i = self.projects.firstIndex(where: { $0.id == p.id }) {
                self.projects[i] = p
            } else {
                self.projects.insert(p, at: 0)
            }
        }
        if Thread.isMainThread {
            publish()
        } else {
            DispatchQueue.main.async(execute: publish)
        }
    }

    func delete(_ project: PatchProject) {
        try? fm.removeItem(at: dir(project.id))
        projects.removeAll { $0.id == project.id }
    }

    // MARK: - create

    /// Copies every source file into the project and builds the rules in one
    /// pass (avoids the stale-copy problem of incremental edits).
    func createProject(name: String,
                       author: String,
                       entries: [(bundleID: String, relativePath: String, source: URL)]) -> PatchProject? {
        var p = PatchProject(name: name, author: author)
        try? fm.createDirectory(at: filesDir(p.id), withIntermediateDirectories: true)

        for e in entries {
            guard let rel = ContainerStore.safeRelativePath(e.relativePath) else { continue }
            guard let data = readSource(e.source), !data.isEmpty else { continue }
            let stored = p.id.uuidString + "-" + e.source.lastPathComponent
            let dest = filesDir(p.id).appendingPathComponent(stored)
            guard (try? data.write(to: dest, options: .atomic)) != nil else { continue }
            p.rules.removeAll { $0.bundleID == e.bundleID && $0.relativePath == rel }
            p.rules.append(PatchRule(bundleID: e.bundleID,
                                     relativePath: rel,
                                     fileName: stored,
                                     sha256: Self.sha256(data),
                                     size: data.count))
        }

        guard !p.rules.isEmpty else { return nil }
        save(p)
        return p
    }

    /// Adds or replaces one rule on an existing project.
    @discardableResult
    func addRule(to project: PatchProject,
                 bundleID: String,
                 relativePath: String,
                 source: URL) -> String? {
        guard let rel = ContainerStore.safeRelativePath(relativePath) else {
            return "Đường dẫn phải tương đối (vd Documents/file.bytes), không dùng .."
        }
        guard let data = readSource(source), !data.isEmpty else {
            return "Không đọc được file thay thế"
        }
        var p = project
        try? fm.createDirectory(at: filesDir(p.id), withIntermediateDirectories: true)
        let stored = p.id.uuidString + "-" + source.lastPathComponent
        let dest = filesDir(p.id).appendingPathComponent(stored)
        guard (try? data.write(to: dest, options: .atomic)) != nil else {
            return "Không ghi được file vào thư mục patch"
        }
        p.rules.removeAll { $0.bundleID == bundleID && $0.relativePath == rel }
        p.rules.append(PatchRule(bundleID: bundleID,
                                 relativePath: rel,
                                 fileName: stored,
                                 sha256: Self.sha256(data),
                                 size: data.count))
        p.status = .prepared
        save(p)
        return nil
    }

    func removeRule(from project: PatchProject, rule: PatchRule) {
        var p = project
        p.rules.removeAll { $0.id == rule.id }
        try? fm.removeItem(at: replacementURL(project, rule))
        try? fm.removeItem(at: backupURL(project, rule))
        try? fm.removeItem(at: existedURL(project, rule))
        save(p)
    }

    // MARK: - bundled seed (works with no server at all)

    /// First launch: build a ready-to-apply project from the patch shipped in
    /// the IPA (`BolaminhducMenu.bytes` + `localConfig.json`).
    func seedBundledIfNeeded() {
        guard projects.isEmpty else { return }
        guard let patch = PatchLibrary.bundled() else { return }

        var entries: [(bundleID: String, relativePath: String, source: URL)] = []
        let cfg = Bundle.main.url(forResource: "localConfig", withExtension: "json")
        for game in GameTarget.allCases {
            entries.append((bundleID: game.rawValue,
                            relativePath: "Documents/Assembly-CSharp-patch.bytes",
                            source: patch.url))
            if let cfg = cfg {
                entries.append((bundleID: game.rawValue,
                                relativePath: "Documents/localConfig.json",
                                source: cfg))
            }
        }
        _ = createProject(name: "MinDo Patch", author: "MinDo", entries: entries)
    }

    // MARK: - helpers

    /// Reads a user-picked URL with the right security scope.
    private func readSource(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    static func sha256(_ data: Data) -> String {
        PatchClient.sha256(data).map { String(format: "%02x", $0) }.joined()
    }
}
