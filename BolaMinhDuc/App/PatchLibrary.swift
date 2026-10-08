import Foundation

struct PatchFile: Identifiable, Hashable {
    let url: URL
    let name: String
    let size: Int
    let bundled: Bool

    var id: String { url.path }
}

/// Only the patch shipped inside the app is used.
///
/// Importing extra patches was removed on purpose: opening the Files document
/// picker after the kernel sandbox escape lets another process sandbox-check
/// our corrupted state, which kernel-panics the device (observed in
/// com.apple.security.sandbox). Keep a single bundled payload.
enum PatchLibrary {
    /// The one patch bundled with the app — `BolaminhducMenu.bytes`.
    static func bundled() -> PatchFile? {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "bytes", subdirectory: nil),
              !urls.isEmpty else { return nil }
        let preferred = urls.first {
            $0.deletingPathExtension().lastPathComponent == "BolaminhducMenu"
        } ?? urls[0]
        return make(preferred)
    }

    private static func make(_ url: URL) -> PatchFile {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return PatchFile(url: url,
                         name: url.deletingPathExtension().lastPathComponent,
                         size: size,
                         bundled: true)
    }
}
