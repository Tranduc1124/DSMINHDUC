import Foundation

struct PatchFile: Identifiable, Hashable {
    let url: URL
    let name: String
    let size: Int
    let bundled: Bool

    var id: String { url.path }
}

/// Patch files = the .bytes payloads. Bundled ones live in the app bundle,
/// imported ones are copied into Documents/Patches (visible in the Files app).
enum PatchLibrary {
    static var importedDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Patches", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func all() -> [PatchFile] {
        var out: [PatchFile] = []

        if let bundled = Bundle.main.urls(forResourcesWithExtension: "bytes", subdirectory: nil) {
            for url in bundled {
                out.append(make(url, bundled: true))
            }
        }

        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: importedDirectory,
                                                   includingPropertiesForKeys: nil) {
            for url in items where url.pathExtension.lowercased() == "bytes" {
                let name = url.deletingPathExtension().lastPathComponent
                if !out.contains(where: { $0.name == name }) {
                    out.append(make(url, bundled: false))
                }
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func importFile(from url: URL) throws -> PatchFile {
        let dest = importedDirectory.appendingPathComponent(url.lastPathComponent)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: url, to: dest)
        return make(dest, bundled: false)
    }

    static func delete(_ patch: PatchFile) {
        guard !patch.bundled else { return }
        try? FileManager.default.removeItem(at: patch.url)
    }

    private static func make(_ url: URL, bundled: Bool) -> PatchFile {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return PatchFile(url: url,
                         name: url.deletingPathExtension().lastPathComponent,
                         size: size,
                         bundled: bundled)
    }
}
