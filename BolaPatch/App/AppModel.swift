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

    func append(_ line: String) {
        logText += line + "\n"
        if logText.count > 80_000 {
            logText.removeFirst(20_000)
        }
    }

    func reloadPatches() {
        patches = PatchLibrary.all()
        if selectedName == nil || !patches.contains(where: { $0.name == selectedName }) {
            selectedName = patches.first?.name
        }
    }

    func refreshInstalled() {
        installedInfo = Installer.installedPatchInfo(for: game)
    }

    func activate() {
        guard !busy else { return }
        phase = .running
        statusText = "Đang chạy exploit…"
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = ExploitRunner.run { line in
                DispatchQueue.main.async { self?.append(line) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.phase = ok ? .active : .failed
                self.statusText = ok ? "Đã kích hoạt — ghi được vào game" : "Kích hoạt thất bại"
                self.append(ok ? "exploit: sẵn sàng cài patch" : "exploit: không có quyền ghi")
                self.refreshInstalled()
            }
        }
    }

    func install() {
        guard !busy else { return }
        guard let patch = selectedPatch else {
            alertText = "Chưa có patch nào để cài."
            return
        }
        let game = self.game
        busy = true
        append("install: \(patch.name) -> \(game.title)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Installer.install(patch: patch.url, into: game)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.append("install: " + result.message)
                self.alertText = result.message
                self.refreshInstalled()
            }
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
