import Foundation

/// Anti-ban kiểu INNOVA CHEAT (bỏ hẳn kiểu DELTA):
///   1. dọn telemetry cache trong Library/Caches (danh sách của INNOVA)
///   2. "removed new file": quét file MỚI sinh ra trong lúc chơi → xoá
///   3. decoy bait: thả file giả "BOLA_CHEAT_*" vào Documents — scan của game
///      nhặt phải bait thì tưởng đã xử lý xong, patch thật nằm yên
/// Chạy lặp mỗi ~10s khi app còn sống (kể cả keep-alive nền).
enum Antiban {
    /// Tên decoy bait — dùng chung cho lúc thả & lúc gỡ.
    static let decoyPrefixes = ["BOLA_CHEAT_", "BOLA_MENU_", "MINHDUC_BAIT_"]

    /// Một lượt dọn: cache telemetry + file lộ Documents + (tuỳ chọn) sweep file mới.
    @discardableResult
    static func cleanAll(since: Date? = nil) -> Int {
        var removed = 0
        for g in [GameTarget.freefireTH, GameTarget.freefireMAX] {
            removed += cleanCaches(game: g)
            removed += cleanExposed(game: g)
            if let since = since {
                removed += sweepNewFiles(game: g, since: since)
            }
        }
        return removed
    }

    /// "[FreeFirePatch] 🧹 dọn dẹp file lộ khỏi Documents" (kiểu INNOVA):
    /// xoá rác của tool khác / bản cũ trong Documents game — trừ file của mình.
    @discardableResult
    static func cleanExposed(game: GameTarget) -> Int {
        let fm = FileManager.default
        guard let container = Installer.containerPath(for: game.rawValue) else { return 0 }
        var removed = 0
        let keep: Set<String> = ["Assembly-CSharp-patch.bytes", "localConfig.json",
                                 ".bola_tok", ".bola_uid", ".bola_dbg.txt", ".bola_probe"]
        let hints = ["bolt", "airlift", "innova", "delta", "cheat", "hack",
                     "bolaminhduc", "bolt_", "air_lift"]
        let docs = container + "/Documents"
        guard let items = try? fm.contentsOfDirectory(atPath: docs) else { return 0 }
        for f in items {
            if keep.contains(f) { continue }
            if decoyPrefixes.contains(where: { f.hasPrefix($0) }) { continue }
            let low = f.lowercased()
            guard hints.contains(where: { low.contains($0) }) else { continue }
            let p = docs + "/" + f
            var isDir: ObjCBool = false
            fm.fileExists(atPath: p, isDirectory: &isDir)
            guard let attrs = try? fm.attributesOfItem(atPath: p),
                  let size = attrs[.size] as? Int, !isDir.boolValue,
                  size < 50 * 1024 * 1024 else { continue }
            if (try? fm.removeItem(atPath: p)) != nil { removed += 1 }
        }
        return removed
    }

    /// Library/Caches — đúng danh sách INNOVA CHEAT dọn.
    @discardableResult
    static func cleanCaches(game: GameTarget) -> Int {
        let fm = FileManager.default
        guard let container = Installer.containerPath(for: game.rawValue) else { return 0 }
        var removed = 0
        let fixed = [
            "Library/Caches/Analytics",
            "Library/Caches/CrashReporter",
            "Library/Caches/Snapshots",
            "Library/Caches/adjust-sdk",
            "Library/Caches/bugly",
            "Library/Caches/com.appsflyer",
            "Library/Caches/com.crashlytics.data",
            "Library/Caches/com.google.firebase",
            "Library/Caches/crashes"
        ]
        for rel in fixed {
            let p = container + "/" + rel
            if fm.fileExists(atPath: p) {
                if (try? fm.removeItem(atPath: p)) != nil { removed += 1 }
            }
        }
        return removed
    }

