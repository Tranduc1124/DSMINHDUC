import Foundation
import UIKit

/// Client cho server patch (ds.tphat.store): kích hoạt thiết bị, kiểm tra
/// phiên bản, tải + giải mã patch (định dạng BOLAP2 do server sinh).
enum PatchClient {

    // MARK: - API

    /// Đăng ký thiết bị với server (bắt buộc trước khi tải patch mã hoá).
    static func activate(license: String, device: String, done: @escaping (Bool, String) -> Void) {
        post("/api/client/activate", ["licenseKey": license, "deviceId": device]) { j in
            done((j["ok"] as? Bool) ?? false, (j["message"] as? String) ?? "")
        }
    }

    /// Kiểm tra phiên bản + hash với server (popup chặn bản cũ).
    static func check(version: String, sha256: String, license: String, device: String,
                      done: @escaping ([String: Any]) -> Void) {
        post("/api/client/check", [
            "version": version, "sha256": sha256,
            "licenseKey": license, "deviceId": device,
        ]) { j in
            done(j)
        }
    }

    /// Tải + giải mã patch mới nhất, ghi vào Documents/remote_patch.bytes.
    static func refreshPatch(license: String, device: String, done: @escaping (Bool) -> Void) {
        fetchSecret(license: license, device: device) { secret in
            guard let secret = secret else { return done(false) }
            let q = "licenseKey=\(esc(license))&deviceId=\(esc(device))"
            guard let url = URL(string: ServerConfig.base + "/api/client/patch?" + q) else { return done(false) }
            var req = URLRequest(url: url)
            req.timeoutInterval = 30
            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let data = data,
                      let plain = decrypt(data, secret: secret, license: license, device: device) else {
                    return done(false)
                }
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let dest = docs.appendingPathComponent("remote_patch.bytes")
                do {
                    try plain.write(to: dest, options: .atomic)
                    done(true)
                } catch {
                    done(false)
                }
            }.resume()
        }
    }

    // MARK: - secret (server cấp cho thiết bị đã kích hoạt)

    private static func fetchSecret(license: String, device: String, done: @escaping (String?) -> Void) {
        let q = "licenseKey=\(esc(license))&deviceId=\(esc(device))"
        guard let url = URL(string: ServerConfig.base + "/api/client/secret?" + q) else { return done(nil) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let s = j["secret"] as? String else { return done(nil) }
            done(s)
        }.resume()
    }

    // MARK: - BOLAP2 decrypt (khớp lib/patchcrypto.js của server)

    static func decrypt(_ data: Data, secret: String, license: String, device: String) -> Data? {
        guard data.count > 45, data.prefix(6) == Data("BOLAP2".utf8) else { return nil }
        let len = Int(data[9]) << 24 | Int(data[10]) << 16 | Int(data[11]) << 8 | Int(data[12])
        guard len > 0, data.count >= 45 + len else { return nil }
        let sha = data.subdata(in: 13..<45)
        let cipher = data.subdata(in: 45..<(45 + len))
        let key = sha256(Data("\(secret):\(license):\(device)".utf8))
        var stream = Data()
        var i: UInt32 = 0
        while stream.count < cipher.count {
            var block = key
            var c = i.bigEndian
            withUnsafeBytes(of: &c) { block.append(contentsOf: $0) }
            stream.append(sha256(block))
            i += 1
        }
        var plain = Data(count: cipher.count)
        for idx in 0..<cipher.count { plain[idx] = cipher[idx] ^ stream[idx] }
        return sha256(plain) == sha ? plain : nil
    }

    static func sha256(_ d: Data) -> Data {
        var out = Data(count: 32)
        out.withUnsafeMutableBytes { ob in
            d.withUnsafeBytes { ib in
                _ = CC_SHA256(ib.baseAddress, CC_LONG(d.count), ob.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        return out
    }

    // MARK: - helpers

    private static func post(_ path: String, _ body: [String: Any], done: @escaping ([String: Any]) -> Void) {
        guard let url = URL(string: ServerConfig.base + path) else { return done([:]) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            DispatchQueue.main.async { done(j) }
        }.resume()
    }

    private static func esc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}
