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
    @Published var statusText = "Chưa kích hoạt"
    @Published var game: GameTarget = .freefireTH
    @Published var patches: [PatchFile] = []
    @Published var selectedName: String?
    @Published var installedInfo = ""
    @Published var logText = ""
    @Published var busy = false
    @Published var alertText: String?
    @Published var showImporter = false
    @Published var autoInstall = true
    @Published var launchAfterInstall = true

    /// auto-bootstrap runs once per app process (kernel access is per-process)
    private var didBootstrap = false

    var deviceInfo: String {
        ExploitRunner.versionDescription() + " • " + (ExploitRunner.isSupported() ? "hỗ trợ" : "chưa kiểm chứng")
    }

    var selectedPatch: PatchFile? {
        patches.first { $0.name == selectedName } ?? patches.first
    }

    init() {
        reloadPatches()
        refreshInstalled()
    }

    // MARK: - text log

    func append(_ line: String) {
        logText += line + "\n"
        if logText.count > 80_000 {
            logText.removeFirst(20_000)
        }
    }

    // MARK: - auto bootstrap (runs on app open)

    /// Called from the UI as soon as the app appears. Runs the kernel exploit
    /// automatically (no button press), then optionally installs the selected
    /// patch — exactly once per process.
    func bootstrap() {
        guard !didBootstrap, phase != .running else { return }
        didBootstrap = true
        if phase == .active {
            refreshInstalled()
            return
        }
        append("auto: mở app → tự chạy kernel")
        activate(autoInstall: true)
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

    // MARK: - exploit + install

    func activate(autoInstall auto: Bool = false) {
        guard !busy else { return }
        phase = .running
        statusText = "Đang chạy exploit…"
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var ok = ExploitRunner.run { line in
                DispatchQueue.main.async { self?.append(line) }
            }
            // kernel r/w can lose the race — retry once before giving up
            if !ok {
                DispatchQueue.main.async { self?.append("exploit: thử lại lần 2…") }
                ok = ExploitRunner.run { line in
                    DispatchQueue.main.async { self?.append(line) }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if self.gameIsAccessible() {
                    self.phase = .active
                    self.statusText = "Sẵn sàng — truy cập được thư mục game"
                    self.append("status: đọc được thư mục game OK")
                } else {
                    self.phase = ok ? .active : .failed
                    self.statusText = ok ? "Kernel r/w OK (chưa đọc được thư mục game)"
                                        : "Kích hoạt thất bại"
                    self.append("status: chưa đọc được thư mục game")
                }
                self.busy = false
                self.refreshInstalled()
                if auto, self.autoInstall, self.selectedPatch != nil {
                    self.install(auto: true)
                }
            }
        }
    }

    private func gameIsAccessible() -> Bool {
        defer { refreshInstalled() }
        return Installer.hasAccess(to: game)
    }

    func install(auto: Bool = false) {
        guard !busy else { return }
        guard let patch = selectedPatch else {
            if !auto { alertText = "Chưa có patch nào để cài." }
            return
        }
        let game = self.game
        let launch = launchAfterInstall
        busy = true
        append("install: \(patch.name) -> \(game.title)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Installer.install(patch: patch.url, into: game)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.append("install: " + result.message)
                if !auto {
                    self.alertText = result.message
                }
                self.refreshInstalled()
                if result.ok, launch {
                    self.launchGame()
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
            alertText = "Đã cài patch nhưng không mở được game tự động — mở \(game.title) bằng tay giúp mình."
        }
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

    // MARK: - patch library

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
