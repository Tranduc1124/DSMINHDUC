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
    @Published var logText = ""
    @Published var busy = false
    @Published var alertText: String?

    // MARK: kernel single-flight state (main-thread only)

    private var didBootstrap = false
    private var kernelInFlight = false
    private var kernelDone = false
    private var kernelWaiters: [(Bool) -> Void] = []

    var deviceInfo: String {
        ExploitRunner.versionDescription() + " • " + (ExploitRunner.isSupported() ? "hỗ trợ" : "chưa kiểm chứng")
    }

    /// The one patch bundled in the app — custom patches are not accepted.
    var bundledPatch: PatchFile? {
        PatchLibrary.bundled()
    }

    // MARK: - log

    func append(_ line: String) {
        logText += line + "\n"
        if logText.count > 80_000 {
            logText.removeFirst(20_000)
        }
    }

    // MARK: - kernel (single run; INJECT joins a run already in flight)

    /// Boot-scoped guard: the kernel exploit must not blindly re-run every
    /// time the app is reopened. Running it twice in one boot session on an
    /// already-dirty kernel is the main cause of panics, so:
    ///   * access-first: if we can already reach the game container, skip it;
    ///   * auto-run happens only ONCE per device boot;
    ///   * re-opens within the same boot only run it on demand (INJECT).
    private var currentBootTime: Int {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        let ok = sysctlbyname("kern.boottime", &tv, &size, nil, 0)
        return ok == 0 ? Int(tv.tv_sec) : 0
    }

    private let lastBootKey = "bola_last_boot"
    private let ranThisBootKey = "bola_ran_this_boot"

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

        // 1. already usable (escape from a previous run still applies)?
        if Installer.hasAccess(to: game) {
            kernelDone = true
            phase = .active
            statusText = "Đã có quyền truy cập — không cần chạy kernel"
            append("auto: đã truy cập được thư mục game → bỏ qua kernel (an toàn hơn)")
            refreshInstalled()
            return
        }

        // 2. run automatically only once per device boot
        let boot = currentBootTime
        let lastBoot = UserDefaults.standard.integer(forKey: lastBootKey)
        let ranThisBoot = UserDefaults.standard.bool(forKey: ranThisBootKey)

        if boot != 0, boot != lastBoot {
            UserDefaults.standard.set(boot, forKey: lastBootKey)
            UserDefaults.standard.set(false, forKey: ranThisBootKey)
        }

        if ranThisBoot {
            append("kernel: đã chạy trong lần khởi động máy này — KHÔNG chạy lại tự động (tránh panic)")
            statusText = "Kernel chưa chạy phiên này — bấm INJECT khi cần"
            phase = .idle
            return
        }

        UserDefaults.standard.set(true, forKey: ranThisBootKey)
        append("auto: mở app → chạy kernel ở nền (lần đầu trong boot)")
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
        busy = true
        phase = .running
        statusText = kernelDone ? "Đang inject…" : "Chờ kernel (đang chạy) rồi inject…"
        if kernelInFlight {
            append("inject: kernel đang chạy — sẽ cài ngay khi xong")
        }

        ensureKernel { [weak self] ok in
            guard let self else { return }
            guard ok || Installer.hasAccess(to: game) else {
                self.busy = false
                self.phase = .failed
                self.statusText = "Kernel lỗi — bấm Chạy lại exploit"
                self.append("inject: kernel chưa sẵn sàng, huỷ inject")
                self.alertText = "Kernel chưa sẵn sàng — chờ vài giây rồi bấm INJECT lại."
                return
            }
            self.append("inject: kernel sẵn sàng → cài \(patch.name) vào \(game.title)")
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Installer.install(patch: patch.url, into: game)
                DispatchQueue.main.async {
                    self.busy = false
                    self.phase = .active
                    self.statusText = result.ok ? "Đã inject — đang mở game" : "Inject lỗi"
                    self.append("inject: " + result.message)
                    self.refreshInstalled()
                    if result.ok {
                        self.launchGame()
                    } else {
                        self.alertText = result.message
                    }
                }
            }
        }
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
