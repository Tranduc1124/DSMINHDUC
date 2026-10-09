import Foundation
import Combine
import SwiftUI
import UIKit

final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running
        case active
        case failed
    }

    @Published var phase: Phase = .idle
    @Published var statusText = "Đang chuẩn bị…"
    @Published var game: GameTarget = .freefireTH
    @Published var installedInfo = ""
    @Published var patchInstalled = false
    @Published var logText = ""
    @Published var busy = false
    @Published var restoring = false
    @Published var toastText: String?
    private var toastToken = 0

    /// feature toggles shown in the app (pushed to the game live + persisted)
    static let cfgKeys = ["box", "line", "bone", "hp", "name", "dist", "bot", "count", "aim", "silent"]

    @Published var cfgFlags: [String: Bool] = [:]
    @Published var aimBone: Int = 0

    /// "vi" or "en" -- in-app language
    @Published var language: String = UserDefaults.standard.string(forKey: "bola_lang") ?? "vi"

    // device pairing file state
    @Published var pairingName: String? = nil
    @Published var pairingIdentifier: String? = nil
    @Published var pairingValid = false
    @Published var pairingBusy = false
    @Published var pairingPin: String? = nil
    @Published var pairingNeedPin = false
    @Published var pairingStage: String? = nil

    /// set when the user taps "HỦY INJECT" — skips install/launch at the next checkpoint
    private var cancelRequested = false

    /// anti double-tap: ignore INJECT/RESTORE right after any completed action
    private var lastActionTime = Date.distantPast
    private let settleWindow: TimeInterval = 1.2

    // MARK: kernel single-flight state (main-thread only)

    private var didBootstrap = false
    private var kernelInFlight = false
    private var kernelDone = false
    private var kernelWaiters: [(Bool) -> Void] = []

    init() {
        var d: [String: Bool] = [:]
        for k in AppModel.cfgKeys {
            if let v = UserDefaults.standard.object(forKey: "bola_cfg_" + k) as? Bool {
                d[k] = v
            } else {
                d[k] = (k == "aim" || k == "silent") ? false : true
            }
        }
        cfgFlags = d
        aimBone = UserDefaults.standard.integer(forKey: "bola_bone")
    }

    /// The one patch bundled in the app — custom patches are not accepted.
    var bundledPatch: PatchFile? {
        PatchLibrary.bundled()
    }

    // MARK: - feature flags

    func flag(_ key: String) -> Bool {
        cfgFlags[key] ?? true
    }

    func setFlag(_ key: String, _ value: Bool) {
        cfgFlags[key] = value
        UserDefaults.standard.set(value, forKey: "bola_cfg_" + key)
        writeConfig()
    }

    func setBone(_ value: Int) {
        aimBone = value
        UserDefaults.standard.set(value, forKey: "bola_bone")
        writeConfig()
    }

    // MARK: - ESP colors (box / line / bone)

    private func colorDefaults() -> [String: [Double]] {
        ["box": [1.0, 0.15, 0.15], "line": [1.0, 0.15, 0.15], "bone": [1.0, 0.15, 0.15]]
    }

    func featureRGB(_ key: String) -> (Double, Double, Double) {
        let d = (UserDefaults.standard.array(forKey: "bola_col_" + key) as? [Double])
            ?? colorDefaults()[key] ?? [1.0, 0.15, 0.15]
        return (d[0], d[1], d[2])
    }

    func featureColor(_ key: String) -> Color {
        let (r, g, b) = featureRGB(key)
        return Color(red: r, green: g, blue: b)
    }

    func setFeatureColor(_ key: String, _ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 1
        var g: CGFloat = 0.15
        var b: CGFloat = 0.15
        var a: CGFloat = 1
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        UserDefaults.standard.set([Double(r), Double(g), Double(b)], forKey: "bola_col_" + key)
        writeConfig()
    }

    private func pack565(_ key: String) -> (UInt8, UInt8) {
        let (r, g, b) = featureRGB(key)
        let r5 = UInt16(max(0, min(31, Int(r * 31 + 0.5))))
        let g6 = UInt16(max(0, min(63, Int(g * 63 + 0.5))))
        let b5 = UInt16(max(0, min(31, Int(b * 31 + 0.5))))
        let v = (r5 << 11) | (g6 << 5) | b5
        return (UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF))
    }

    func setLanguage(_ code: String) {
        language = code
        UserDefaults.standard.set(code, forKey: "bola_lang")
    }

    func tr(_ vi: String, _ en: String) -> String {
        language == "en" ? en : vi
    }

    // MARK: - binary config (app -> game)
    //
    // bolacfg.bin = 16 obfuscated payload bytes + 4-byte CRC32 (little endian).
    // payload: "BOLA" | ver=1 | flags | - | 0...
    // flags bits: 0 box, 1 line, 2 hp, 3 name, 4 dist, 5 bot, 7 count.
    // byte 7: bit0 aim, bit1 skeleton bones, bit2 silent aim; byte 8: aim bone (0 head, 1 neck, 2 chest).
    // bytes 9..14: RGB565 box / line / bone colors (0 = default red).
    // The payload is XOR-ed with a per-index keystream, so a hand-edited file
    // without a matching checksum is ignored by the running patch.

    private func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in bytes {
            crc ^= UInt32(b)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return ~crc
    }

    /// Best-effort write; also called right before install so the file is
    /// guaranteed fresh when the game starts.
    func writeConfig() {
        guard let container = Installer.containerPath(for: game.rawValue) else { return }
        var payload = [UInt8](repeating: 0, count: 16)
        payload[0] = 0x42
        payload[1] = 0x4F
        payload[2] = 0x4C
        payload[3] = 0x41
        payload[4] = 1
        var flags: UInt8 = 0
        if flag("box")  { flags |= 1 }
        if flag("line") { flags |= 2 }
        if flag("hp")   { flags |= 4 }
        if flag("name") { flags |= 8 }
        if flag("dist") { flags |= 16 }
        if flag("bot")  { flags |= 32 }
        if flag("count") { flags |= 128 }
        payload[5] = flags
        var extra: UInt8 = 0
        if flag("aim") { extra |= 1 }
        if flag("bone") { extra |= 2 }
        if flag("silent") { extra |= 4 }
        payload[7] = extra
        payload[8] = UInt8(max(0, min(2, aimBone)))
        let (c9, c10) = pack565("box")
        let (c11, c12) = pack565("line")
        let (c13, c14) = pack565("bone")
        payload[9] = c9
        payload[10] = c10
        payload[11] = c11
        payload[12] = c12
        payload[13] = c13
        payload[14] = c14
        for i in 0..<16 {
            payload[i] ^= UInt8(truncatingIfNeeded: (0x5A + i * 0x37) ^ (i << 4))
        }
        var data = payload
        let crc = crc32(payload)
        data.append(UInt8(crc & 0xFF))
        data.append(UInt8((crc >> 8) & 0xFF))
        data.append(UInt8((crc >> 16) & 0xFF))
        data.append(UInt8((crc >> 24) & 0xFF))
        let path = container + "/Documents/bolacfg.bin"
        do {
            try Data(data).write(to: URL(fileURLWithPath: path), options: .atomic)
            append("cfg: đã ghi bolacfg.bin")
        } catch {
            append("cfg: không ghi được bolacfg.bin")
        }
    }

    // MARK: - log

    func append(_ line: String) {
        logText += line + "\n"
        if logText.count > 80_000 {
            logText.removeFirst(20_000)
        }
    }

    /// Custom in-app popup (replaces the system alert) with auto-dismiss.
    func showToast(_ text: String) {
        toastText = text
        toastToken += 1
        let token = toastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            guard let self else { return }
            if self.toastToken == token {
                self.toastText = nil
            }
        }
    }

    // MARK: - kernel (single run; INJECT joins a run already in flight)

    /// Auto-run policy: a sandbox escape only lives inside one process, so
    /// every app launch needs a fresh run — but if the game container is
    /// already reachable, the exploit is skipped (it is pointless then).
    /// A second tap of INJECT joins the run already in flight.
    func ensureKernel(_ completion: @escaping (Bool) -> Void) {
        if kernelDone {
            completion(true)
            return
        }
        kernelWaiters.append(completion)
        guard !kernelInFlight else { return }
        startKernelRun()
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        // already usable? (escape from a previous run still applies)
        if Installer.hasAccess(to: game) {
            kernelDone = true
            phase = .active
            statusText = "Đã sẵn sàng — không cần chuẩn bị lại"
            append("auto: đã truy cập được thư mục game → bỏ qua kernel (an toàn hơn)")
            refreshInstalled()
            writeConfig()
            return
        }

        // no access yet → run the exploit in the background
        append("auto: mở app → chạy exploit ở nền")
        ensureKernel { _ in }
    }

    private func startKernelRun() {
        kernelInFlight = true
        phase = .running
        statusText = "Đang chuẩn bị…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var ok = ExploitRunner.run { line in
                DispatchQueue.main.async { self?.append(line) }
            }
            if !ok {
                DispatchQueue.main.async { self?.append("exploit: thử lại lần 2…") }
                ok = ExploitRunner.run { line in
                    DispatchQueue.main.async { self?.append(line) }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.kernelInFlight = false
                self.kernelDone = ok
                self.phase = ok ? .active : .failed
                self.statusText = ok ? "Sẵn sàng — bấm INJECT" : "Có lỗi — thử lại nhé"
                self.refreshInstalled()
                let waiters = self.kernelWaiters
                self.kernelWaiters = []
                waiters.forEach { $0(ok) }
            }
        }
    }

    private func allowAction() -> Bool {
        if Date().timeIntervalSince(lastActionTime) < settleWindow {
            append("ui: bỏ qua thao tác quá nhanh (chống bấm nhầm)")
            return false
        }
        return true
    }

    // MARK: - INJECT: wait for kernel (or join it), install patch, open game

    func inject() {
        guard !busy, !restoring, allowAction() else { return }
        guard let patch = bundledPatch else {
            showToast(tr("Không tìm thấy gói cài đặt trong app.", "Package not found in the app."))
            return
        }
        let game = self.game
        cancelRequested = false
        busy = true
        phase = .running
        statusText = kernelDone ? "Đang inject…" : "Chờ một chút rồi inject…"
        if kernelInFlight {
            append("inject: kernel đang chạy — sẽ cài ngay khi xong")
        }

        ensureKernel { [weak self] ok in
            guard let self else { return }
            if self.cancelRequested {
                self.busy = false
                self.phase = .idle
                self.statusText = "Đã huỷ inject"
                self.append("inject: đã huỷ theo yêu cầu")
                self.lastActionTime = Date()
                return
            }
            guard ok || Installer.hasAccess(to: game) else {
                self.busy = false
                self.phase = .failed
                self.statusText = "Có lỗi — thử lại nhé"
                self.append("inject: kernel chưa sẵn sàng, huỷ inject")
                self.showToast(self.tr("Chưa sẵn sàng — chờ vài giây rồi thử lại nhé.", "Not ready yet — try again in a few seconds."))
                self.lastActionTime = Date()
                return
            }
            self.writeConfig()
            self.append("inject: kernel sẵn sàng → cài \(patch.name) vào \(game.title)")
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Installer.install(patch: patch.url, into: game)
                DispatchQueue.main.async {
                    if !result.ok {
                        self.busy = false
                        self.phase = .failed
                        self.statusText = "Inject lỗi"
                        self.append("inject: " + result.message)
                        self.showToast(result.message)
                        self.refreshInstalled()
                        self.lastActionTime = Date()
                        return
                    }
                    self.append("inject: " + result.message)
                    self.refreshInstalled()
                    self.statusText = "Đã cài — chuẩn bị mở game…"

                    // short window where HỦY still works; cancelling late
                    // rolls the fresh patch back instead of launching
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        self.busy = false
                        self.lastActionTime = Date()
                        if self.cancelRequested {
                            let rb = Installer.restore(game: game)
                            self.phase = .idle
                            self.statusText = "Đã huỷ — đã gỡ xong"
                            self.append("inject: huỷ muộn → gỡ patch vừa cài (" + rb.message + ")")
                            self.refreshInstalled()
                            return
                        }
                        self.phase = .active
                        self.statusText = "Đã inject — đang mở game"
                        self.launchGame()
                    }
                }
            }
        }
    }

    /// User tapped the button while inject is running: stop waiting / skip launch.
    func cancelInject() {
        guard busy else { return }
        cancelRequested = true
        statusText = "Đang huỷ…"
        append("inject: người dùng bấm huỷ")
    }

    /// Opens the game with the same private API Delta Proxy uses.
    func launchGame() {
        let game = self.game
        let ok = BolaLaunchApp(game.rawValue)
        append("launch: \(game.title) -> \(ok ? "đã gửi lệnh mở game" : "KHÔNG mở được")")
        if !ok {
            showToast(tr("Đã cài xong nhưng không mở được game — mở \(game.title) bằng tay giúp mình.",
                         "Installed, but the game didn't open — please open \(game.title) manually."))
        }
    }

    // MARK: - installed patch state

    func refreshInstalled() {
        installedInfo = Installer.installedPatchInfo(for: game)
        patchInstalled = Installer.patchExists(for: game)
    }

    func restore() {
        guard !busy, allowAction() else { return }
        let game = self.game
        restoring = true
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Installer.restore(game: game)
            DispatchQueue.main.async {
                guard let self else { return }
                self.restoring = false
                self.busy = false
                self.lastActionTime = Date()
                self.append("restore: " + result.message)
                self.showToast(result.message)
                self.refreshInstalled()
            }
        }
    }

    // MARK: - settings actions

    /// Removes caches + temp files created by the app.
    func clearCache() {
        let fm = FileManager.default
        var freed: UInt64 = 0
        let targets = [fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
                       fm.temporaryDirectory].compactMap { $0 }
        for dir in targets {
            guard let items = try? fm.contentsOfDirectory(at: dir,
                                                          includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for item in items {
                let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { UInt64($0) } ?? 0
                if (try? fm.removeItem(at: item)) != nil {
                    freed += size
                }
            }
        }
        append("cache: đã xoá \(freed) bytes")
        showToast(tr("Đã xoá bộ nhớ đệm (\(freed / 1024) KB).", "Cache cleared (\(freed / 1024) KB)."))
    }

    // MARK: - device pairing file (dropped into the app's Documents via Files)

    func refreshPairing() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        pairingName = nil
        pairingIdentifier = nil
        pairingValid = false
        guard let files = try? fm.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let sorted = files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return da > db
        }
        for f in sorted {
            let ext = f.pathExtension.lowercased()
            if ext == "mobiledevicepairing" || ext == "mobilepair" || ext == "plist" {
                if let data = try? Data(contentsOf: f),
                   let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] {
                    let pk = plist["public_key"] as? Data
                    let sk = plist["private_key"] as? Data
                    if pk != nil && sk != nil {
                        pairingName = f.lastPathComponent
                        pairingValid = true
                        if let pid = plist["identifier"] as? String {
                            pairingIdentifier = pid
                        } else if let udid = plist["UDID"] as? String {
                            pairingIdentifier = udid
                        }
                        return
                    }
                }
            }
        }
    }

    func removePairingFile() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
              let name = pairingName else { return }
        try? fm.removeItem(at: docs.appendingPathComponent(name))
        refreshPairing()
    }

    /// Generates the pairing file ON-DEVICE (connects to the device's own
    /// remotepairing service via LocalDevVPN at 10.7.0.1:49152).
    func generatePairingOnDevice() {
        guard !pairingBusy else { return }
        pairingBusy = true
        pairingPin = nil
        pairingNeedPin = false
        pairingStage = nil
        append("pairing: bắt đầu tạo trên máy…")
        if !PairingHost.vpnLoopbackPresent() {
            append("pairing: chưa thấy VPN (utun/10.7.x)")
            showToast(tr("Chưa thấy VPN — cần LocalDevVPN bật trước",
                         "VPN not detected — turn on LocalDevVPN first"))
        }
        PairingHost.onNeedPin = { [weak self] in
            guard let self = self else { return }
            self.pairingNeedPin = true
            self.append("pairing: máy đang hiện mã — nhập vào app")
            self.showToast(self.tr("Nhập mã đang hiện trên màn hình vào app",
                                   "Type the code shown on the screen into the app"))
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = PairingHost.generate(
                progress: { line in
                    DispatchQueue.main.async {
                        self?.append("pairing: " + line)
                        self?.pairingStage = line
                    }
                }
            )
            PairingHost.onNeedPin = nil
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pairingBusy = false
                self.pairingPin = nil
                self.pairingNeedPin = false
                self.pairingStage = nil
                switch result {
                case .success:
                    self.append("pairing: tạo xong")
                    self.showToast(self.tr("Đã tạo file ghép đôi", "Pairing file created"))
                case .failure(let err):
                    self.append("pairing: lỗi — " + err.message)
                    self.showToast(err.message)
                }
                self.refreshPairing()
            }
        }
    }

    /// The device is waiting for its on-screen code to be confirmed in-app.
    func submitPairingPin(_ pin: String) {
        pairingNeedPin = false
        PairingHost.submitPin(pin)
    }

    /// Stops a pending on-device pairing attempt.
    func cancelPairing() {
        PairingHost.cancel()
    }
}
