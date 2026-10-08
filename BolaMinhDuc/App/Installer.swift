import Foundation

enum GameTarget: String, CaseIterable, Identifiable {
    case freefireTH = "com.dts.freefireth"
    case freefireMAX = "com.dts.freefiremax"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freefireTH: return "Free Fire"
        case .freefireMAX: return "Free Fire MAX"
        }
    }
}

struct InstallOutcome {
    let ok: Bool
    let message: String
}

/// Finds another app's data container (by bundle id) and drops the patch
/// file into its Documents folder. Requires the sandbox escape to be active.
enum Installer {
    // localized string helper (reads the app language directly)
    private static func tr(_ vi: String, _ en: String) -> String {
        (UserDefaults.standard.string(forKey: "bola_lang") ?? "vi") == "en" ? en : vi
    }

    static let patchFileName = "Assembly-CSharp-patch.bytes"
    static let localConfigName = "localConfig.json"
    private static let applicationRoot = "/var/mobile/Containers/Data/Application"

    /// nil when the container cannot be read (not activated / game missing).
    static func containerPath(for bundleID: String) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: applicationRoot) else {
            return nil
        }
        for entry in entries {
            let dir = applicationRoot + "/" + entry
            let meta = dir + "/.com.apple.mobile_container_manager.metadata.plist"
            guard let data = fm.contents(atPath: meta),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: data, options: [], format: nil) as? [String: Any],
                  let identifier = plist["MCMMetadataIdentifier"] as? String,
                  identifier == bundleID
            else { continue }
            return dir
        }
        return nil
    }

    static func installedPatchInfo(for game: GameTarget) -> String {
        guard let container = containerPath(for: game.rawValue) else {
            return tr("Chưa kết nối được với game", "Can't reach the game")
        }
        let docs = container + "/Documents"
        let fm = FileManager.default
        if fm.fileExists(atPath: docs + "/" + patchFileName) {
            return tr("Đã cài đặt", "Installed")
        }
        return tr("Chưa cài đặt", "Not installed")
    }

    /// Writes a tiny probe file into the game's Documents folder to prove the
    /// container is actually writable (works even when the sandbox-escape
    /// probe reports otherwise on iOS 17/18).
    /// Read-only access check: can we reach the game's container and list its
    /// Documents folder? Creates nothing on disk.
    static func hasAccess(to game: GameTarget) -> Bool {
        guard let container = containerPath(for: game.rawValue) else { return false }
        let docs = container + "/Documents"
        let fm = FileManager.default

        // 1. directory listing (fails while fully sandboxed)
        guard (try? fm.contentsOfDirectory(atPath: docs)) != nil else { return false }

        // 2. POSIX open for reading on the folder itself
        let fd = open(docs, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        if fd >= 0 {
            close(fd)
            return true
        }

        // 3. fall back to reading metadata of the installed patch, if present
        let patch = docs + "/" + patchFileName
        if let handle = FileHandle(forReadingAtPath: patch) {
            handle.closeFile()
            return true
        }
        return false
    }

    static func patchExists(for game: GameTarget) -> Bool {
        guard let container = containerPath(for: game.rawValue) else { return false }
        return FileManager.default.fileExists(atPath: container + "/Documents/" + patchFileName)
    }

    static func install(patch: URL, into game: GameTarget) -> InstallOutcome {
        guard let container = containerPath(for: game.rawValue) else {
            return InstallOutcome(
                ok: false,
                message: tr("Không tìm thấy \(game.title). Kiểm tra game đã cài chưa nhé.",
                            "\(game.title) not found. Check that the game is installed."))
        }
        let fm = FileManager.default
        let docs = container + "/Documents"
        let dest = docs + "/" + patchFileName
        do {
            if !fm.fileExists(atPath: docs) {
                try fm.createDirectory(atPath: docs, withIntermediateDirectories: true)
            }
            let backup = dest + ".bak"
            if fm.fileExists(atPath: backup) {
                try? fm.removeItem(atPath: backup)
            }
            if fm.fileExists(atPath: dest) {
                try? fm.removeItem(atPath: dest)
            }
            try fm.copyItem(atPath: patch.path, toPath: dest)

            // community config shipped with the patch (local-json fix)
            if let cfg = Bundle.main.url(forResource: "localConfig", withExtension: "json") {
                let cfgDest = docs + "/" + localConfigName
                try? fm.removeItem(atPath: cfgDest)
                try? fm.copyItem(atPath: cfg.path, toPath: cfgDest)
            }

            return InstallOutcome(ok: true,
                                  message: tr("Đã cài xong cho \(game.title). Mở game để kiểm tra nhé.",
                                              "Installed for \(game.title). Open the game to test."))
        } catch {
            return InstallOutcome(ok: false,
                                  message: tr("Lỗi ghi file: ", "File error: ") + error.localizedDescription)
        }
    }

    static func restore(game: GameTarget) -> InstallOutcome {
        guard let container = containerPath(for: game.rawValue) else {
            return InstallOutcome(ok: false, message: tr("Không tìm thấy thư mục game.", "Game folder not found."))
        }
        let fm = FileManager.default
        let docs = container + "/Documents"
        let dest = docs + "/" + patchFileName
        let had = fm.fileExists(atPath: dest)
        // remove everything we install -- no backups kept around
        try? fm.removeItem(atPath: dest)
        try? fm.removeItem(atPath: dest + ".bak")
        try? fm.removeItem(atPath: docs + "/" + localConfigName)
        return InstallOutcome(
            ok: true,
            message: had
                ? tr("Đã gỡ xong. Mở lại game để áp dụng nhé.", "Removed. Reopen the game to apply.")
                : tr("Chưa có gì để gỡ.", "Nothing to remove."))
    }
}
