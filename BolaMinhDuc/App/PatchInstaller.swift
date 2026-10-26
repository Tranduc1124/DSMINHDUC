import Foundation

struct GameRestoreReport {
    let ok: Bool
    let restored: Int
    let removed: Int
    let failed: Int
    let lines: [String]
}

/// Astra-style "restore game to pristine" — dùng cho nút KHÔI PHỤC cạnh INJECT.
///
/// Với từng file mà sản phẩm có thể để lại trong Data container của game:
///   1. server có bản gốc  -> tải về, verify sha256, ghi đè
///   2. server không có    -> file vốn không tồn tại trước khi patch -> xoá
///   3. file đánh dấu của mình (.bola_tok / .bola_uid / .bola_probe) -> luôn xoá
enum PatchInstaller {

    static func restoreGame(bundleID: String) -> GameRestoreReport {
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

            // 2) pristine copy from the server
            if item.exists {
                lines.append("Đang tải dữ liệu gốc: \(item.path)...")
                if let data = OriginalClient.fetch(bundle: bundleID, path: item.path) {
                    let sha = sha256(data)
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

            // 3) no pristine copy -> file did not exist before the patch
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

    /// Số file quản lý / file đánh dấu đang tồn tại trong container game.
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

    private static func sha256(_ data: Data) -> String {
        PatchClient.sha256(data).map { String(format: "%02x", $0) }.joined()
    }
}
