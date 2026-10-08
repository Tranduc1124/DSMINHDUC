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
    static let patchFileName = "Assembly-CSharp-patch.bytes"
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
            return "Chưa đọc được thư mục game (cần kích hoạt exploit trước)."
        }
        let patch = container + "/Documents/" + patchFileName
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: patch) else {
            return "Game sạch — chưa có patch."
        }
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        let date = (attrs[.modificationDate] as? Date).map {
            DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .medium)
        } ?? "?"
        return "Đang có patch: \(size) bytes • \(date)"
    }

    /// Writes a tiny probe file into the game's Documents folder to prove the
    /// container is actually writable (works even when the sandbox-escape
    /// probe reports otherwise on iOS 17/18).
    static func canWrite(into game: GameTarget) -> Bool {
        guard let container = containerPath(for: game.rawValue) else { return false }
        let docs = container + "/Documents"
        let probe = docs + "/.bola_probe_\(getpid())"
        do {
            try Data([0x42]).write(to: URL(fileURLWithPath: probe))
            try? FileManager.default.removeItem(atPath: probe)
            return true
        } catch {
            return false
        }
    }

    static func install(patch: URL, into game: GameTarget) -> InstallOutcome {
        guard let container = containerPath(for: game.rawValue) else {
            return InstallOutcome(
                ok: false,
                message: "Không tìm thấy \(game.title). Kích hoạt exploit trước hoặc kiểm tra game đã cài chưa.")
        }
        let fm = FileManager.default
        let docs = container + "/Documents"
        let dest = docs + "/" + patchFileName
        do {
            if !fm.fileExists(atPath: docs) {
                try fm.createDirectory(atPath: docs, withIntermediateDirectories: true)
            }
            if fm.fileExists(atPath: dest) {
                let backup = dest + ".bak"
                if fm.fileExists(atPath: backup) {
                    try? fm.removeItem(atPath: backup)
                }
                try? fm.moveItem(atPath: dest, toPath: backup)
            }
            try fm.copyItem(atPath: patch.path, toPath: dest)
            return InstallOutcome(ok: true,
                                  message: "Đã cài patch vào \(game.title). Mở game để kiểm tra.")
        } catch {
            return InstallOutcome(ok: false,
                                  message: "Lỗi ghi file: \(error.localizedDescription)")
        }
    }

    static func restore(game: GameTarget) -> InstallOutcome {
        guard let container = containerPath(for: game.rawValue) else {
            return InstallOutcome(ok: false, message: "Không tìm thấy thư mục game.")
        }
        let fm = FileManager.default
        let dest = container + "/Documents/" + patchFileName
        guard fm.fileExists(atPath: dest) else {
            return InstallOutcome(ok: true, message: "Không có patch để xoá.")
        }
        do {
            let backup = dest + ".bak"
            if fm.fileExists(atPath: backup) {
                try? fm.removeItem(atPath: backup)
            }
            try fm.moveItem(atPath: dest, toPath: backup)
            return InstallOutcome(ok: true,
                                  message: "Đã xoá patch (bản cũ lưu tại .bak). Game về trạng thái sạch.")
        } catch {
            return InstallOutcome(ok: false,
                                  message: "Lỗi xoá patch: \(error.localizedDescription)")
        }
    }
}
