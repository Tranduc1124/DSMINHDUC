import Foundation

/// Anti-ban kiểu INNOVA CHEAT (bỏ hẳn kiểu DELTA):
///   1. dọn telemetry cache trong Library/Caches (danh sách của INNOVA)
///   2. "removed new file": quét file MỚI sinh ra trong lúc chơi → xoá
///   3. dọn "file lộ" khỏi Documents (rác tool khác / bản cũ)
///   4. "🌪️ Đã tạo N file rác": thả ~1000 file rác 512KB ngẫu nhiên vào
///      Documents — patch thật (Assembly-CSharp-patch.bytes) TRỘN LẪN vào
///      đống đó + file giả "na ná patch" + bait 1MB (giống INNOVA)
/// Chạy lặp mỗi ~10s khi app còn sống (kể cả keep-alive nền).
enum Antiban {
    /// Prefix decoy bait — dùng chung cho lúc thả & lúc gỡ.
    static let decoyPrefixes = ["BOLA_CHEAT_", "BOLA_MENU_", "MINHDUC_BAIT_"]
    /// File giả "na ná" patch thật — để patch thật trộn vào đám rác.
    static let patchSiblings = ["Assembly-CSharp-patch.bak",
                                "Assembly-CSharp-patch_old.bytes",
                                "Assembly-CSharp-patch2.bytes",
                                "Assembly-CSharp-patch(1).bytes",
                                "Assembly-CSharp-patch-copy.bytes"]
    /// Manifest ghi tên các file rác — để trong CONTAINER CỦA APP MÌNH
    /// (không nằm trong thư mục game nữa, tránh lộ dấu vết).
    private static let junkManifest = ".bola_junk"
    private static func manifestPath(_ raw: String) -> String {
        let mine = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        return mine + "/bola_junk_" + raw + ".txt"
    }
    /// Prefix rác thả trong Library/Caches.
    private static let cacheJunkPrefix = "cache_data_"
    /// Chặn chạy plantJunk trùng lặp (tránh văng app khi bật anti liên tục).
    private static var planting = false

    /// Một lượt dọn: cache telemetry + file lộ + (tuỳ chọn) sweep file mới.
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

