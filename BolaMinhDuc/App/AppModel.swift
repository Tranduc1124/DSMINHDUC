import Foundation
import Combine

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
    @Published var alertText: String?

    /// feature toggles shown in the app (pushed to the game live + persisted)
    static let cfgKeys = ["box", "line", "hp", "name", "dist", "bot", "fov"]

    @Published var cfgFlags: [String: Bool] = [:]
    @Published var fovRadius: Double = 18

    /// set when the user taps "HỦY INJECT" — skips install/launch at the next checkpoint
    private var cancelRequested = false

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
                d[k] = true
            }
        }
        cfgFlags = d
        let r = UserDefaults.standard.double(forKey: "bola_fovr")
        fovRadius = r == 0 ? 18 : r
    }

    var deviceInfo: String {
        ExploitRunner.versionDescription() + " • " + (ExploitRunner.isSupported() ? "hỗ trợ" : "chưa kiểm chứng")
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

    func setFovRadius(_ value: Double) {
        fovRadius = value
        UserDefaults.standard.set(value, forKey: "bola_fovr")
    }

    // MARK: - binary config (app -> game)
    //
    // bolacfg.bin = 16 obfuscated payload bytes + 4-byte CRC32 (little endian).
    // payload: "BOLA" | ver=1 | flags | fov% | 0...
    // flags bits: 0 box, 1 line, 2 hp, 3 name, 4 dist, 5 bot, 6 fov.
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
        if flag("fov")  { flags |= 64 }
        payload[5] = flags
        payload[6] = UInt8(max(5, min(45, Int(fovRadius.rounded()))))
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
            statusText = "Đã có quyền truy cập — không cần chạy kernel"
            append("auto: đã truy cập được thư mục game → bỏ qua kernel (an toàn hơn)")
            refreshInstalled()
            writeConfig()
            return
        }

        // no access yet → run the exploit in the background
        append("auto: mở app → chạy exploit ở nền")
        ensureKernel { _ in }
    }

    /// manual retry: clears the previous failure and runs again
    func rerunKernel() {
        guard !kernelInFlight else { return }
        kernelDone = false
        phase = .running
        statusText = "Đang chạy lại exploit…"
        busy = true
        ensureKernel { ok in
            self.busy = false
            self.phase = ok ? .active : .failed
            self.statusText = ok ? "Kernel OK — bấm INJECT" : "Kernel lỗi — thử lại"
        }
    }

    private func startKernelRun() {
        kernelInFlight = true
        phase = .running
        statusText = "Kernel đang chạy nền…"
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
                self.statusText = ok ? "Kernel OK — bấm INJECT" : "Kernel lỗi — thử lại"
                self.refreshInstalled()
                let waiters = self.kernelWaiters
                self.kernelWaiters = []
                waiters.forEach { $0(ok) }
            }
        }
    }

    // MARK: - INJECT: wait for kernel (or join it), install patch, open game

    func inject() {
        guard !busy else { return }
        guard let patch = bundledPatch else {
            alertText = "Không tìm thấy patch trong app."
            return
        }
        let game = self.game
        cancelRequested = false
        busy = true
        phase = .running
        statusText = kernelDone ? "Đang inject…" : "Chờ kernel (đang chạy) rồi inject…"
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
                return
            }
            guard ok || Installer.hasAccess(to: game) else {
                self.busy = false
                self.phase = .failed
                self.statusText = "Kernel lỗi — bấm Chạy lại exploit"
                self.append("inject: kernel chưa sẵn sàng, huỷ inject")
                self.alertText = "Kernel chưa sẵn sàng — chờ vài giây rồi bấm INJECT lại."
                return
            }
            self.writeConfig()
            self.append("inject: kernel sẵn sàng → cài \(patch.name) vào \(game.title)")
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Installer.install(patch: patch.url, into: game)
                DispatchQueue.main.async {
                    self.busy = false
                    self.phase = .active
                    self.append("inject: " + result.message)
                    self.refreshInstalled()
                    if result.ok && !self.cancelRequested {
                        self.statusText = "Đã inject — đang mở game"
                        self.launchGame()
                    } else if result.ok {
                        self.statusText = "Đã cài patch (chưa mở game)"
                        self.append("inject: đã huỷ mở game theo yêu cầu")
                    } else {
                        self.statusText = "Inject lỗi"
                        self.alertText = result.message
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
            alertText = "Đã cài patch nhưng không mở được game — mở \(game.title) bằng tay giúp mình."
        }
    }

    // MARK: - installed patch state

    func refreshInstalled() {
        installedInfo = Installer.installedPatchInfo(for: game)
        patchInstalled = Installer.patchExists(for: game)
    }

    func restore() {
        guard !busy else { return }
        let game = self.game
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Installer.restore(game: game)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.append("restore: " + result.message)
                self.alertText = result.message
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
        alertText = "Đã xoá bộ nhớ đệm (\(freed / 1024) KB)."
    }
}
