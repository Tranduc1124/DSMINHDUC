import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Foundation

struct FileEntry: Identifiable, Hashable {
    let name: String
    let isDir: Bool
    let size: Int

    var id: String { name }
}

/// Files tab — browse every app's Data container (Astra's "Files").
/// Read/write through MobileHouseArrest or the sandbox escape.
struct FileBrowserView: View {
    @EnvironmentObject private var model: AppModel

    @State private var apps: [InstalledApp] = []
    @State private var query = ""
    @State private var loading = true

    private var filtered: [InstalledApp] {
        let withContainer = apps.filter { $0.hasContainer }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return withContainer }
        return withContainer.filter {
            $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    header
                    searchBar
                    if loading {
                        ProgressView()
                            .tint(.white)
                            .padding(.top, 40)
                    } else if filtered.isEmpty {
                        emptyCard
                    } else {
                        ForEach(filtered) { app in
                            row(app)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("FILES")
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.white)
                .tracking(1.2)
            Text(model.tr("Duyệt Data container của mọi app trên máy",
                          "Browse the Data container of every app on the device"))
                .font(.caption2)
                .foregroundColor(Theme.dim)
            Text(model.tr("Cần quyền sandbox (chạy Kernel Exploit ở tab TOOLS nếu danh sách trống).",
                          "Needs sandbox access (run the kernel exploit in TOOLS if this list is empty)."))
                .font(.system(size: 10))
                .foregroundColor(Theme.dimmer)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.dimmer)
            TextField("", text: $query,
                      prompt: Text(model.tr("Tìm app hoặc bundle…", "Search app or bundle…"))
                        .foregroundColor(Theme.dimmer))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(.system(size: 12.5))
                .foregroundColor(.white)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.dimmer)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.border, lineWidth: 1))
    }

    private var emptyCard: some View {
        VStack(spacing: 9) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Theme.dimmer)
            Text(model.tr("Không thấy container", "No container found"))
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
            Text(model.tr("Chạy Kernel Exploit ở tab TOOLS rồi mở lại tab này.",
                          "Run the kernel exploit in TOOLS, then reopen this tab."))
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

    private func row(_ app: InstalledApp) -> some View {
        NavigationLink {
            FileDirView(container: app.container ?? "", title: app.name)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.cardHi)
                        .frame(width: 40, height: 40)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(app.bundleID)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.dim)
                        .lineLimit(1)
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

    private func load() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let list = ContainerStore.installedApps()
            DispatchQueue.main.async {
                self.apps = list
                self.loading = false
            }
        }
    }
}

// MARK: - directory

struct FileDirView: View {
    let container: String
    let title: String

    @State private var path: String
    @State private var entries: [FileEntry] = []
    @State private var showPicker = false
    @State private var toast: String?
    @State private var pendingDelete: FileEntry?

    init(container: String, title: String, path: String = "") {
        self.container = container
        self.title = title
        _path = State(initialValue: path)
    }

    private var currentPath: String {
        path.isEmpty ? container : container + "/" + path
    }

    private var shownPath: String {
        path.isEmpty ? "/" : "/" + path
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 8) {
                    pathBar
                    if entries.isEmpty {
                        Text("—")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.dimmer)
                            .padding(.top, 30)
                    } else {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
        }
        .onAppear(perform: load)
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.data, .item],
                      allowsMultipleSelection: false) { result in
            importFile(result)
        }
        .confirmationDialog("Xoá file này?",
                            isPresented: Binding(
                                get: { pendingDelete != nil },
                                set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { entry in
            Button("Xoá \(entry.name)", role: .destructive) { delete(entry) }
            Button("Huỷ", role: .cancel) {}
        }
        .toastOverlay($toast)
    }

    private var pathBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive")
                .font(.system(size: 9, weight: .bold))
            Text(shownPath)
                .font(.system(size: 9.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Text("\(entries.count)")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(Theme.dimmer)
        .padding(.bottom, 2)
    }

    private func row(_ entry: FileEntry) -> some View {
        let child = path.isEmpty ? entry.name : path + "/" + entry.name

        return Group {
            if entry.isDir {
                NavigationLink {
                    FileDirView(container: container, title: entry.name, path: child)
                } label: {
                    rowBody(entry, chevron: true)
                }
                .buttonStyle(CardButtonStyle())
            } else {
                rowBody(entry, chevron: false)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = currentPath + "/" + entry.name
                            toast = "Đã copy đường dẫn"
                        } label: {
                            Label("Copy đường dẫn", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            pendingDelete = entry
                        } label: {
                            Label("Xoá", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func rowBody(_ entry: FileEntry, chevron: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isDir ? "folder.fill" : "doc.text.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(entry.isDir ? .white : Theme.dim)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !entry.isDir {
                    Text(sizeText(entry.size))
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.dimmer)
                }
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.dimmer)
            }
        }
        .padding(11)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.border, lineWidth: 1))
    }

    private func load() {
        var out: [FileEntry] = []
        let fm = FileManager.default
        if let names = try? fm.contentsOfDirectory(atPath: currentPath) {
            for n in names {
                let p = currentPath + "/" + n
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: p, isDirectory: &isDir) else { continue }
                let attrs = try? fm.attributesOfItem(atPath: p)
                let size = (attrs?[.size] as? Int) ?? 0
                out.append(FileEntry(name: n, isDir: isDir.boolValue, size: size))
            }
        }
        entries = out.sorted {
            if $0.isDir != $1.isDir { return $0.isDir }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func delete(_ entry: FileEntry) {
        let p = currentPath + "/" + entry.name
        do {
            try FileManager.default.removeItem(atPath: p)
            toast = "Đã xoá \(entry.name)"
            load()
        } catch {
            toast = "Không xoá được: \(error.localizedDescription)"
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let u = urls.first else { return }
            let scoped = u.startAccessingSecurityScopedResource()
            defer { if scoped { u.stopAccessingSecurityScopedResource() } }
            let dest = currentPath + "/" + u.lastPathComponent
            let fm = FileManager.default
            do {
                if fm.fileExists(atPath: dest) { try fm.removeItem(atPath: dest) }
                try fm.copyItem(at: u, to: URL(fileURLWithPath: dest))
                toast = "Đã nhập \(u.lastPathComponent)"
                load()
            } catch {
                toast = "Lỗi nhập file: \(error.localizedDescription)"
            }
        case .failure(let e):
            toast = e.localizedDescription
        }
    }

    private func sizeText(_ bytes: Int) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576.0) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024.0) }
        return "\(bytes) B"
    }
}
