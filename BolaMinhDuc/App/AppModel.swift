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

    /// auto-bootstrap runs once per app process (kernel access is per-process)
    private var didBootstrap = false
    /// kernel finished at least once this session
    private var kernelDone = false

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

    // MARK: - kernel (runs in background, UI does not depend on it)

    /// Called when the app appears: kick off the kernel exploit in the
    /// background, once per process. Nothing else happens automatically.
    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        append("auto: mở app → chạy kernel ở nền")
        runKernel(markBusy: false)
    }

    /// manual retry button
    func rerunKernel() {
        runKernel(markBusy: true)
    }

    private func runKernel(markBusy: Bool) {
        guard phase != .running else { return }
        phase = .running
        if markBusy {
            busy = true
            statusText = "Đang chạy exploit…"
        } else {
            statusText = "Kernel đang chạy nền…"
        }
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
                self.kernelDone = ok
                self.phase = ok ? .active : .failed
                self.statusText = ok ? "Kernel OK — bấm INJECT để cài patch"
                                    : "Kernel lỗi — bấm INJECT để thử lại"
                self.busy = false
                self.refreshInstalled()
            }
        }
    }

    // MARK: - INJECT: install patch + open game

    func inject() {
        guard !busy else { return }
        guard let patch = selectedPatch else {
            alertText = "Chưa có patch nào để inject."
            return
        }
        let game = self.game
        busy = true
        if phase != .running { phase = .running }
        statusText = "Đang inject…"

        let kernelReadyBefore = kernelDone || Installer.hasAccess(to: game)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var ready = kernelReadyBefore
            if !ready {
                self.append_main("inject: kernel chưa xong — chạy lại trước khi cài")
                let ok = ExploitRunner.run { line in
                    DispatchQueue.main.async { self.append(line) }
                }
                ready = ok || Installer.hasAccess(to: game)
                DispatchQueue.main.async { self.kernelDone = ready }
            }

            let result: InstallOutcome
            if ready {
                result = Installer.install(patch: patch.url, into: game)
            } else {
                result = InstallOutcome(ok: false,
                                        message: "Kernel chưa sẵn sàng — chờ vài giây rồi bấm INJECT lại.")
            }

            DispatchQueue.main.async {
                self.busy = false
                self.append("inject: " + result.message)
                self.phase = ready ? .active : .failed
                self.statusText = result.ok ? "Đã inject — đang mở game"
                                            : (ready ? "Kernel OK" : "Kernel lỗi")
                self.refreshInstalled()
                if result.ok {
                    self.launchGame()
                } else {
                    self.alertText = result.message
                }
            }
        }
    }

    private func append_main(_ line: String) {
        DispatchQueue.main.async { [weak self] in self?.append(line) }
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
}
