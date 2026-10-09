import Foundation

/// Collects recent crash evidence into the app's Documents/logs_vang
/// (visible in the Files app). Needs the sandbox escape active to reach
/// system paths like /var/mobile/Library/Logs/CrashReporter.
enum CrashLogs {
    static func collect(containers: [String]) -> Int {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return 0 }
        let outDir = docs.appendingPathComponent("logs_vang", isDirectory: true)
        try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        var copied = 0
        let cutoff = Date().addingTimeInterval(-3 * 24 * 3600)

        func consider(_ path: String, _ name: String) {
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let mdate = attrs[.modificationDate] as? Date, mdate > cutoff else { return }
            let dst = outDir.appendingPathComponent(name)
            try? fm.removeItem(at: dst)
            if (try? fm.copyItem(atPath: path, toPath: dst.path)) != nil { copied += 1 }
        }

        let crashDirs = [
            "/var/mobile/Library/Logs/CrashReporter",
            "/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs"
        ]
        for dir in crashDirs {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for f in files {
                let low = f.lowercased()
                if low.contains("freefire") || low.contains("free_fire") || low.contains("jetsam") {
                    consider(dir + "/" + f, f)
                }
            }
        }
        for container in containers {
            let garena = container + "/Documents/garena_log"
            if fm.fileExists(atPath: garena) {
                consider(garena, "garena_log.txt")
            }
        }
        return copied
    }
}
