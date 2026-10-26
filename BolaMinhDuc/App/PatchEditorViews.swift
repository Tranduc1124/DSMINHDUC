import SwiftUI
import UniformTypeIdentifiers
import Foundation

// MARK: - shared field components

struct PatchLabeledField: View {
    let title: String
    @Binding var text: String
    var placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundColor(Theme.dimmer)
            TextField("", text: $text,
                      prompt: Text(placeholder).foregroundColor(Theme.dimmer))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundColor(.white)
                .padding(12)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1))
        }
    }
}

struct PatchAppPicker: View {
    @Binding var bundleID: String
    let apps: [InstalledApp]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("APP ĐÍCH")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundColor(Theme.dimmer)

            Menu {
                ForEach(apps.filter { $0.hasContainer }) { app in
                    Button {
                        bundleID = app.bundleID
                    } label: {
                        Text(app.name + "  ·  " + app.bundleID)
                    }
                }
                Divider()
                Button("Free Fire") { bundleID = "com.dts.freefireth" }
                Button("Free Fire MAX") { bundleID = "com.dts.freefiremax" }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12, weight: .semibold))
                    Text(bundleID.isEmpty ? "Chọn app" : bundleID)
                        .font(.system(size: 12.5, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(12)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text("Hoặc gõ bundle identifier (không dán UUID container)")
                .font(.system(size: 9.5))
                .foregroundColor(Theme.dimmer)
        }
    }
}

struct PatchFilePick: View {
    @Binding var picked: URL?
    @Binding var showPicker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FILE THAY THẾ")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundColor(Theme.dimmer)

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: picked == nil ? "doc.badge.plus" : "doc.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(picked?.lastPathComponent ?? "Chọn file trong máy…")
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if let u = picked {
                        Text(sizeText(u))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.dim)
                    }
                }
                .foregroundColor(.white)
                .padding(12)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func sizeText(_ url: URL) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size >= 1_048_576 { return String(format: "%.1f MB", Double(size) / 1_048_576.0) }
        if size >= 1024 { return String(format: "%.0f KB", Double(size) / 1024.0) }
        return "\(size) B"
    }
}

// MARK: - new patch

struct NewPatchView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var author = ""
    @State private var bundleID = "com.dts.freefireth"
    @State private var relativePath = ""
    @State private var picked: URL?
    @State private var apps: [InstalledApp] = []
    @State private var showPicker = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 14) {
                        PatchLabeledField(title: "TÊN PATCH", text: $name,
                                          placeholder: "MinDo Patch")
                        PatchLabeledField(title: "TÁC GIẢ", text: $author,
                                          placeholder: "MinDo")
                        PatchAppPicker(bundleID: $bundleID, apps: apps)
                        PatchFilePick(picked: $picked, showPicker: $showPicker)
                        PatchLabeledField(title: "ĐƯỜNG DẪN TRONG CONTAINER",
                                          text: $relativePath,
                                          placeholder: "Documents/Assembly-CSharp-patch.bytes")

                        if !error.isEmpty {
                            Text(error)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            create()
                        } label: {
                            Text("TẠO PATCH")
                                .font(.system(size: 13, weight: .heavy))
                                .tracking(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(WhiteButtonStyle())
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Patch mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
            .onAppear {
                if apps.isEmpty { apps = ContainerStore.installedApps() }
            }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: false) { result in
                handlePick(result)
            }
        }
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let u = urls.first else { return }
            picked = u
            if relativePath.trimmingCharacters(in: .whitespaces).isEmpty {
                relativePath = "Documents/" + u.lastPathComponent
            }
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                name = u.deletingPathExtension().lastPathComponent
            }
            error = ""
        case .failure(let e):
            error = e.localizedDescription
        }
    }

    private func create() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { error = "Nhập tên patch"; return }
        guard let src = picked else { error = "Chọn file thay thế"; return }
        guard let rel = ContainerStore.safeRelativePath(relativePath) else {
            error = "Đường dẫn phải tương đối (vd Documents/file.bytes), không dùng .."
            return
        }
        let project = PatchStore.shared.createProject(
            name: n,
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            entries: [(bundleID: bundleID, relativePath: rel, source: src)])
        guard project != nil else {
            error = "Không tạo được patch — kiểm tra file và đường dẫn"
            return
        }
        dismiss()
    }
}

// MARK: - add rule to an existing project

struct AddRuleView: View {
    @Environment(\.dismiss) private var dismiss
    let project: PatchProject

    @State private var bundleID: String
    @State private var relativePath = ""
    @State private var picked: URL?
    @State private var apps: [InstalledApp] = []
    @State private var showPicker = false
    @State private var error = ""

    init(project: PatchProject) {
        self.project = project
        _bundleID = State(initialValue: project.bundles.first ?? "com.dts.freefireth")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 14) {
                        Text(project.name)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        PatchAppPicker(bundleID: $bundleID, apps: apps)
                        PatchFilePick(picked: $picked, showPicker: $showPicker)
                        PatchLabeledField(title: "ĐƯỜNG DẪN TRONG CONTAINER",
                                          text: $relativePath,
                                          placeholder: "Documents/localConfig.json")

                        if !error.isEmpty {
                            Text(error)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            add()
                        } label: {
                            Text("THÊM VÀO PATCH")
                                .font(.system(size: 13, weight: .heavy))
                                .tracking(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(WhiteButtonStyle())
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Thêm file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
            .onAppear {
                if apps.isEmpty { apps = ContainerStore.installedApps() }
            }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let u = urls.first else { return }
                    picked = u
                    if relativePath.trimmingCharacters(in: .whitespaces).isEmpty {
                        relativePath = "Documents/" + u.lastPathComponent
                    }
                    error = ""
                case .failure(let e):
                    error = e.localizedDescription
                }
            }
        }
    }

    private func add() {
        guard let src = picked else { error = "Chọn file thay thế"; return }
        guard let rel = ContainerStore.safeRelativePath(relativePath) else {
            error = "Đường dẫn phải tương đối, không dùng .."
            return
        }
        if let msg = PatchStore.shared.addRule(to: project,
                                               bundleID: bundleID,
                                               relativePath: rel,
                                               source: src) {
            error = msg
            return
        }
        dismiss()
    }
}
