import SwiftUI
import Foundation

/// Restore tab/sheet — Astra-style "khôi phục game về nguyên bản".
///
/// Scans installed games, shows which ones still have patch files, and
/// restores them:
///   1. local backup, 2. pristine copy from the server, 3. delete if it did
///   not exist before, 4. always delete our own marker files.
struct RestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    @State private var apps: [InstalledApp] = []
    @State private var states: [String: (files: Int, markers: Int)] = [:]
    @State private var times: [String: Date] = [:]
    @State private var busy = false
    @State private var busyName = ""
    @State private var log: [String] = []
    @State private var toast: String?
    @State private var confirmAll = false

    private let gameBundles = ["com.dts.freefireth", "com.dts.freefiremax"]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 12) {
                        intro
                        if apps.isEmpty {
                            emptyCard
                        } else {
                            ForEach(apps) { app in
                                row(app)
                            }
                            restoreAllButton
                        }
                        logCard
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
                if busy {
                    busyOverlay
                }
            }
            .navigationTitle("Khôi phục game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .confirmationDialog("Khôi phục tất cả game?",
                                isPresented: $confirmAll,
                                titleVisibility: .visible) {
                Button("Khôi phục tất cả", role: .destructive) { restoreAll() }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Hệ thống sẽ khôi phục mọi game về trạng thái nguyên bản: xoá patch và file tạm.")
            }
            .toastOverlay($toast)
            .onAppear(perform: load)
        }
    }

    // MARK: - intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Text("KHÔI PHỤC GAME")
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(1)
                    .foregroundColor(.white)
                Spacer()
            }
            Text(model.tr("Hệ thống sẽ khôi phục game về trạng thái nguyên bản: xoá patch, config và file tạm trong Data container.",
                          "Restores the game to its pristine state: removes patch, config and temp files from the Data container."))
                .font(.system(size: 10.5))
                .foregroundColor(Theme.dimmer)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.border, lineWidth: 1))
    }

    private var emptyCard: some View {
        VStack(spacing: 9) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Theme.dimmer)
            Text(model.tr("Không thấy Free Fire / FF MAX", "Free Fire / FF MAX not found"))
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
            Text(model.tr("Cài game rồi mở lại màn này.", "Install the game, then reopen this screen."))
                .font(.caption2)
                .foregroundColor(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - row

    private func row(_ app: InstalledApp) -> some View {
        let st = states[app.bundleID] ?? (files: 0, markers: 0)
        let patched = st.files + st.markers > 0
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.cardHi)
                        .frame(width: 40, height: 40)
                    Image(systemName: app.bundleID == "com.dts.freefireth" ? "flame.fill" : "bolt.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(app.bundleID)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(Theme.dimmer)
                        .lineLimit(1)
                }
                Spacer()
                statusPill(patched: patched, files: st.files, markers: st.markers)
            }

            if let t = times[app.bundleID] {
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9, weight: .bold))
                    Text(model.tr("Lần cuối: ", "Last: ") + timeText(t))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(Theme.dimmer)
            }

            Button {
                restore(app)
            } label: {
                Text(busy && busyName == app.name
                     ? model.tr("ĐANG KHÔI PHỤC…", "RESTORING…")
                     : model.tr("KHÔI PHỤC VỀ NGUYÊN BẢN", "RESTORE TO ORIGINAL"))
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(0.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(RestoreButtonStyle(active: patched))
            .disabled(busy)
        }
        .padding(13)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.border, lineWidth: 1))
    }

    private func statusPill(patched: Bool, files: Int, markers: Int) -> some View {
        let text = patched
            ? model.tr("ĐÃ PATCH", "PATCHED") + " · \(files + markers)"
            : model.tr("NGUYÊN BẢN", "ORIGINAL")
        return HStack(spacing: 5) {
            Circle()
                .fill(patched ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
        }
        .foregroundColor(patched ? .white : Theme.dim)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.cardHi)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - restore all

    private var restoreAllButton: some View {
        Button {
            confirmAll = true
        } label: {
            Text(model.tr("KHÔI PHỤC TẤT CẢ", "RESTORE ALL"))
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(GhostButtonStyle())
        .disabled(busy)
    }

    // MARK: - log

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LOG")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundColor(Theme.dimmer)
                Spacer()
                if !log.isEmpty {
                    Button {
                        log = []
                    } label: {
                        Text(model.tr("Xoá", "Clear"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.dim)
                    }
                    .buttonStyle(.plain)
                }
            }
            if log.isEmpty {
                Text("—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.dimmer)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(log.suffix(18).enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.border, lineWidth: 1))
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(model.tr("Đang khôi phục ", "Restoring ") + busyName + "…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(20)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
        }
    }

    // MARK: - actions

    private func load() {
        let all = ContainerStore.installedApps()
        apps = all.filter { gameBundles.contains($0.bundleID) && $0.hasContainer }
        refreshStates()
    }

    private func refreshStates() {
        var s: [String: (files: Int, markers: Int)] = [:]
        var t: [String: Date] = [:]
        for app in apps {
            s[app.bundleID] = PatchInstaller.patchState(bundleID: app.bundleID)
            if let d = PatchInstaller.restoreTime(bundleID: app.bundleID) {
                t[app.bundleID] = d
            }
        }
        states = s
        times = t
    }

    private func restore(_ app: InstalledApp) {
        guard !busy else { return }
        busy = true
        busyName = app.name
        log.append(model.tr("Đang khôi phục ", "Restoring ") + app.name + "...")
        DispatchQueue.global(qos: .userInitiated).async {
            let r = PatchInstaller.restoreGame(bundleID: app.bundleID)
            DispatchQueue.main.async {
                self.busy = false
                self.busyName = ""
                self.log.append(contentsOf: r.lines)
                self.toast = r.ok
                    ? self.model.tr("Đã khôi phục \(app.name) về nguyên bản",
                                    "\(app.name) restored to original")
                    : self.model.tr("Khôi phục chưa hoàn tất", "Restore incomplete")
                self.refreshStates()
            }
        }
    }

    private func restoreAll() {
        guard !busy, !apps.isEmpty else { return }
        busy = true
        busyName = model.tr("tất cả", "all")
        log = []
        let list = apps
        DispatchQueue.global(qos: .userInitiated).async {
            for app in list {
                DispatchQueue.main.async { self.busyName = app.name }
                let r = PatchInstaller.restoreGame(bundleID: app.bundleID)
                DispatchQueue.main.async { self.log.append(contentsOf: r.lines) }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.busyName = ""
                self.toast = self.model.tr("Đã khôi phục tất cả", "All restored")
                self.refreshStates()
            }
        }
    }

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm"
        return f.string(from: d)
    }
}

/// White when the game still has patch files (primary action),
/// ghost when it is already pristine.
struct RestoreButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(active ? .black : .white)
            .background(
                active
                    ? Color.white.opacity(configuration.isPressed ? 0.75 : 1)
                    : Theme.cardHi.opacity(configuration.isPressed ? 0.7 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(active ? Color.clear : Theme.borderHi, lineWidth: 1)
            )
    }
}
