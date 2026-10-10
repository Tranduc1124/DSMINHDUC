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

    /// "Reset Guest": wipes the local guest/account identity files (the
    /// preferences plists Free Fire uses to bind the device to its guest
    /// account) so the next launch creates a brand-new guest. The reference
    /// tool ships the same trick behind its `resetGuest` config flag and
    /// uses it for ban evasion. Best done with the game force-closed,
    /// otherwise the running game can rewrite its preferences on exit.
    @discardableResult
    static func resetGuest() -> Int {
        let fm = FileManager.default
        var removed = 0
        for game in [GameTarget.freefireTH, GameTarget.freefireMAX] {
            guard let container = Installer.containerPath(for: game.rawValue) else { continue }
            let prefs = container + "/Library/Preferences"
            if let items = try? fm.contentsOfDirectory(atPath: prefs) {
                for f in items {
                    let low = f.lowercased()
                    if low.contains("freefire") || low.contains("dts.") {
                        if (try? fm.removeItem(atPath: prefs + "/" + f)) != nil {
                            removed += 1
                        }
                    }
                }
            }
        }
        return removed
    }
}
