import Foundation
import UIKit
import Darwin

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

    /// Detects whether the game is installed — works even before the sandbox
    /// escape: LSApplicationWorkspace enumeration (+ dlopen fallback), then the
    /// game's URL scheme, then the container scan when the escape is active.
    static func isGameDetected(_ bundleID: String) -> Bool {
        if isDetectedViaLS(bundleID) {
            return true
        }
        if bundleID == "com.dts.freefireth", canOpenURLScheme("freefire") {
            return true
        }
        return containerPath(for: bundleID) != nil
    }

    private static func isDetectedViaLS(_ bundleID: String) -> Bool {
        loadLSFrameworkIfNeeded()
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              let ws = cls.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject else {
            return false
        }
        for selName in ["allInstalledApplications", "allApplications"] {
            guard let list = ws.perform(NSSelectorFromString(selName))?.takeUnretainedValue() as? [NSObject] else {
                continue
            }
            for app in list {
                if let bid = app.perform(NSSelectorFromString("bundleIdentifier"))?.takeUnretainedValue() as? String,
                   bid == bundleID {
                    return true
                }
                if let bid = app.perform(NSSelectorFromString("applicationIdentifier"))?.takeUnretainedValue() as? String,
                   bid == bundleID {
                    return true
                }
            }
        }
        return false
    }

    private static func loadLSFrameworkIfNeeded() {
        if NSClassFromString("LSApplicationWorkspace") != nil {
            return
        }
        let paths = [
            "/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices",
            "/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices"
        ]
        for p in paths {
            _ = dlopen(p, RTLD_NOW)
        }
    }

    private static func canOpenURLScheme(_ scheme: String) -> Bool {
        guard let url = URL(string: scheme + "://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// nil when the container cannot be read (not activated / game missing).
    static func containerPath(for bundleID: String) -> String? {
        // MobileHouseArrest fast path: when the app was signed with the MHA
        // identity, the container path comes straight from ContainerManager
        // and the activated sandbox extension grants read/write - no kernel
        // exploit involved (works on iOS 16 too).
        if let mha = mha_path_for_bundle(bundleID) {
            return String(cString: mha)
        }
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
        // Chống bypass màn key: tắt UI gate vẫn không cài được.
        // Cần canEnterApp (seal+server) + trailer khớp key.
        let lic = LicenseGate.shared.licenseKey
        guard LicenseGate.shared.canEnterApp,
              LicenseGate.shared.revalidate(),
              !lic.isEmpty else {
            return InstallOutcome(ok: false,
                                  message: tr("🔑 Chưa kích hoạt key — không thể inject.",
                                              "🔑 Key not activated — cannot inject."))
        }
        guard PatchLibrary.hasValidTrailer(patch, license: lic) else {
            return InstallOutcome(ok: false,
                                  message: tr("Patch không hợp lệ cho key này — mở lại app / kiểm tra mạng.",
                                              "Patch invalid for this key — reopen app / check network."))
        }
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

            // (v213) patch không đọc .bola_tok — dọn nếu còn.
            // (bolacfg.bin là config của patch — KHÔNG xoá!)
            try? fm.removeItem(atPath: docs + "/.bola_tok")

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

    /// Self-heal cho gate trong game: nếu patch ĐANG nằm trong game đúng là
    /// bản cá nhân hoá cho key hiện tại (licHash khớp), thì đảm bảo
    /// Documents/.bola_tok tồn tại và chứa đúng key đó. Cứu trường hợp token
    /// bị xoá thủ công (test gate) mà không cần inject lại.
    @discardableResult
    static func resyncTokenIfNeeded(for game: GameTarget) -> Bool {
        guard let container = containerPath(for: game.rawValue) else { return false }
        let lic = LicenseGate.shared.licenseKey
        guard !lic.isEmpty else { return false }
        let docs = container + "/Documents"
        let patchPath = docs + "/" + patchFileName
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: patchPath)),
              data.count > 128 else { return false }
        let tail = data.suffix(64)
        // magic "|BOLATK1|" XOR 0x5A — khớp PatchLibrary.trailerMagic
        let magicEnc: [UInt8] = [38, 24, 21, 22, 27, 14, 17, 107, 38]
        let magic = String(bytes: magicEnc.map { $0 ^ 0x5A }, encoding: .utf8) ?? ""
        guard let s = String(data: tail, encoding: .utf8), !magic.isEmpty, s.hasPrefix(magic) else { return false }
        let parts = s.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 4 else { return false }
        let licHash = PatchClient.sha256(Data(lic.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
        guard String(parts[2]) == String(licHash) else { return false }
        let tokPath = docs + "/.bola_tok"
        let existing = (try? String(contentsOfFile: tokPath, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existing == lic { return true }
        return (try? (lic + "\n").write(toFile: tokPath, atomically: true, encoding: .utf8)) != nil
    }

    /// Kiểm tra THỰC: viết được file vào Documents của game không.
    /// "Tốt" chỉ hiện khi thực sự ghi được (không đoán).
    @discardableResult
    static func canWriteIntoGame(_ game: GameTarget) -> Bool {
        guard hasAccess(to: game) else { return false }
        guard let container = containerPath(for: game.rawValue) else { return false }
        let fm = FileManager.default
        let docs = container + "/Documents"
        if !fm.fileExists(atPath: docs) {
            if (try? fm.createDirectory(atPath: docs, withIntermediateDirectories: true)) == nil {
                return false
            }
        }
        let probe = (docs as NSString).appendingPathComponent(".bola_probe")
        if fm.fileExists(atPath: probe) {
            return fm.isWritableFile(atPath: probe)
        }
        let ok = (try? Data("bola".utf8).write(to: URL(fileURLWithPath: probe), options: .atomic)) != nil
        if ok { try? fm.removeItem(atPath: probe) }
        return ok
    }

    /// Anti (kiểu INNOVA "rolledBack"): sau khi game đã nạp patch vào RAM,
    /// xoá 2 file boot khỏi Documents — patch vẫn chạy từ RAM, container sạch.
    @discardableResult
    static func rollbackBootFiles(game: GameTarget) -> Int {
        guard let container = containerPath(for: game.rawValue) else { return 0 }
        let fm = FileManager.default
        let docs = container + "/Documents"
        var n = 0
        for f in [patchFileName, localConfigName] {
            if (try? fm.removeItem(atPath: docs + "/" + f)) != nil { n += 1 }
        }
        return n
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
        // unject sạch: xoá luôn token để scan giữa/cuối trận không thấy gì
        try? fm.removeItem(atPath: docs + "/.bola_tok")
        try? fm.removeItem(atPath: docs + "/.bola_uid")
        try? fm.removeItem(atPath: docs + "/bolacfg.bin")
        return InstallOutcome(
            ok: true,
            message: had
                ? tr("Đã gỡ xong. Mở lại game để áp dụng nhé.", "Removed. Reopen the game to apply.")
                : tr("Chưa có gì để gỡ.", "Nothing to remove."))
    }
}
