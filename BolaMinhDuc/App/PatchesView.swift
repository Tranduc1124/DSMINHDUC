import SwiftUI
import Foundation

/// Patch tab — Astra-style project list: apply / restore / delete, with the
/// original files backed up before every write.
struct PatchesView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var store = PatchStore.shared

    @State private var showNew = false
    @State private var showRestore = false
    @State private var addRuleTo: PatchProject?
    @State private var pending: Pending?
    @State private var busy = false
    @State private var toast: String?
    @State private var installed: [UUID: Int] = [:]

    private enum Pending: Identifiable {
        case apply(PatchProject)
        case restore(PatchProject)
        case delete(PatchProject)

        var id: String {
            switch self {
            case .apply(let p): return "apply-" + p.id.uuidString
            case .restore(let p): return "restore-" + p.id.uuidString
            case .delete(let p): return "delete-" + p.id.uuidString
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    header
                    restoreCard
                    if store.projects.isEmpty {
                        emptyCard
                    } else {
                        ForEach(store.projects) { project in
                            card(project)
                        }
                    }
                    hint
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNew) { NewPatchView() }
        .sheet(isPresented: $showRestore) { RestoreView() }
        .sheet(item: $addRuleTo) { project in AddRuleView(project: project) }
        .confirmationDialog(dialogTitle, isPresented: dialogShown, presenting: pending) { item in
            switch item {
            case .apply(let p):
                Button("Áp dụng") { runApply(p) }
            case .restore(let p):
                Button("Khôi phục file gốc", role: .destructive) { runRestore(p) }
            case .delete(let p):
                Button("Xoá patch", role: .destructive) {
                    store.delete(p)
                    toast = "Đã xoá patch"
                    refreshCounts()
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: { item in
            Text(dialogMessage(item))
        }
        .toastOverlay($toast)
        .onAppear(perform: refreshCounts)
        .onChange(of: store.projects.count) { _ in refreshCounts() }
    }

    // MARK: - restore entry

    private var restoreCard: some View {
        Button {
            showRestore = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.cardHi)
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.tr("KHÔI PHỤC GAME", "RESTORE GAME"))
                        .font(.system(size: 13.5, weight: .heavy))
                        .tracking(0.6)
                        .foregroundColor(.white)
                    Text(model.tr("Trả game về trạng thái nguyên bản — tải bản gốc từ máy chủ",
                                  "Restore the game to its pristine state — fetch the original from the server"))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.dim)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.dimmer)
            }
            .padding(12)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(CardButtonStyle())
    }

    // MARK: - header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PATCH")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.white)
                        .tracking(1.2)
                    Text(model.tr("Quản lý gói patch — áp dụng / khôi phục",
                                  "Patch manager — apply / restore"))
                        .font(.caption2)
                        .foregroundColor(Theme.dim)
                }
                Spacer()
                Button {
                    showNew = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 38, height: 38)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            Text(model.tr("File gốc luôn được sao lưu trước khi ghi. Chỉ ghi trong Data container của app — không đụng binary, không inject tiến trình.",
                          "Original files are backed up before every write. Only the app's Data container is touched — no binary, no process injection."))
                .font(.system(size: 10.5))
                .foregroundColor(Theme.dimmer)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(Theme.dimmer)
            Text(model.tr("Chưa có patch", "No patch yet"))
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
            Text(model.tr("Bấm ＋ để tạo patch từ file trong máy.",
                          "Tap ＋ to build a patch from a local file."))
                .font(.caption2)
                .foregroundColor(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - project card

    private func card(_ project: PatchProject) -> some View {
        let active = installed[project.id] ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.cardHi)
                        .frame(width: 42, height: 42)
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(project.bundles.map { BundleLabel.short($0) }.joined(separator: " · "))
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.dim)
                        .lineLimit(1)
                }
                Spacer()
                statusPill(project, installed: active)
            }

            HStack(spacing: 14) {
                metaItem("doc.on.doc", "\(project.rules.count) file")
                metaItem("internaldrive", byteText(project.totalBytes))
                if !project.author.isEmpty {
                    metaItem("person", project.author)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    pending = .apply(project)
                } label: {
                    Text(model.tr("ÁP DỤNG", "APPLY"))
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(0.6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(WhiteButtonStyle())
                .disabled(busy)

                Button {
                    pending = .restore(project)
                } label: {
                    Text(model.tr("KHÔI PHỤC", "RESTORE"))
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(0.6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(busy)

                Menu {
                    Button {
                        addRuleTo = project
                    } label: {
                        Label("Thêm file", systemImage: "plus.circle")
                    }
                    Button {
                        pending = .apply(project)
                    } label: {
                        Label("Đặt lại theo gói", systemImage: "arrow.clockwise")
                    }
                    Divider()
                    Button(role: .destructive) {
                        pending = .delete(project)
                    } label: {
                        Label("Xoá patch", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.cardHi)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1))
                }
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Theme.border, lineWidth: 1))
    }

    private func statusPill(_ project: PatchProject, installed: Int) -> some View {
        let total = project.rules.count
        let active = total > 0 && installed == total
        let partial = installed > 0 && installed < total
        let text = active ? model.tr("ĐANG BẬT", "ACTIVE")
                 : (partial ? "\(installed)/\(total)" : model.tr("TẮT", "OFF"))
        let color = active ? Color.green : (partial ? Color.orange : Theme.dimmer)
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.5)
        }
        .foregroundColor(active || partial ? .white : Theme.dim)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.cardHi)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }

    private func metaItem(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(Theme.dim)
    }

    private var hint: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))
            Text(model.tr("Đóng game trước khi Áp dụng hoặc Khôi phục. Patch chỉ ghi file trong Documents/Library của game.",
                          "Close the game before Apply or Restore. The patch only writes files inside the game's Documents/Library."))
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .foregroundColor(Theme.dimmer)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    // MARK: - dialogs

    private var dialogShown: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private var dialogTitle: String {
        switch pending {
        case .apply: return model.tr("Áp dụng patch?", "Apply patch?")
        case .restore: return model.tr("Khôi phục file gốc?", "Restore original files?")
        case .delete: return model.tr("Xoá patch này?", "Delete this patch?")
        case .none: return ""
        }
    }

    private func dialogMessage(_ item: Pending) -> String {
        switch item {
        case .apply(let p):
            return model.tr("\(p.rules.count) file sẽ được ghi. File gốc được sao lưu trước.",
                            "\(p.rules.count) files will be written. Originals are backed up first.")
        case .restore:
            return model.tr("File sẽ trở về trạng thái trước khi áp dụng; file do patch tạo sẽ bị xoá.",
                            "Files return to the pre-apply state; files created by the patch are removed.")
        case .delete:
            return model.tr("Xoá khỏi app (không ảnh hưởng file trong game).",
                            "Removed from the app (game files are untouched).")
        }
    }

    // MARK: - actions

    private func runApply(_ project: PatchProject) {
        guard !busy else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let r = PatchInstaller.apply(project)
            DispatchQueue.main.async {
                self.busy = false
                self.toast = r.ok ? "\(r.message) → \(project.name)" : r.message
                self.store.reload()
                self.refreshCounts()
            }
        }
    }

    private func runRestore(_ project: PatchProject) {
        guard !busy else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let r = PatchInstaller.restore(project)
            DispatchQueue.main.async {
                self.busy = false
                self.toast = r.message
                self.store.reload()
            }
        }
    }

    private func refreshCounts() {
        let snapshot = store.projects
        DispatchQueue.global(qos: .utility).async {
            var out: [UUID: Int] = [:]
            for p in snapshot {
                out[p.id] = PatchInstaller.installedCount(p)
            }
            DispatchQueue.main.async { self.installed = out }
        }
    }

    private func byteText(_ bytes: Int) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576.0) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024.0) }
        return "\(bytes) B"
    }
}
