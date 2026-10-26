import Foundation

struct PatchApplyResult {
    let ok: Bool
    let message: String
    let changed: Int

    static func fail(_ m: String) -> PatchApplyResult {
        PatchApplyResult(ok: false, message: m, changed: 0)
    }
    static func done(_ m: String, _ n: Int) -> PatchApplyResult {
        PatchApplyResult(ok: true, message: m, changed: n)
    }
}

/// Transactional file replacement — the Astra model.
///
///   plan    : resolve container per rule + validate the relative path
///   backup  : original -> backup/<rule>.bak (+ "existed" flag)
///   write   : replacement -> <target>.patchtmp -> atomic move
///   rollback: any failure restores every backup and deletes created files
///   restore : backup -> target (or delete when the patch created the file)
///
/// Only files inside the target app's *data container* are touched. The app
/// bundle, the binary and the code signature are never modified, and no
/// process is attached to the game.
enum PatchInstaller {

    private struct Item {
        let rule: PatchRule
        let target: String
    }

    // MARK: - apply

    static func apply(_ project: PatchProject, store: PatchStore = .shared) -> PatchApplyResult {
        guard !project.rules.isEmpty else { return .fail("Patch chưa có quy tắc nào") }

        // 1) plan + validate
        var items: [Item] = []
        var missing: [String] = []
        for rule in project.rules {
            guard let container = ContainerStore.containerPath(for: rule.bundleID) else {
                // app not installed -> skip this rule, keep the rest working
                missing.append(BundleLabel.short(rule.bundleID))
                continue
            }
            guard let target = ContainerStore.targetPath(container: container,
                                                         relative: rule.relativePath) else {
                return .fail("Đường dẫn không an toàn: \(rule.relativePath)")
            }
            let src = store.replacementURL(project, rule)
            guard FileManager.default.fileExists(atPath: src.path) else {
                return .fail("Thiếu file thay thế cho \(rule.relativePath)")
            }
            items.append(Item(rule: rule, target: target))
        }
        guard !items.isEmpty else {
            return .fail("Không thấy app nào trong patch — kiểm tra game đã cài chưa")
        }

        // 2) backup
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: store.backupDir(project.id),
                                   withIntermediateDirectories: true)
            for it in items {
                let bak = store.backupURL(project, it.rule)
                let existed = fm.fileExists(atPath: it.target)
                if existed {
                    if fm.fileExists(atPath: bak.path) { try? fm.removeItem(atPath: bak.path) }
                    try fm.copyItem(atPath: it.target, toPath: bak.path)
                }
                let flag = existed ? "1" : "0"
                try flag.write(to: store.existedURL(project, it.rule),
                               atomically: true, encoding: .utf8)
            }
        } catch {
            return .fail("Sao lưu file gốc thất bại: \(error.localizedDescription)")
        }

        // 3) write (rollback on any error)
        var written: [Item] = []
        do {
            for it in items {
                let src = store.replacementURL(project, it.rule)
                let parent = (it.target as NSString).deletingLastPathComponent
                try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)

                let tmp = it.target + ".patchtmp"
                if fm.fileExists(atPath: tmp) { try? fm.removeItem(atPath: tmp) }
                try fm.copyItem(atPath: src.path, toPath: tmp)
                if fm.fileExists(atPath: it.target) { try fm.removeItem(atPath: it.target) }
                try fm.moveItem(atPath: tmp, toPath: it.target)
                written.append(it)
            }
        } catch {
            rollback(written, project: project, store: store)
            return .fail("Ghi file thất bại — đã rollback: \(error.localizedDescription)")
        }

        var p = project
        p.status = .applied
        p.appliedAt = Date()
        store.save(p)
        let note = missing.isEmpty ? "" : " · bỏ qua: " + missing.joined(separator: ", ")
        return .done("Đã áp dụng \(written.count) file" + note, written.count)
    }

    private static func rollback(_ items: [Item], project: PatchProject, store: PatchStore) {
        let fm = FileManager.default
        for it in items {
            let bak = store.backupURL(project, it.rule)
            if fm.fileExists(atPath: bak.path) {
                try? fm.removeItem(atPath: it.target)
                try? fm.copyItem(atPath: bak.path, toPath: it.target)
            } else {
                try? fm.removeItem(atPath: it.target)
            }
        }
    }

    // MARK: - restore

    static func restore(_ project: PatchProject, store: PatchStore = .shared) -> PatchApplyResult {
        guard !project.rules.isEmpty else { return .fail("Patch chưa có quy tắc nào") }
        let fm = FileManager.default
        var n = 0

        for rule in project.rules {
            guard let container = ContainerStore.containerPath(for: rule.bundleID),
                  let target = ContainerStore.targetPath(container: container,
                                                         relative: rule.relativePath)
            else { continue }

            let bak = store.backupURL(project, rule)
            let flag = store.existedURL(project, rule)
            let hadOriginal = (try? String(contentsOf: flag, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "1"

            if hadOriginal, fm.fileExists(atPath: bak.path) {
                try? fm.removeItem(atPath: target)
                if (try? fm.copyItem(atPath: bak.path, toPath: target)) != nil { n += 1 }
            } else if !hadOriginal {
                if fm.fileExists(atPath: target),
                   (try? fm.removeItem(atPath: target)) != nil { n += 1 }
            }
            try? fm.removeItem(atPath: bak.path)
            try? fm.removeItem(atPath: flag.path)
        }

        var p = project
        p.status = .restored
        p.appliedAt = nil
        store.save(p)
        return .done("Đã khôi phục \(n) file", n)
    }

    // MARK: - reset (Astra "Đặt lại theo gói")

    static func reset(_ project: PatchProject, store: PatchStore = .shared) -> PatchApplyResult {
        _ = restore(project, store: store)
        return apply(project, store: store)
    }

    // MARK: - state

    /// How many rules currently match the project content on disk.
    static func installedCount(_ project: PatchProject, store: PatchStore = .shared) -> Int {
        var n = 0
        for rule in project.rules {
            guard let container = ContainerStore.containerPath(for: rule.bundleID),
                  let target = ContainerStore.targetPath(container: container,
                                                         relative: rule.relativePath),
                  let data = FileManager.default.contents(atPath: target),
                  PatchStore.sha256(data) == rule.sha256
            else { continue }
            n += 1
        }
        return n
    }

    /// Targets that no longer match the applied package (game rewrote them).
    static func changedTargets(_ project: PatchProject) -> [String] {
        var out: [String] = []
        for rule in project.rules {
            guard let container = ContainerStore.containerPath(for: rule.bundleID),
                  let target = ContainerStore.targetPath(container: container,
                                                         relative: rule.relativePath),
                  let data = FileManager.default.contents(atPath: target)
            else { continue }
            if PatchStore.sha256(data) != rule.sha256 { out.append(rule.relativePath) }
        }
        return out
    }
}
