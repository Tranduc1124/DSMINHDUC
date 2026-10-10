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

    /// Best patch available: a personalised OTA download for the CURRENT key
    /// (server attaches sha256(key) trailer). The bundled/GitHub copies have no
    /// trailer, so they are never injected — the patch gate would keep them off
    /// anyway, and failing early gives a clear message.
    static func latest() -> PatchFile? {
        let license = LicenseGate.shared.licenseKey
        let cache = remoteCacheURL
        let fm = FileManager.default
        if !license.isEmpty,
           let attrs = try? fm.attributesOfItem(atPath: cache.path),
           let size = attrs[.size] as? Int, size > 4096,
           hasValidTrailer(cache, license: license) {
            return PatchFile(url: cache,
                             name: "BolaminhducMenu-OTA",
                             size: size,
                             bundled: false)
        }
        return nil
    }

    /// Checks the 64-byte personalisation trailer: "|BOLATK1|" + sha256(key)[0:16]
    static func hasValidTrailer(_ url: URL, license: String) -> Bool {
        guard let data = try? Data(contentsOf: url), data.count > 128, !license.isEmpty else { return false }
        let tail = data.suffix(64)
        guard let s = String(data: tail, encoding: .utf8), s.hasPrefix("|BOLATK1|") else { return false }
        let parts = s.split(separator: "|", omittingEmptySubsequences: false)
        // ["", "BOLATK1", licHash, exp, "0000…"]
        guard parts.count >= 4 else { return false }
        let licHash = PatchClient.sha256(Data(license.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
        guard String(parts[2]) == String(licHash) else { return false }
        let exp = TimeInterval(parts[3]) ?? 0
        return exp > Date().timeIntervalSince1970
    }

    /// Silent refresh, two sources:
    /// 1) the licensed server (ds.tphat.store) — encrypted per license+device;
    /// 2) the public GitHub mirror — plain bytes (kept as a fallback so the
    ///    app keeps updating even if the server is unreachable).
    /// `completion` gets the downloaded size (0 on any failure).
    static func refreshRemote(completion: @escaping (Int) -> Void) {
        let license = LicenseGate.shared.licenseKey
        if !license.isEmpty {
            PatchClient.refreshPatch(license: license, device: ServerConfig.deviceId) { ok in
                let size = (try? FileManager.default
                    .attributesOfItem(atPath: remoteCacheURL.path)[.size] as? Int) ?? 0
                if ok, size > 4096 {
                    DispatchQueue.main.async { completion(size) }
                } else {
                    refreshFromGitHub(completion: completion)
                }
            }
            return
        }
        refreshFromGitHub(completion: completion)
    }

    private static func refreshFromGitHub(completion: @escaping (Int) -> Void) {
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
            // IMPORTANT: KHÔNG ghi đè remote_patch.bytes (patch cá nhân hoá từ
            // server). Bản GitHub không có trailer — ghi đè nó từng làm mọi
            // lần INJECT bị chặn ("Patch chưa sẵn sàng") khi server fetch lỗi.
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dest = docs.appendingPathComponent("github_patch.bin")
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
