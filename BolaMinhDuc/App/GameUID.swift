import Foundation

/// UID tài khoản game (kiểu DELTA CLIENT): tự dò UID đang đăng nhập từ dữ
/// liệu phiên/tài khoản trong container game, ghi `.bola_uid` để patch trong
/// game đối chiếu (sai UID -> cảnh báo trong game), và xoá phiên khi đổi acc.
enum GameUID {

    /// Từ khoá dữ liệu phiên/tài khoản (theo DELTA) — dò UID dạng số.
    private static let keyWords = [
        "player_id", "playerid", "user_id", "userid", "uid", "openid",
        "player_uid", "garena_uid", "game_uid"
    ]

    // MARK: - detect

    /// Dò UID ở cả 2 game; trả về (uid, nguồn).
    static func detectFirst() -> (uid: String, source: String)? {
        for game in GameTarget.allCases {
            if let hit = detect(in: game) { return hit }
        }
        return nil
    }

    static func detect(in game: GameTarget) -> (uid: String, source: String)? {
        guard let container = Installer.containerPath(for: game.rawValue) else { return nil }
        let fm = FileManager.default
        let docs = container + "/Documents"
        guard let items = try? fm.contentsOfDirectory(atPath: docs) else { return nil }

        // Ưu tiên file chắc chắn theo DELTA, rồi mới quét theo tên.
        var ordered: [String] = []
        for name in ["settings.bin", "cache.bin", "sys.log"] {
            if items.contains(name) { ordered.append(name) }
        }
        let hints = ["user", "account", "login", "session", "player", "profile",
                     "token", "garena", "msdk", "game"]
        for f in items {
            let low = f.lowercased()
            if isOurFile(low) { continue }
            if hints.contains(where: { low.contains($0) }) { ordered.append(f) }
        }
        var seen = Set<String>()
        for f in ordered where !seen.contains(f) {
            seen.insert(f)
            let p = docs + "/" + f
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue else { continue }
            if let uid = extractUID(from: p) {
                return (uid, "Documents/" + f)
            }
        }
        return nil
    }

    private static func isOurFile(_ low: String) -> Bool {
        low.hasPrefix(".bola") || low == "assembly-csharp-patch.bytes"
            || low == "localconfig.json"
    }

    /// Tìm UID số trong file: `"player_id": 123...` / `uid=123...` (kể cả
    /// trong binary plist / log — quét ISO-8859-1 nên byte nào cũng đọc được).
    private static func extractUID(from path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int, size > 0, size <= 4_000_000 else { return nil }
        guard let data = FileManager.default.contents(atPath: path),
              let s = String(data: data, encoding: .isoLatin1) else { return nil }
        for kw in keyWords {
            let pattern = "(?:^|[^a-z0-9_])" + NSRegularExpression.escapedPattern(for: kw)
                + "[^0-9]{0,10}([0-9]{6,15})"
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let m = re.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)),
               let r = Range(m.range(at: 1), in: s) {
                return String(s[r])
            }
        }
        return nil
    }

    // MARK: - write / remove (.bola_uid trong container game)

    /// Ghi UID đang kích hoạt vào cả 2 container game (patch đối chiếu).
    @discardableResult
    static func write(_ uid: String) -> Int {
        var n = 0
        for game in GameTarget.allCases {
            guard let container = Installer.containerPath(for: game.rawValue) else { continue }
            let docs = container + "/Documents"
            try? FileManager.default.createDirectory(atPath: docs, withIntermediateDirectories: true)
            if (try? (uid + "\n").write(toFile: docs + "/.bola_uid", atomically: true, encoding: .utf8)) != nil {
                n += 1
            }
        }
        return n
    }

    /// Xoá UID khỏi cả 2 container (nút "Xóa UID hiện tại").
    @discardableResult
    static func remove() -> Int {
        let fm = FileManager.default
        var n = 0
        for game in GameTarget.allCases {
            guard let container = Installer.containerPath(for: game.rawValue) else { continue }
            let p = container + "/Documents/.bola_uid"
            if fm.fileExists(atPath: p) {
                if (try? fm.removeItem(atPath: p)) != nil { n += 1 }
            }
        }
        return n
    }

    // MARK: - wipe session (đổi tài khoản — theo DELTA logout)

    /// Xoá dữ liệu phiên đăng nhập: file session/token/cookie trong Documents
    /// + Cookies/WebKit của game. Dùng khi muốn đổi sang tài khoản khác.
    @discardableResult
    static func wipeSession() -> Int {
        let fm = FileManager.default
        var removed = 0
        let sessionHints = ["session", "token", "auth", "login", "credential",
                            "openid", "cookie", "ticket", "user_id", "account"]
        for game in GameTarget.allCases {
            guard let container = Installer.containerPath(for: game.rawValue) else { continue }
            let docs = container + "/Documents"
            if let items = try? fm.contentsOfDirectory(atPath: docs) {
                for f in items {
                    let low = f.lowercased()
                    if isOurFile(low) { continue }
                    if sessionHints.contains(where: { low.contains($0) }) {
                        let p = docs + "/" + f
                        var isDir: ObjCBool = false
                        fm.fileExists(atPath: p, isDirectory: &isDir)
                        if !isDir.boolValue, (try? fm.removeItem(atPath: p)) != nil { removed += 1 }
                    }
                }
            }
            let fixed = [
                "Library/Cookies/Cookies.binarycookies",
                "Library/WebKit/WebsiteData",
                "Library/Caches/garena",
                "Library/Caches/com.garena",
                "Library/Caches/com.facebook.sdk"
            ]
            for rel in fixed {
                let p = container + "/" + rel
                if fm.fileExists(atPath: p), (try? fm.removeItem(atPath: p)) != nil { removed += 1 }
            }
        }
        return removed
    }
}
