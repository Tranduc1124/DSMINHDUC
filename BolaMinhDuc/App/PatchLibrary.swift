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

    // MARK: - OTA patch (downloaded from the public repo)

    /// Raw bytes in the GitHub repo — updated by CI on every patch change, so
    /// the app can pick up new patches without reinstalling the IPA.
    static let remoteURL = URL(string:
        "https://raw.githubusercontent.com/Tranduc1124/DSMINHDUC/main/BolaMinhDuc/Patches/BolaminhducMenu.bytes")!

    /// Where the downloaded patch is cached (inside our own container).
    static var remoteCacheURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("remote_patch.bytes")
    }

    /// Best patch available: downloaded OTA bytes first, bundled as fallback.
    static func latest() -> PatchFile? {
        let cache = remoteCacheURL
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: cache.path),
           let size = attrs[.size] as? Int, size > 4096 {
            return PatchFile(url: cache,
                             name: "BolaminhducMenu-OTA",
                             size: size,
                             bundled: false)
        }
        return bundled()
    }

    /// Silent refresh: downloads the newest bytes into the cache.
    /// `completion` gets the downloaded size (0 on any failure).
    static func refreshRemote(completion: @escaping (Int) -> Void) {
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // cache-buster so a fresh push is picked up immediately
        request.url = URL(string: remoteURL.absoluteString
            + "?v=" + String(Int(Date().timeIntervalSince1970)))
        let task = URLSession.shared.downloadTask(with: request) { tmp, response, error in
            guard let tmp = tmp,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = try? Data(contentsOf: tmp), data.count > 4096 else {
                DispatchQueue.main.async { completion(0) }
                return
            }
            let dest = remoteCacheURL
            try? FileManager.default.removeItem(at: dest)
            do {
                try data.write(to: dest, options: .atomic)
                DispatchQueue.main.async { completion(data.count) }
            } catch {
                DispatchQueue.main.async { completion(0) }
            }
        }
        task.resume()
    }
}
