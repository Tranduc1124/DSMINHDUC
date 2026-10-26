import Foundation

/// One file the product manages inside a game's Data container.
struct ManagedPath {
    let path: String
    let kind: String        // "file" | "marker"
    let exists: Bool        // server has a pristine copy
    let size: Int
    let sha256: String
    let updatedAt: Int

    var isMarker: Bool { kind == "marker" }
}

/// Server-side pristine files — Astra's "restore to original" model.
///
/// The app asks which files this product manages for a bundle, then asks for
/// the pristine bytes of each. If the server has no copy, the file did not
/// exist before the patch and must be deleted.
enum OriginalClient {

    static func manifest(bundle: String) -> [ManagedPath] {
        guard var c = URLComponents(string: ServerConfig.base + "/api/client/original/manifest") else {
            return []
        }
        c.queryItems = [
            URLQueryItem(name: "bundle", value: bundle),
            URLQueryItem(name: "device", value: ServerConfig.deviceId),
            URLQueryItem(name: "t", value: AppConfig.originalToken)
        ]
        guard let url = c.url else { return [] }

        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let sem = DispatchSemaphore(value: 0)
        var out: [ManagedPath] = []
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { sem.signal() }
            guard let data = data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (j["ok"] as? Bool) == true,
                  let arr = j["paths"] as? [[String: Any]] else { return }
            out = arr.compactMap { d in
                guard let p = d["path"] as? String,
                      let k = d["kind"] as? String else { return nil }
                return ManagedPath(path: p,
                                   kind: k,
                                   exists: (d["exists"] as? Bool) ?? false,
                                   size: (d["size"] as? Int) ?? 0,
                                   sha256: (d["sha256"] as? String) ?? "",
                                   updatedAt: (d["updatedAt"] as? Int) ?? 0)
            }
        }.resume()
        _ = sem.wait(timeout: .now() + 15)
        return out
    }

    /// Pristine bytes for one path; nil when the server has none / offline.
    static func fetch(bundle: String, path: String) -> Data? {
        guard var c = URLComponents(string: ServerConfig.base + "/api/client/original") else {
            return nil
        }
        c.queryItems = [
            URLQueryItem(name: "bundle", value: bundle),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "device", value: ServerConfig.deviceId),
            URLQueryItem(name: "t", value: AppConfig.originalToken)
        ]
        guard let url = c.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                out = data
            }
        }.resume()
        _ = sem.wait(timeout: .now() + 35)
        return out
    }

    /// Local fallback when the server is unreachable (same list as originals.js).
    static let fallbackPaths: [ManagedPath] = [
        ManagedPath(path: "Documents/Assembly-CSharp-patch.bytes", kind: "file",
                    exists: false, size: 0, sha256: "", updatedAt: 0),
        ManagedPath(path: "Documents/localConfig.json", kind: "file",
                    exists: false, size: 0, sha256: "", updatedAt: 0),
        ManagedPath(path: "Documents/bolacfg.bin", kind: "file",
                    exists: false, size: 0, sha256: "", updatedAt: 0),
        ManagedPath(path: "Documents/.bola_tok", kind: "marker",
                    exists: false, size: 0, sha256: "", updatedAt: 0),
        ManagedPath(path: "Documents/.bola_uid", kind: "marker",
                    exists: false, size: 0, sha256: "", updatedAt: 0),
        ManagedPath(path: "Documents/.bola_probe", kind: "marker",
                    exists: false, size: 0, sha256: "", updatedAt: 0)
    ]
}
