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

    // MARK: - restore a whole game (Astra "khôi phục về nguyên bản")

    /// Restores every managed file of one game:
    ///   1. local backup (fast, offline)
    ///   2. pristine bytes from the server (download + verify sha256)
    ///   3. no pristine copy -> the file did not exist before -> delete
    ///   4. our own marker files (.bola_tok / .bola_uid) -> always delete
    static func restoreGame(bundleID: String,
                            store: PatchStore = .shared) -> GameRestoreReport {
        var lines: [String] = []
        guard let container = ContainerStore.containerPath(for: bundleID) else {
            return GameRestoreReport(ok: false, restored: 0, removed: 0, failed: 0,
                                     lines: ["Không thấy \(BundleLabel.short(bundleID)) trên máy"])
        }

        lines.append("Đang quét \(BundleLabel.short(bundleID))...")
        var paths = OriginalClient.manifest(bundle: bundleID)
        if paths.isEmpty {
            lines.append("Không lấy được danh sách từ máy chủ — dùng danh sách mặc định")
            paths = OriginalClient.fallbackPaths
        }

        let fm = FileManager.default
        var restored = 0
        var removed = 0
        var failed = 0

        for item in paths {
            guard let target = ContainerStore.targetPath(container: container,
                                                         relative: item.path) else {
                failed += 1
                lines.append("Bỏ qua đường dẫn không an toàn: \(item.path)")
                continue
            }
            let exists = fm.fileExists(atPath: target)

            // 1) bookkeeping files -> always delete
            if item.isMarker {
                if exists {
                    if (try? fm.removeItem(atPath: target)) != nil {
                        removed += 1
                        lines.append("Đã xoá \(item.path)")
                    } else {
                        failed += 1
                        lines.append("Không xoá được \(item.path)")
                    }
                }
                continue
            }

            // 2) local backup from any project that patched this target
            if let backup = localBackup(bundleID: bundleID,
                                        relativePath: item.path,
                                        store: store) {
                do {
                    let parent = (target as NSString).deletingLastPathComponent
                    try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
                    if exists { try? fm.removeItem(atPath: target) }
                    try fm.copyItem(atPath: backup.path, toPath: target)
                    restored += 1
                    lines.append("Đã khôi phục \(item.path) (bản sao lưu)")
                } catch {
                    failed += 1
                    lines.append("Khôi phục \(item.path) lỗi: \(error.localizedDescription)")
                }
                continue
            }

            // 3) pristine copy from the server
            if item.exists {
                lines.append("Đang tải dữ liệu gốc: \(item.path)...")
                if let data = OriginalClient.fetch(bundle: bundleID, path: item.path) {
                    let sha = PatchStore.sha256(data)
                    if !item.sha256.isEmpty && sha != item.sha256 {
                        failed += 1
                        lines.append("Dữ liệu gốc không toàn vẹn: \(item.path)")
                        continue
                    }
                    do {
                        let parent = (target as NSString).deletingLastPathComponent
                        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
                        if exists { try? fm.removeItem(atPath: target) }
                        try data.write(to: URL(fileURLWithPath: target), options: .atomic)
                        restored += 1
                        lines.append("Đã ghi đè bản gốc: \(item.path)")
                    } catch {
                        failed += 1
                        lines.append("Ghi bản gốc lỗi: \(error.localizedDescription)")
                    }
                } else {
                    failed += 1
                    lines.append("Không tải được bản gốc: \(item.path)")
                }
                continue
            }

            // 4) no pristine copy -> file did not exist before the patch
            if exists {
                if (try? fm.removeItem(atPath: target)) != nil {
                    removed += 1
                    lines.append("Đã xoá \(item.path)")
                } else {
                    failed += 1
                    lines.append("Không xoá được \(item.path)")
                }
            }
        }

        let ok = failed == 0
        if ok {
            UserDefaults.standard.set(Int(Date().timeIntervalSince1970),
                                      forKey: "restore_time_" + bundleID)
            lines.append("Đã khôi phục \(BundleLabel.short(bundleID)) về nguyên bản")
        } else {
            lines.append("Khôi phục chưa hoàn tất (\(failed) lỗi)")
        }
        return GameRestoreReport(ok: ok, restored: restored, removed: removed,
                                 failed: failed, lines: lines)
    }

    /// How many managed files / markers currently exist in the game container.
    static func patchState(bundleID: String) -> (files: Int, markers: Int) {
        guard let container = ContainerStore.containerPath(for: bundleID) else { return (0, 0) }
        let fm = FileManager.default
        var files = 0
        var markers = 0
        for item in OriginalClient.fallbackPaths {
            guard let target = ContainerStore.targetPath(container: container,
                                                         relative: item.path),
                  fm.fileExists(atPath: target) else { continue }
            if item.isMarker { markers += 1 } else { files += 1 }
        }
        return (files, markers)
    }

    static func restoreTime(bundleID: String) -> Date? {
        let t = UserDefaults.standard.integer(forKey: "restore_time_" + bundleID)
        return t > 0 ? Date(timeIntervalSince1970: TimeInterval(t)) : nil
    }

    private static func localBackup(bundleID: String,
                                    relativePath: String,
                                    store: PatchStore) -> URL? {
        for project in store.projects {
            for rule in project.rules
            where rule.bundleID == bundleID && rule.relativePath == relativePath {
                let bak = store.backupURL(project, rule)
                if FileManager.default.fileExists(atPath: bak.path) { return bak }
            }
        }
        return nil
    }
}

struct GameRestoreReport {
    let ok: Bool
    let restored: Int
    let removed: Int
    let failed: Int
    let lines: [String]
}