    /// "[FreeFirePatch] 🧹 dọn dẹp file lộ khỏi Documents" (kiểu INNOVA):
    /// xoá rác của tool khác / bản cũ trong Documents game — trừ file của mình.
    @discardableResult
    static func cleanExposed(game: GameTarget) -> Int {
        let fm = FileManager.default
        guard let container = Installer.containerPath(for: game.rawValue) else { return 0 }
        let docs = container + "/Documents"
        let manifest = junkNames(path: manifestPath(game.rawValue))
        var removed = 0
        let keep: Set<String> = ["Assembly-CSharp-patch.bytes", "localConfig.json",
                                 ".bola_tok", ".bola_uid", ".bola_dbg.txt", ".bola_probe"]
        let hints = ["bolt", "airlift", "innova", "delta", "cheat", "hack",
                     "bolaminhduc", "bolt_", "air_lift"]
        guard let items = try? fm.contentsOfDirectory(atPath: docs) else { return 0 }
        for f in items {
            if keep.contains(f) { continue }
            if isOurJunk(f, manifest: manifest) { continue }
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

    /// "Removed new file (restored)": file sinh ra sau khi bật anti-ban (mtime
    /// >= since) mà tên dính log/telemetry/anti-cheat → xoá. Không bao giờ
    /// đụng file của patch mình (patch/localConfig/token/rác của mình).
    @discardableResult
    static func sweepNewFiles(game: GameTarget, since: Date) -> Int {
        let fm = FileManager.default
        guard let container = Installer.containerPath(for: game.rawValue) else { return 0 }
        let manifest = junkNames(path: manifestPath(game.rawValue))
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
                if isOurJunk(f, manifest: manifest) { continue }
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

    // MARK: - "🌪️ đống file rác" (kiểu INNOVA)

    /// Thả MỘT ĐỐNG file rác vào container game: ~1000 file 512KB +
    /// 5 file giả na ná patch + 2 bait 1MB + 3 rác trong Caches.
    /// Patch thật nằm lẫn trong đống — nhìn vào không biết file nào là thật.
    @discardableResult
    static func plantJunk() -> Int {
        if planting { return 0 }
        planting = true
        defer { planting = false }
        let fm = FileManager.default
        var planted = 0
        for game in [GameTarget.freefireTH, GameTarget.freefireMAX] {
            guard let container = Installer.containerPath(for: game.rawValue) else { continue }
            let doc = container + "/Documents"
            let caches = container + "/Library/Caches"
            try? fm.createDirectory(atPath: doc, withIntermediateDirectories: true)
            try? fm.createDirectory(atPath: caches, withIntermediateDirectories: true)
            _ = removeJunkFiles(doc: doc, caches: caches,
                                manifest: manifestPath(game.rawValue)) // dọn rác cũ trước
            var names: [String] = []

            // ~1000 file rác TO (512KB) — giống decoy của INNOVA (theo yêu cầu).
            // Patch thật trộn lẫn trong đống này.
            // autoreleasepool từng file: không gom rác bộ nhớ -> không văng.
            let alnum = Array("abcdefghijklmnopqrstuvwxyz0123456789")
            for _ in 0..<1000 {
                autoreleasepool {
                    let tag = (0..<11).map { _ in String(alnum[Int.random(in: 0..<alnum.count)]) }.joined()
                    let name = "BOLA_CHEAT_\(tag).bytes"
                    if writeJunk(doc + "/" + name, size: 512_000) { names.append(name); planted += 1 }
                }
            }
            // 5 file giả "na ná patch thật" — patch thật trộn vào đây
            for sib in patchSiblings {
                if writeJunk(doc + "/" + sib, size: 40_000 + Int.random(in: 0...160_000)) {
                    names.append(sib); planted += 1
                }
            }
            // 2 bait (1MB + 1 json) — chống Filza dump
            let hex1 = (0..<4).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
            let b1 = "BOLA_CHEAT_\(hex1).bytes"
            if writeJunk(doc + "/" + b1, size: 1_000_000 + Int.random(in: 0...200_000)) {
                names.append(b1); planted += 1
            }
            let hex2 = (0..<4).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
            let b2 = "BOLA_MENU_\(hex2).json"
            if writeJunk(doc + "/" + b2, size: 600 + Int.random(in: 0...900)) {
                names.append(b2); planted += 1
            }
            // 3 rác trong Library/Caches
            for _ in 0..<3 {
                let hex = (0..<4).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
                if writeJunk(caches + "/\(cacheJunkPrefix)\(hex).bin",
                             size: 20_000 + Int.random(in: 0...80_000)) {
                    planted += 1
                }
            }
            // manifest để gỡ sạch sau này — ghi vào container của APP MÌNH
            try? (names.joined(separator: "\n") + "\n")
                .write(toFile: manifestPath(game.rawValue), atomically: true, encoding: .utf8)
        }
        return planted
    }

    private static func writeJunk(_ path: String, size: Int) -> Bool {
        // random thuần (entropy ~8.0 như decoy INNOVA) + sinh nhanh bằng
        // arc4random_buf (512KB x 1000 file không bị chậm như map() từng byte).
        var junk = Data(count: size)
        junk.withUnsafeMutableBytes { ptr in
            if let base = ptr.baseAddress {
                arc4random_buf(base, size)
            }
        }
        return (try? junk.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
    }

    /// Gỡ sạch rác/decoy của mình khỏi 2 container (khi tắt anti / unject).
    @discardableResult
    static func removeDecoys() -> Int {
        var n = 0
        for game in [GameTarget.freefireTH, GameTarget.freefireMAX] {
            guard let container = Installer.containerPath(for: game.rawValue) else { continue }
            n += removeJunkFiles(doc: container + "/Documents",
                                 caches: container + "/Library/Caches",
                                 manifest: manifestPath(game.rawValue))
            n += removeDecoys(in: container + "/Documents")
            n += removeDecoys(in: container + "/Library")
        }
        return n
    }

    private static func removeJunkFiles(doc: String, caches: String, manifest: String) -> Int {
        let fm = FileManager.default
        var n = 0
        // theo manifest (trong container app mình)
        if let s = try? String(contentsOfFile: manifest, encoding: .utf8) {
            for line in s.split(separator: "\n") {
                let name = String(line).trimmingCharacters(in: .whitespaces)
                if name.isEmpty { continue }
                if (try? fm.removeItem(atPath: doc + "/" + name)) != nil { n += 1 }
            }
            try? fm.removeItem(atPath: manifest)
        }
        // manifest cũ (bản trước để trong thư mục game) — dọn luôn
        try? fm.removeItem(atPath: doc + "/" + junkManifest)
        // tên cố định (phòng khi manifest mất)
        for sib in patchSiblings {
            if (try? fm.removeItem(atPath: doc + "/" + sib)) != nil { n += 1 }
        }
        // rác trong Caches
        if let items = try? fm.contentsOfDirectory(atPath: caches) {
            for f in items where f.hasPrefix(cacheJunkPrefix) {
                if (try? fm.removeItem(atPath: caches + "/" + f)) != nil { n += 1 }
            }
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

    /// Đọc manifest rác (trong container app mình) → set tên file.
    private static func junkNames(path: String) -> Set<String> {
        var set: Set<String> = []
        if let s = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in s.split(separator: "\n") {
                let name = String(line).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { set.insert(name) }
            }
        }
        return set
    }

    /// File này có phải rác của mình không (đừng xoá nhầm).
    private static func isOurJunk(_ name: String, manifest: Set<String>) -> Bool {
        if name == junkManifest { return true }
        if decoyPrefixes.contains(where: { name.hasPrefix($0) }) { return true }
        if name.hasPrefix(cacheJunkPrefix) { return true }
        if patchSiblings.contains(name) { return true }
        if manifest.contains(name) { return true }
        return false
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