    /// "Removed new file (restored)": file sinh ra sau khi bật anti-ban (mtime
    /// >= since) mà tên dính log/telemetry/anti-cheat → xoá. Không bao giờ
    /// đụng file của patch mình (patch/localConfig/token/decoy).
    @discardableResult
    static func sweepNewFiles(game: GameTarget, since: Date) -> Int {
        let fm = FileManager.default
        guard let container = Installer.containerPath(for: game.rawValue) else { return 0 }
        var removed = 0
        let keep: Set<String> = ["Assembly-CSharp-patch.bytes", "localConfig.json",
                                 ".bola_tok", ".bola_uid", ".bola_dbg.txt", ".bola_probe",
                                 ".com.apple.mobile_container_manager.metadata.plist"]
        let hints = ["log", "trace", "report", "crash", "analytic", "bugly", "telemetry",
                     "beacon", "garena", "tencent", "anticheat", "anti_cheat", "shadow",
                     "upload", "feedback", "audit", "detect", "integrity", "tlog", "xlog",
                     "tdlog", "sys.log"]
        let dirs = [container + "/Documents",
                    container + "/Library",
                    container + "/Library/Caches"]
        let cutoff = since.addingTimeInterval(-90) // chừa biên 90s vì mtime có thể lệch
        for d in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: d) else { continue }
            for f in items {
                if keep.contains(f) { continue }
                if decoyPrefixes.contains(where: { f.hasPrefix($0) }) { continue }
                if f == "contentcache" || f == "Preferences" { continue }
                let low = f.lowercased()
                guard hints.contains(where: { low.contains($0) }) else { continue }
                let p = d + "/" + f
                var isDir: ObjCBool = false
                fm.fileExists(atPath: p, isDirectory: &isDir)
                if isDir.boolValue { continue }
                guard let attrs = try? fm.attributesOfItem(atPath: p),
                      let mt = attrs[.modificationDate] as? Date, mt >= cutoff else { continue }
                if (try? fm.removeItem(atPath: p)) != nil { removed += 1 }
            }
        }
        return removed
    }

    // MARK: - decoy bait (giống INNOVA_CHEAT_xxxxx.bytes)

    /// Thả 2 file giả vào Documents của game (bait cho scan). Đổi tên mỗi lần
    /// bật để nhìn như "file rác/cheat thật".
    @discardableResult
    static func plantDecoys() -> Int {
        let fm = FileManager.default
        var planted = 0
        for game in [GameTarget.freefireTH, GameTarget.freefireMAX] {
            guard let container = Installer.containerPath(for: game.rawValue) else { continue }
            let doc = container + "/Documents"
            try? fm.createDirectory(atPath: doc, withIntermediateDirectories: true)
            _ = removeDecoys(in: doc) // dọn decoy cũ trước
            for i in 0..<2 {
                let hex = (0..<4).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
                let name = i == 0 ? "BOLA_CHEAT_\(hex).bytes" : "BOLA_MENU_\(hex).json"
                let path = doc + "/" + name
                var junk = Data("BOLA_\(hex)_BAIT".utf8)
                junk.append(Data((0..<(1_000_000 + Int.random(in: 0...200_000))).map { _ in UInt8.random(in: 0...255) }))
                if (try? junk.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil {
                    planted += 1
                }
            }
        }
        return planted
    }

    /// Gỡ hết decoy của mình khỏi 2 container game.
    @discardableResult
    static func removeDecoys() -> Int {
        var n = 0
        for game in [GameTarget.freefireTH, GameTarget.freefireMAX] {
            guard let container = Installer.containerPath(for: game.rawValue) else { continue }
            n += removeDecoys(in: container + "/Documents")
            n += removeDecoys(in: container + "/Library")
        }
        return n
    }

    private static func removeDecoys(in dir: String) -> Int {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return 0 }
        var n = 0
        for f in items where decoyPrefixes.contains(where: { f.hasPrefix($0) }) {
            if (try? fm.removeItem(atPath: dir + "/" + f)) != nil { n += 1 }
        }
        return n
    }

    // MARK: - Reset Guest

    /// "Reset Guest": forces the game's own debug config file
    /// `Documents/localConfig.json` with `{"testCodePatch":true,"resetGuest":true}`
    /// into both game containers - exactly what the reference tool does when
    /// its reset button is pressed. The game reads that flag on next launch
    /// and resets its guest account (and bootstraps a fresh local identity).
    /// The user should force-close the game first, then relaunch it.
    @discardableResult
    static func resetGuest() -> Int {
        let fm = FileManager.default
        let json = "{\"testCodePatch\":true,\"resetGuest\":true}"
        var written = 0
        for game in [GameTarget.freefireTH, GameTarget.freefireMAX] {
            guard let container = Installer.containerPath(for: game.rawValue) else { continue }
            let doc = container + "/Documents"
            try? fm.createDirectory(atPath: doc, withIntermediateDirectories: true)
            let path = doc + "/localConfig.json"
            if let data = json.data(using: .utf8),
               (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil {
                written += 1
            }
        }
        return written
    }
}
