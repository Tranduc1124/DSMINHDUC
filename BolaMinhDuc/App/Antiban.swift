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

        let fixed = [
            "Library/Caches/Analytics",
            "Library/Caches/bugly",
            "Library/Caches/KSCrash",
            "Library/Caches/Crashlytics"
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
}
