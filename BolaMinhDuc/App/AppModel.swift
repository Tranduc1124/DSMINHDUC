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
    @Published var patches: [PatchFile] = []
    @Published var selectedName: String?
    @Published var installedInfo = ""
    @Published var logText = ""
    @Published var busy = false
    @Published var alertText: String?
    @Published var showImporter = false
    @Published var latestTag = ""

    // MARK: kernel single-flight state (main-thread only)

    private var didBootstrap = false
    private var kernelInFlight = false
    private var kernelDone = false
    private var kernelWaiters: [(Bool) -> Void] = []

    var deviceInfo: String {
        ExploitRunner.versionDescription() + " • " + (ExploitRunner.isSupported() ? "hỗ trợ" : "chưa kiểm chứng")
    }

    var selectedPatch: PatchFile? {
        patches.first { $0.name == selectedName } ?? patches.first
    }

    init() {
        reloadPatches()
    }

    // MARK: - log

    func append(_ line: String) {
        logText += line + "\n"
        if logText.count > 80_000 {
            logText.removeFirst(20_000)
        }
    }

    // MARK: - kernel (single run; INJECT joins a run already in flight)

    /// Runs the kernel exploit at most once at a time. If it is already
    /// running, `completion` fires when that run finishes — pressing INJECT
    /// during the kernel therefore piggy-backs instead of racing it.
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
        append("auto: mở app → chạy kernel ở nền")
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
        guard let patch = selectedPatch else {
            alertText = "Chưa có patch nào để inject."
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

    // MARK: - patches

    func reloadPatches() {
        patches = PatchLibrary.all()
        if selectedName == nil || !patches.contains(where: { $0.name == selectedName }) {
            selectedName = patches.first?.name
        }
    }

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

    func importPicked(_ url: URL) {
        do {
            let patch = try PatchLibrary.importFile(from: url)
            reloadPatches()
            selectedName = patch.name
            alertText = "Đã thêm patch: \(patch.name)"
        } catch {
            alertText = "Không thêm được patch: \(error.localizedDescription)"
        }
    }

    func deleteSelected() {
        guard let patch = selectedPatch, !patch.bundled else {
            alertText = "Patch có sẵn trong app, không xoá được."
            return
        }
        PatchLibrary.delete(patch)
        reloadPatches()
        refreshInstalled()
    }

    // MARK: - settings actions

    /// Fetches the newest release tag from the (public) GitHub repo.
    func checkUpdate() {
        guard let url = URL(string: "https://api.github.com/repos/Tranduc1124/DSMINHDUC/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tag = json["tag_name"] as? String {
                    self.latestTag = tag
                    self.append("update: bản mới nhất \(tag)")
                    self.alertText = "Bản mới nhất trên GitHub: \(tag)"
                } else {
                    self.alertText = "Không kiểm tra được cập nhật\(error.map { ": \($0.localizedDescription)" } ?? "")."
                }
            }
        }.resume()
    }

    /// Removes caches + temp files created by the app (keeps imported patches).
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
