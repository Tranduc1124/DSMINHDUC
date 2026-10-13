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
                          "emote"]

    @Published var cfgFlags: [String: Bool] = [:]
    @Published var aimBone: Int = 0
    @Published var silentFov: Int = 30
    /// FOV riêng của Aimbot (% chiều cao màn hình)
    @Published var aimFov: Int = 30
    /// Tỉ lệ silent vào ĐẦU khi chọn Head (%)
    @Published var headRate: Int = 100
    @Published var camFov: Int = 88
    @Published var espThick: Int = 100

    /// "vi" or "en" -- in-app language
    @Published var language: String = UserDefaults.standard.string(forKey: "bola_lang") ?? "vi"

    /// anti-ban V2 (kiểu INNOVA): flood ~95k file bảo vệ + dọn 1 lần.
    @Published var antiban: Bool = false
    @Published var antiPreparing: Bool = false
    @Published var antiFloodReady: Bool = false
    @Published var antiSheetVisible: Bool = false
    @Published var antiPercent: Int = 0

    /// ===== UID game (kích hoạt theo tài khoản — kiểu DELTA) =====
    @Published var uidInput: String = ""
    @Published var uidActive: String? = UserDefaults.standard.string(forKey: "bola_uid_active")
    @Published var uidSwitchesLeft: Int = -1
    @Published var uidBusy: Bool = false

    /// true when MobileHouseArrest granted container access (no kernel needed)
    @Published var mhaActive: Bool = false
    /// Đã THỰC SỰ ghi được file vào game chưa (probe thật — không đoán)
    @Published var writeOK: Bool = false

    // MARK: license key bar (DEMO — real key system later)

    /// masked key name shown on the home key bar (demo placeholder)
    @Published var keyMaskedName: String = ""
    /// giờ còn lại THẬT của key (-1 = chưa biết, lấy từ lease SDK)
    @Published var keyHoursLeft: Int = -1

    /// set when the user taps "HỦY INJECT" — skips install/launch at the next checkpoint
    private var cancelRequested = false


    /// anti double-tap: ignore INJECT/RESTORE right after any completed action
    private var lastActionTime = Date.distantPast
    private var keyCardTimer: Timer?
    private let settleWindow: TimeInterval = 1.2

    // MARK: kernel single-flight state (main-thread only)

    private var didBootstrap = false
    private var didUploadDebug = false
    private var kernelInFlight = false
    private var kernelDone = false
    private var kernelWaiters: [(Bool) -> Void] = []

    init() {
        var d: [String: Bool] = [:]
        let offByDefault: Set<String> = ["aim", "silent", "skipknock", "straight",
                                         "fastfire", "buffdame", "fastreload", "fastswap", "nograss",
                                         "nofog", "highjump", "fps144", "chams", "spin360",
                                         "fastcrouch", "fastloot", "backjump", "speedrun", "camwide",
                                         "emote"]
        for k in AppModel.cfgKeys {
            if let v = UserDefaults.standard.object(forKey: "bola_cfg_" + k) as? Bool {
                d[k] = v
            } else {
                d[k] = !offByDefault.contains(k)
            }
        }
        cfgFlags = d
        antiban = false
        antiPreparing = false
        antiFloodReady = false
        if let a = uidActive { uidInput = a }
        aimBone = UserDefaults.standard.integer(forKey: "bola_bone")
        let storedFov = UserDefaults.standard.object(forKey: "bola_fov") as? Int
        if let f = storedFov, f >= 5 && f <= 100 {
            silentFov = f
        }
        let storedAimFov = UserDefaults.standard.object(forKey: "bola_aimfov") as? Int
        if let f = storedAimFov, f >= 5 && f <= 100 {
            aimFov = f
        }
        let storedHeadRate = UserDefaults.standard.object(forKey: "bola_headrate") as? Int
        if let h = storedHeadRate, h >= 10 && h <= 100 {
            headRate = h
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

    func setAimFov(_ value: Int) {
        var v = value
        if v < 5 { v = 5 }
        if v > 100 { v = 100 }
        aimFov = v
        UserDefaults.standard.set(v, forKey: "bola_aimfov")
        writeConfig()
    }

    func setHeadRate(_ value: Int) {
        var v = value
        if v < 10 { v = 10 }
        if v > 100 { v = 100 }
        headRate = v
        UserDefaults.standard.set(v, forKey: "bola_headrate")
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
        var payload = [UInt8](repeating: 0, count: 24)
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
        if flag("fastswap") { n1 |= 8 }
        if flag("emote") { n1 |= 32 }
        if flag("highjump") { n1 |= 64 }
        if flag("fps144") { n1 |= 128 }
        payload[16] = n1
        var n2: UInt8 = 0
        if flag("camwide") { n2 |= 2 }
        if flag("backjump") { n2 |= 16 }
        if flag("speedrun") { n2 |= 32 }
        payload[17] = n2
        payload[18] = UInt8(max(50, min(130, camFov)))
        payload[19] = UInt8(max(5, min(100, aimFov)))
        payload[20] = UInt8(max(10, min(100, headRate)))
        for i in 0..<24 {
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

        // anti-ban đã gỡ theo yêu cầu (sẽ làm lại bản mới sau)

        // tự hồi .bola_tok nếu patch trong game khớp key hiện tại
        // (trường hợp token bị xoá thủ công — không cần inject lại)
        selfHealToken()

        // OTA patch: silently fetch the newest bytes from the repo so patch
        // fixes apply without reinstalling the app.
        refreshPatchRemote()

        // Tự gửi báo cáo chẩn đoán lên server (im lặng — admin đọc trực tiếp,
        // người dùng không cần tìm file / share gì cả).
        scheduleDebugUploadIfNeeded()

        // card KEY ở Home: nạp giá trị THẬT (mask + giờ còn lại) và tự
        // cập nhật mỗi phút.
        refreshKeyCard()
        if keyCardTimer == nil {
            keyCardTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.refreshKeyCard()
            }
        }

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

    /// Card KEY ở Home: mask THẬT (từ SDK) + giờ còn lại THẬT (từ lease SDK).
    func refreshKeyCard() {
        let k = LicenseGate.shared.licenseKey
        if !k.isEmpty { keyMaskedName = k }
        let exp = LicenseGate.shared.leaseExpiryUnix
        if exp > 0 {
            let secs = exp - Int(Date().timeIntervalSince1970)
            keyHoursLeft = secs > 0 ? (secs + 3599) / 3600 : 0
        }
    }

    /// Tự hồi .bola_tok trong container game (nếu patch đang cài khớp key).
    private func selfHealToken() {
        let g = game
        DispatchQueue.global(qos: .utility).async {
            if Installer.hasAccess(to: g) {
                _ = Installer.resyncTokenIfNeeded(for: g)
            }
        }
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
        if antiban && antiPreparing {
            showToast(tr("🛡️ Anti đang bật — chờ chút rồi INJECT nhé!",
                         "🛡️ Anti-ban is enabling — wait a bit then INJECT!"))
            append("inject: chờ anti chuẩn bị")
            return
        }
        // kill-switch server: bản đã ngừng hoạt động → không cho inject
        guard !VersionGate.shared.blocked else {
            showToast(tr("⛔ Bản này đã ngừng hoạt động.",
                         "⛔ This build has been stopped."))
            append("inject: bản đã bị server kill")
            return
        }
        guard let patch = bundledPatch else {
            showToast(tr("Patch chưa sẵn sàng — kiểm tra mạng + key rồi mở lại app.",
                         "Patch not ready — check network + key, then reopen the app."))
            append("inject: chưa có patch cá nhân hoá hợp lệ")
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
        // Tương tích CHỈ "Tốt" khi viết THẬT được file vào máy game.
        let g = game
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let ok = Installer.canWriteIntoGame(g)
            DispatchQueue.main.async {
                self?.writeOK = ok
            }
        }
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

    /// Reset Guest: forces `Documents/localConfig.json` ({"testCodePatch":
    /// true,"resetGuest":true}) into both game containers - the game reads
    /// the flag on next launch and resets its guest account.
    func resetGuest() {
        let n = Antiban.resetGuest()
        append("reset guest: đã đặt cờ localConfig.json vào \(n) container")
        showToast(n > 0
            ? tr("🧹 Đã đặt cờ reset guest — tắt hẳn game rồi MỞ LẠI để reset!",
                 "🧹 Guest reset flag written — force-close the game and RELAUNCH it!")
            : tr("Không ghi được — mở game 1 lần (để tạo container) rồi thử lại",
                 "Could not write — launch the game once (container must exist) then retry"))
    }

    func setAntiban(_ value: Bool) {
        if value && LicenseGate.shared.state != .authorized {
            showToast(tr("🔑 Nhập key xong rồi mới bật được Anti-ban nhé!",
                         "🔑 Activate your key before enabling Anti-ban!"))
            return
        }
        antiban = value
        if value {
            antiSheetVisible = true
            antiPercent = 0
            append("antiban: ON")
            DispatchQueue.global(qos: .utility).async { [weak self] in
                _ = Antiban.cleanAll(since: nil)
                _ = GameUID.wipeSession()
                // Đã có sẵn đủ file từ lần trước? → bật xong NGAY. Đếm file
                // chạy NỀN (95k entry) nên UI không bị treo khi bấm.
                if Antiban.floodDone() {
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.antiPreparing = false
                        self.antiFloodReady = true
                        self.antiPercent = 100
                        self.append("antiban: sẵn sàng ✓")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            if self?.antiban == true { self?.antiSheetVisible = false }
                        }
                    }
                    return
                }
                DispatchQueue.main.async {
                    self?.antiPreparing = true
                    self?.antiFloodReady = false
                }
                Antiban.prepareFlood(progress: { cur, total in
                    let pct = min(99, cur * 100 / max(1, total))
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if pct != self.antiPercent {
                            self.antiPercent = pct
                            if pct % 10 == 0 {
                                self.append("antiban: đang chuẩn bị… \(pct)%")
                            }
                        }
                    }
                }, done: { _ in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.antiPreparing = false
                        self.antiFloodReady = true
                        self.antiPercent = 100
                        self.append("antiban: sẵn sàng ✓")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            if self.antiban { self.antiSheetVisible = false }
                        }
                    }
                })
            }
            return
        }
        antiSheetVisible = false
        antiPreparing = false
        antiFloodReady = false
        antiPercent = 0
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            _ = Antiban.removeDecoys()
            var removed: [String] = []
            for g in GameTarget.allCases where Installer.patchExists(for: g) {
                _ = Installer.restore(game: g)
                removed.append(g.title)
            }
            DispatchQueue.main.async {
                self.append("antiban: đã tắt · file bảo vệ giữ nguyên (bật lại là xong ngay)" + (removed.isEmpty ? "" : " · gỡ patch " + removed.joined(separator: ", ")))
                if !removed.isEmpty {
                    self.showToast(self.tr("Đã tắt Anti-ban", "Anti-ban off"))
                }
                self.refreshInstalled()
            }
        }
    }

    /// Tự dò UID từ dữ liệu game rồi điền vào ô nhập (nút 🔍 "Lấy UID").
    func detectUID() {
        guard !uidBusy else { return }
        uidBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let hit = GameUID.detectFirst()
            DispatchQueue.main.async {
                guard let self else { return }
                self.uidBusy = false
                if let hit {
                    self.uidInput = hit.uid
                    self.append("uid: dò thấy \(hit.uid) (\(hit.source))")
                    self.showToast(self.tr("🔍 Đã lấy UID \(hit.uid) — bấm KÍCH HOẠT nhé!",
                                           "🔍 UID \(hit.uid) detected — tap ACTIVATE!"))
                } else {
                    self.append("uid: không dò thấy trong dữ liệu game — nhập tay")
                    self.showToast(self.tr("🔍 Không thấy UID trong dữ liệu game — nhập tay nhé",
                                           "🔍 No UID found in game data — enter it manually"))
                }
            }
        }
    }

    /// Bật anti-ban mà thiếu UID: tự dò rồi kích hoạt luôn.
    private func detectAndActivateUID() {
        guard !uidBusy else { return }
        uidBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let hit = GameUID.detectFirst()
            DispatchQueue.main.async {
                guard let self else { return }
                self.uidBusy = false
                if let hit {
                    self.uidInput = hit.uid
                    self.append("uid: tự dò thấy \(hit.uid) (\(hit.source)) — kích hoạt…")
                    self.activateUID(hit.uid)
                } else {
                    self.append("uid: không dò thấy — chờ nhập tay")
                    self.showToast(self.tr("🔍 Không dò thấy UID — nhập UID vào ô rồi bấm KÍCH HOẠT",
                                           "🔍 No UID detected — enter UID then tap ACTIVATE"))
                }
            }
        }
    }

    /// Kích hoạt UID với server (theo dõi lượt/ngày kiểu DELTA). Thành công
    /// thì ghi .bola_uid vào container game để patch trong game đối chiếu.
    func activateUID(_ uid: String? = nil) {
        guard !uidBusy else { return }
        if LicenseGate.shared.state != .authorized {
            showToast(tr("🔑 Nhập key trước đã!", "🔑 Activate your key first!"))
            return
        }
        let target = (uid ?? uidInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            showToast(tr("Nhập UID trước đã.", "Enter UID first."))
            return
        }
        guard target.range(of: "^[0-9]{4,18}$", options: .regularExpression) != nil else {
            showToast(tr("UID chỉ gồm chữ số (4–18 số).", "UID must be digits (4–18)."))
            return
        }
        uidBusy = true
        PatchClient.uidActivate(license: LicenseGate.shared.licenseKey,
                                device: ServerConfig.deviceId, uid: target) { [weak self] j in
            guard let self else { return }
            self.uidBusy = false
            if (j["ok"] as? Bool) ?? false {
                let already = (j["alreadyActive"] as? Bool) ?? false
                self.uidInput = target
                self.uidActive = target
                UserDefaults.standard.set(target, forKey: "bola_uid_active")
                if let left = j["switchesLeft"] as? Int { self.uidSwitchesLeft = left }
                let n = GameUID.write(target)
                let leftTxt = self.uidSwitchesLeft >= 0
                    ? self.tr(" · còn \(self.uidSwitchesLeft) lượt hôm nay",
                              " · \(self.uidSwitchesLeft) left today")
                    : ""
                self.append("uid: \(already ? "đang bảo vệ" : "kích hoạt") \(target) → ghi \(n) container\(leftTxt)")
                self.showToast(already
                    ? self.tr("✅ UID \(target) đang bảo vệ — mở lại game để chơi",
                              "✅ UID \(target) is protected — reopen the game")
                    : self.tr("✅ Đã kích hoạt UID \(target)\(leftTxt) — mở lại game để chơi!",
                              "✅ UID \(target) activated\(leftTxt) — reopen the game!"))
            } else {
                let msg = (j["message"] as? String)
                    ?? self.tr("Xác thực thất bại, thử lại.", "Verification failed, try again.")
                self.append("uid: kích hoạt thất bại — " + msg)
                self.showToast("⚠️ " + msg)
            }
        }
    }

    /// Xoá UID hiện tại (trong app). Muốn đổi sang UID mới thì BẮT BUỘC bấm
    /// nút này trước, rồi mới nhập + kích hoạt UID mới được.
    func clearUID() {
        uidActive = nil
        uidInput = ""
        uidSwitchesLeft = -1
        UserDefaults.standard.removeObject(forKey: "bola_uid_active")
        let n = GameUID.remove()
        append("uid: đã xoá UID hiện tại (gỡ .bola_uid ở \(n) container)")
        showToast(tr("🗑️ Đã xoá UID hiện tại — nhập UID mới để kích hoạt lại",
                     "🗑️ Current UID removed — enter a new UID to activate"))
    }

    /// Đổi tài khoản: xoá phiên đăng nhập (session/cookie) như DELTA logout.
    func gameLogout() {
        let n = GameUID.wipeSession()
        append("logout: đã xoá session data (\(n) mục) — game sẽ yêu cầu đăng nhập lại")
        showToast(tr("🚪 Đã xoá phiên đăng nhập (\(n) mục) — mở game đăng nhập tài khoản khác",
                     "🚪 Session wiped (\(n) item(s)) — reopen the game to sign in"))
    }

    // MARK: - debug report (gửi admin khi patch "không chạy")

    /// Gom toàn bộ thông tin chẩn đoán: patch đang dùng, file trong từng
    /// container game (.bola_tok / .bola_uid / patch bytes / .bola_dbg.txt).
    func collectDebugReport() -> String {
        var out = "=== \(AppBrand.name) DEBUG \(DeviceInfo.appVersion) ===\n"
        out += "ios: \(DeviceInfo.iosVersion) | \(DeviceInfo.machine)\n"
        out += "key: \(keyMaskedName) | state: \(String(describing: LicenseGate.shared.state))\n"
        out += "uidActive: \(uidActive ?? "-")\n"
        let cache = PatchLibrary.remoteCacheURL
        if let data = try? Data(contentsOf: cache), data.count > 4096 {
            let sha = PatchClient.sha256(data).map { String(format: "%02x", $0) }.joined().prefix(16)
            out += "patch(server-cache): size=\(data.count) sha16=\(sha)\n"
        } else {
            out += "patch(server-cache): MISSING\n"
        }
        let fm = FileManager.default
        for g in GameTarget.allCases {
            out += "\n=== \(g.title) (\(g.rawValue)) ===\n"
            guard let container = Installer.containerPath(for: g.rawValue) else {
                out += "(khong truy cap duoc container)\n"
                continue
            }
            let docs = container + "/Documents"
            out += "tok: \(fm.fileExists(atPath: docs + "/.bola_tok") ? "co" : "KHONG")"
            out += " | uid-file: \(fm.fileExists(atPath: docs + "/.bola_uid") ? "co" : "KHONG")"
            let uidv = (try? String(contentsOfFile: docs + "/.bola_uid", encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "-"
            out += " | uid=\(uidv)\n"
            if let pd = fm.contents(atPath: docs + "/Assembly-CSharp-patch.bytes"), pd.count > 128 {
                let psha = PatchClient.sha256(pd).map { String(format: "%02x", $0) }.joined().prefix(16)
                out += "patch-in-game: size=\(pd.count) sha16=\(psha)\n"
            } else {
                out += "patch-in-game: KHONG\n"
            }
            if let dbg = fm.contents(atPath: docs + "/.bola_dbg.txt"),
               let s = String(data: dbg, encoding: .utf8) {
                let lines = s.split(separator: "\n").suffix(60)
                out += "--- .bola_dbg.txt (last \(lines.count)) ---\n"
                out += lines.joined(separator: "\n") + "\n"
            } else {
                out += ".bola_dbg.txt: KHONG CO (patch chua chay?)\n"
            }
            // danh sách file + mtime: biết game có chạy sau khi inject không
            // (file trong container game đổi mtime mỗi lần game mở).
            out += "docs-list:\n" + dirListing(docs, limit: 60)
            out += "library-list:\n" + dirListing(container + "/Library", limit: 50)
            out += "caches-list:\n" + dirListing(container + "/Library/Caches", limit: 40)
            out += "prefs-list:\n" + dirListing(container + "/Library/Preferences", limit: 40)
            out += "--- log hunt ---\n" + huntGameLogs(container)
        }
        if out.count > 55000 { out = String(out.prefix(55000)) + "\n...(het)\n" }
        return out
    }

    /// Liệt kê 1 thư mục (tên + size + mtime) — kèm cả file ẩn.
    private func dirListing(_ path: String, limit: Int = 60) -> String {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else {
            return "  (khong doc duoc)\n"
        }
        let df = DateFormatter()
        df.dateFormat = "dd HH:mm"
        var out = ""
        var shown = 0
        for it in items {
            if shown >= limit {
                out += "  ...(+\(items.count - limit) muc nua)\n"
                break
            }
            let p = path + "/" + it
            let attrs = try? fm.attributesOfItem(atPath: p)
            let isDir = (attrs?[.type] as? FileAttributeType) == .typeDirectory
            let size = (attrs?[.size] as? Int) ?? 0
            let mt = (attrs?[.modificationDate] as? Date).map { df.string(from: $0) } ?? "-"
            out += "  \(isDir ? "d" : "f") \(it.prefix(70)) \(isDir ? "" : "\(size)B") \(mt)\n"
            shown += 1
        }
        return out
    }

    /// Tìm log nội bộ của game (IFix/Unity/Garena/Crash) — lấy file mới nhất,
    /// đọc đuôi file để thấy lý do patch bị từ chối (nếu có).
    private func huntGameLogs(_ container: String, maxFiles: Int = 4, maxLines: Int = 30) -> String {
        let fm = FileManager.default
        var found: [(String, Date, Int)] = []
        let dirs = [container + "/Documents", container + "/Library",
                    container + "/Library/Caches", container + "/Library/Logs",
                    container + "/tmp"]
        for d in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: d) else { continue }
            for it in items {
                let low = it.lowercased()
                let isLog = low.hasSuffix(".log") || low.contains("log") || low.contains("ifix")
                    || low.contains("player") || low.contains("crash") || low.contains("garena")
                guard isLog else { continue }
                let p = d + "/" + it
                guard let attrs = try? fm.attributesOfItem(atPath: p),
                      (attrs[.type] as? FileAttributeType) == .typeRegular,
                      let size = attrs[.size] as? Int, size > 0, size < 30_000_000 else { continue }
                let mt = (attrs[.modificationDate] as? Date) ?? .distantPast
                found.append((p, mt, size))
            }
        }
        found.sort { $0.1 > $1.1 }
        var out = ""
        for f in found.prefix(maxFiles) {
            out += "--- \(String(f.0.dropFirst(container.count))) (\(f.2)B) ---\n"
            if let h = FileHandle(forReadingAtPath: f.0) {
                defer { try? h.close() }
                if let end = try? h.seekToEnd(), end > 0 {
                    let start = end > UInt64(20_000) ? end - 20_000 : 0
                    try? h.seek(toOffset: start)
                    let data = (try? h.readToEnd()) ?? Data()
                    let text = String(data: data, encoding: .utf8)
                        ?? String(decoding: data, as: UTF8.self)
                    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(maxLines)
                    for ln in lines { out += String(ln.prefix(140)) + "\n" }
                }
            }
        }
        return out.isEmpty ? "(khong co file log)\n" : out
    }

    /// Mở share sheet để gửi báo cáo debug (Zalo/Telegram...).
    func shareDebugReport() {
        append("debug: đang gom báo cáo…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let report = self.collectDebugReport()
            DispatchQueue.main.async {
                self.append("debug: xong (\(report.count) ký tự) — mở chia sẻ")
                let av = UIActivityViewController(activityItems: [report], applicationActivities: nil)
                if let scene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                   let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    var top = root
                    while let p = top.presentedViewController { top = p }
                    if let pop = av.popoverPresentationController {
                        pop.sourceView = top.view
                        pop.sourceRect = CGRect(x: top.view.bounds.midX,
                                                y: top.view.bounds.midY, width: 0, height: 0)
                    }
                    top.present(av, animated: true)
                } else {
                    self.showToast(self.tr("Không mở được chia sẻ — thử lại nhé",
                                           "Could not open share sheet — try again"))
                }
            }
        }
    }

    /// Lên lịch tự gửi báo cáo debug 1 lần mỗi lần mở app (chờ patch tải xong).
    private func scheduleDebugUploadIfNeeded() {
        guard !didUploadDebug else { return }
        didUploadDebug = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.uploadDebugReport()
        }
    }

    /// Gom + gửi báo cáo lên server (nền). Thất bại thì im lặng bỏ qua.
    private func uploadDebugReport() {
        let lic = LicenseGate.shared.licenseKey
        guard !lic.isEmpty else { return }
        let dev = ServerConfig.deviceId
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let report = self.collectDebugReport()
            PatchClient.debugUpload(license: lic, device: dev, report: report) { ok in
                DispatchQueue.main.async { [weak self] in
                    self?.append(ok ? "debug: báo cáo chẩn đoán đã gửi lên server ✓"
                                    : "debug: gửi báo cáo thất bại (bỏ qua)")
                }
            }
        }
    }


}
