import Foundation

/// Anti-ban: continuously wipe the game's telemetry / crash caches while the
/// app runs (the reference tool keeps cleaning on a repeating timer, so any
/// post-match report has nothing to upload). Flow: open app -> keep cleaning
/// in the background -> inject -> play.
enum Antiban {
    /// One silent cleanup pass over both Free Fire containers.
    @discardableResult
    static func cleanAll() -> Int {
        var removed = 0
        removed += clean(game: .freefireTH)
        removed += clean(game: .freefireMAX)
        return removed
    }

    /// Removes telemetry / crash-report traces inside one game container.
    @discardableResult
    static func clean(game: GameTarget) -> Int {
        let fm = FileManager.default
        guard let container = Installer.containerPath(for: game.rawValue) else { return 0 }
        var removed = 0

        // the reference tool's exact telemetry / crash-cache list
        let fixed = [
            "Library/Caches/Analytics",
            "Library/Caches/CrashReporter",
            "Library/Caches/crashes",
            "Library/Caches/com.crashlytics.data",
            "Library/Caches/bugly",
            "Library/Caches/com.google.firebase",
            "Library/Caches/com.appsflyer",
            "Library/Caches/adjust-sdk",
            "Library/Caches/Snapshots"
        ]
        for rel in fixed {
            let p = container + "/" + rel
            if fm.fileExists(atPath: p) {
                if (try? fm.removeItem(atPath: p)) != nil { removed += 1 }
            }
        }

        // scan Library/Caches for telemetry-ish entries (case-insensitive)
        let caches = container + "/Library/Caches"
        if let items = try? fm.contentsOfDirectory(atPath: caches) {
            for f in items {
                let low = f.lowercased()
                if low.contains("analytics") || low.contains("bugly")
                    || low.contains("telemetry") || low.contains("crash") {
                    if (try? fm.removeItem(atPath: caches + "/" + f)) != nil { removed += 1 }
                }
            }
        }

        // the game's own crash reports on the device
        let crashDir = "/var/mobile/Library/Logs/CrashReporter"
        if let items = try? fm.contentsOfDirectory(atPath: crashDir) {
            for f in items where f.lowercased().contains("freefire") {
                if (try? fm.removeItem(atPath: crashDir + "/" + f)) != nil { removed += 1 }
            }
        }
        return removed
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
