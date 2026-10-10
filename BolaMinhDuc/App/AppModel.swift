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
    static let cfgKeys = ["box", "line", "bone", "hp", "name", "dist", "bot", "count", "aim", "silent", "skipknock", "showfov", "team", "straight",
                          "fastfire", "buffdame", "fastreload", "fastswap", "nograss", "nofog", "highjump", "fps144",
                          "chams", "spin360", "fastcrouch", "fastloot", "backjump", "speedrun", "camwide",
                          "fastpara", "emote"]

    @Published var cfgFlags: [String: Bool] = [:]
    @Published var aimBone: Int = 0
    @Published var silentFov: Int = 30
    @Published var camFov: Int = 88
    @Published var espThick: Int = 100

    /// "vi" or "en" -- in-app language
    @Published var language: String = UserDefaults.standard.string(forKey: "bola_lang") ?? "vi"

    /// anti-ban: continuous background cleanup of the game's telemetry caches
    /// (OFF by default - the user enables it explicitly)
    @Published var antiban: Bool = false

    /// true when MobileHouseArrest granted container access (no kernel needed)
    @Published var mhaActive: Bool = false

    // MARK: license key bar (DEMO — real key system later)

    /// masked key name shown on the home key bar (demo placeholder)
    @Published var keyMaskedName: String = "BOLA-••••-9C41"
    /// hours left on the key (demo placeholder)
    @Published var keyHoursLeft: Int = 72

    /// set when the user taps "HỦY INJECT" — skips install/launch at the next checkpoint
    private var cancelRequested = false

    /// anti double-tap: ignore INJECT/RESTORE right after any completed action
    private var lastActionTime = Date.distantPast
    private var antibanTimer: Timer?
    private let settleWindow: TimeInterval = 1.2

    // MARK: kernel single-flight state (main-thread only)

    private var didBootstrap = false
    private var kernelInFlight = false
    private var kernelDone = false
    private var kernelWaiters: [(Bool) -> Void] = []

    init() {
        var d: [String: Bool] = [:]
        let offByDefault: Set<String> = ["aim", "silent", "skipknock", "straight",
                                         "fastfire", "buffdame", "fastreload", "fastswap", "nograss",
                                         "nofog", "highjump", "fps144", "chams", "spin360",
                                         "fastcrouch", "fastloot", "backjump", "speedrun", "camwide",
                                         "fastpara", "emote"]
        for k in AppModel.cfgKeys {
            if let v = UserDefaults.standard.object(forKey: "bola_cfg_" + k) as? Bool {
                d[k] = v
            } else {
                d[k] = !offByDefault.contains(k)
            }
        }
        cfgFlags = d
        if let ab = UserDefaults.standard.object(forKey: "bola_antiban") as? Bool {
            antiban = ab
        }
        aimBone = UserDefaults.standard.integer(forKey: "bola_bone")
        let storedFov = UserDefaults.standard.object(forKey: "bola_fov") as? Int
        if let f = storedFov, f >= 5 && f <= 100 {
            silentFov = f
        }
        let storedCamFov = UserDefaults.standard.object(forKey: "bola_camfov") as? Int
        if let cf = storedCamFov, cf >= 50 && cf <= 130 {
            camFov = cf
        }
        let storedThick = UserDefaults.standard.object(forKey: "bola_thick") as? Int
        if let t = storedThick, t >= 50 && t <= 200 {
            espThick = t
        }
    }

    /// The patch to inject: the newest one available (OTA download from the
    /// repo when present, otherwise the payload bundled in the app).
    var bundledPatch: PatchFile? {
        PatchLibrary.latest()
    }

    // MARK: - feature flags

    func flag(_ key: String) -> Bool {
        cfgFlags[key] ?? true
    }

    func setFlag(_ key: String, _ value: Bool) {
        cfgFlags[key] = value
        UserDefaults.standard.set(value, forKey: "bola_cfg_" + key)
        // aimbot vs silent aim: only one can be on
        if value && key == "aim" {
            cfgFlags["silent"] = false
            UserDefaults.standard.set(false, forKey: "bola_cfg_silent")
        }
        if value && key == "silent" {
            cfgFlags["aim"] = false
            UserDefaults.standard.set(false, forKey: "bola_cfg_aim")
        }
        writeConfig()
    }

    func setBone(_ value: Int) {
        aimBone = value
        UserDefaults.standard.set(value, forKey: "bola_bone")
        writeConfig()
    }

    func setSilentFov(_ value: Int) {
        var v = value
        if v < 5 { v = 5 }
        if v > 100 { v = 100 }
        silentFov = v
        UserDefaults.standard.set(v, forKey: "bola_fov")
        writeConfig()
    }

    func setCamFov(_ value: Int) {
        var v = value
        if v < 50 { v = 50 }
        if v > 130 { v = 130 }
        camFov = v
        UserDefaults.standard.set(v, forKey: "bola_camfov")
        writeConfig()
    }

    func setEspThick(_ value: Int) {
        var v = value
        if v < 50 { v = 50 }
        if v > 200 { v = 200 }
        espThick = v
        UserDefaults.standard.set(v, forKey: "bola_thick")
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
    // bolacfg.bin = 20 obfuscated payload bytes + 4-byte CRC32 (little endian).
    // payload: "BOLA" | ver=1 | flags | - | 0...
    // flags bits: 0 box, 1 line, 2 hp, 3 name, 4 dist, 5 bot, 7 count.
    // byte 7: bit0 aim, bit1 skeleton bones, bit2 silent aim; byte 8: aim bone (0 head, 1 neck, 2 chest).
    // bytes 9..14: RGB565 box / line / bone colors (0 = default red).
    // byte 16: misc flags 1 (fastfire, buffdame, fastreload, fastswap, nograss, nofog, highjump, fps144).
    // byte 17: misc flags 2 (chams, spin360, fastcrouch, fastloot, backjump).
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
        var payload = [UInt8](repeating: 0, count: 20)
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
        if flag("skipknock") { extra |= 8 }
        if flag("showfov") { extra |= 16 }
        if flag("team") { extra |= 32 }
        if flag("straight") { extra |= 64 }
        payload[7] = extra
        payload[8] = UInt8(max(0, min(2, aimBone)))
        payload[6] = UInt8(max(50, min(200, espThick)))
        payload[15] = UInt8(max(5, min(100, silentFov)))
        let (c9, c10) = pack565("box")
        let (c11, c12) = pack565("line")
        let (c13, c14) = pack565("bone")
        payload[9] = c9
        payload[10] = c10
        payload[11] = c11
        payload[12] = c12
        payload[13] = c13
        payload[14] = c14
        var n1: UInt8 = 0
        if flag("fastfire") { n1 |= 1 }
        if flag("buffdame") { n1 |= 2 }
        if flag("fastreload") { n1 |= 4 }
        if flag("fastswap") { n1 |= 8 }
        if flag("fastpara") { n1 |= 16 }
        if flag("emote") { n1 |= 32 }
        if flag("highjump") { n1 |= 64 }
        if flag("fps144") { n1 |= 128 }
        payload[16] = n1
        var n2: UInt8 = 0
        if flag("camwide") { n2 |= 2 }
        if flag("fastcrouch") { n2 |= 4 }
        if flag("fastloot") { n2 |= 8 }
        if flag("backjump") { n2 |= 16 }
        if flag("speedrun") { n2 |= 32 }
        payload[17] = n2
        payload[18] = UInt8(max(50, min(130, camFov)))
        for i in 0..<20 {
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
        if antiban {
            startAntibanLoop()
        }

        // OTA patch: silently fetch the newest bytes from the repo so patch
        // fixes apply without reinstalling the app.
        refreshPatchRemote()

        // MobileHouseArrest fast path: when the app was signed with the MHA
        // identity this grants container access with no kernel exploit and
        // works on iOS 16 (where the kernel offsets are missing).
        attemptMHA()

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
}

// MARK: - anti-ban loop

extension AppModel {
    /// OTA patch refresh: downloads the newest bytes from the GitHub repo.
    /// On success the next INJECT uses them; on any failure the bundled
    /// payload is used as before.
    func refreshPatchRemote() {
        PatchLibrary.refreshRemote { [weak self] n in
            guard let self else { return }
            if n > 0 {
                self.append("patch: đã tải patch mới từ GitHub (\(n) bytes)")
            } else {
                self.append("patch: dùng bản trong app (không tải được OTA)")
            }
        }
    }

    /// Tries to open both game containers through MobileHouseArrest.
    private func attemptMHA() {
        let th = mha_open_container(GameTarget.freefireTH.rawValue)
        let mx = mha_open_container(GameTarget.freefireMAX.rawValue)
        if th >= 0 || mx >= 0 {
            mhaActive = true
            append("mha: đã mở container qua MobileHouseArrest — bỏ qua kernel")
        } else {
            mhaActive = false
            append("mha: không khả dụng (mã \(th)/\(mx)) — dùng kernel exploit")
        }
    }

    func setAntiban(_ value: Bool) {
        antiban = value
        UserDefaults.standard.set(value, forKey: "bola_antiban")
        if value {
            startAntibanLoop()
            showToast(tr("🛡️ Đã bật Anti-ban — tự dọn dấu vết liên tục (tắt sẽ tự gỡ patch)",
                         "🛡️ Anti-ban on — keeps wiping traces (turning off auto-removes the patch)"))
            return
        }
        // Turning anti-ban OFF while the patch is installed = instant
        // uninject: stop the cleanup loop and pull the patch out of every
        // game container it is in.
        antibanTimer?.invalidate()
        antibanTimer = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var removed: [String] = []
            for g in GameTarget.allCases where Installer.patchExists(for: g) {
                let rb = Installer.restore(game: g)
                removed.append(g.title)
                DispatchQueue.main.async {
                    self.append("antiban: tắt anti → tự gỡ patch \(g.title) (" + rb.message + ")")
                }
            }
            DispatchQueue.main.async {
                if !removed.isEmpty {
                    self.showToast(self.tr("Đã tắt Anti-ban → tự gỡ patch (\(removed.joined(separator: ", ")))",
                                           "Anti-ban off → patch removed (\(removed.joined(separator: ", ")))"))
                }
                self.refreshInstalled()
            }
        }
    }

    /// Continuous anti-ban: like the reference tool, keep wiping the game's
    /// telemetry caches in the background (works while the app is alive,
    /// including the background audio keep-alive).
    func startAntibanLoop() {
        guard antibanTimer == nil else { return }
        DispatchQueue.global(qos: .utility).async {
            Antiban.cleanAll()
        }
        antibanTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self, self.antiban else { return }
            guard self.kernelDone
                || Installer.hasAccess(to: GameTarget.freefireTH)
                || Installer.hasAccess(to: GameTarget.freefireMAX) else { return }
            DispatchQueue.global(qos: .utility).async {
                Antiban.cleanAll()
            }
        }
    }
}
