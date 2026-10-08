import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    gameCard
                    patchCard
                    actionCard
                    logCard
                }
                .padding(14)
            }
            .background(
                LinearGradient(colors: [Color.black, Color(red: 0.06, green: 0.03, blue: 0.10)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundColor(.purple)
                        Text("BOLAMINHDUC")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { model.bootstrap() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.bootstrap()
                model.refreshInstalled()
            }
        }
        .sheet(isPresented: $model.showImporter) {
            DocumentPicker { url in model.importPicked(url) }
        }
        .alert(model.alertText ?? "", isPresented: Binding(
            get: { model.alertText != nil },
            set: { if !$0 { model.alertText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: cards

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(model.statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                if model.busy {
                    ProgressView().tint(.purple)
                }
            }
            Text(model.deviceInfo)
                .font(.caption)
                .foregroundColor(.gray)

            Button {
                model.rerunKernel()
            } label: {
                Label("Chạy lại exploit", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.purple)
            .disabled(model.busy)
        }
        .card()
    }

    private var gameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GAME").sectionTitle()
            Picker("Game", selection: $model.game) {
                ForEach(GameTarget.allCases) { game in
                    Text(game.title).tag(game)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.game) { _ in model.refreshInstalled() }
            Text(model.installedInfo)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .card()
    }

    private var patchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PATCH").sectionTitle()
                Spacer()
                Button {
                    model.showImporter = true
                } label: {
                    Label("Thêm", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .tint(.purple)
            }

            if model.patches.isEmpty {
                Text("Chưa có patch .bytes nào.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            ForEach(model.patches) { patch in
                Button {
                    model.selectedName = patch.name
                } label: {
                    HStack {
                        Image(systemName: model.selectedPatch?.name == patch.name
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(patch.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text("\(patch.size) bytes\(patch.bundled ? " • có sẵn" : "")")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private var actionCard: some View {
        VStack(spacing: 10) {
            Button {
                model.inject()
            } label: {
                VStack(spacing: 3) {
                    Label("INJECT", systemImage: "bolt.fill")
                        .font(.title3.weight(.bold))
                    Text("tự cài patch & mở game")
                        .font(.caption2)
                        .opacity(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(model.busy || model.selectedPatch == nil)

            HStack(spacing: 10) {
                Button {
                    model.restore()
                } label: {
                    Label("Xoá patch", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    model.deleteSelected()
                } label: {
                    Label("Xoá khỏi app", systemImage: "minus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.selectedPatch?.bundled ?? true)
            }
            .tint(.gray)
        }
        .card()
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LOG").sectionTitle()
                Spacer()
                Button("Xoá log") { model.logText = "" }
                    .font(.caption)
                    .tint(.gray)
            }
            ScrollView {
                Text(model.logText.isEmpty ? "—" : model.logText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.green.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 160)
        }
        .card()
    }

    private var statusColor: Color {
        switch model.phase {
        case .idle: return .gray
        case .running: return .yellow
        case .active: return .green
        case .failed: return .red
        }
    }
}

private extension View {
    func card() -> some View {
        self
            .padding(14)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.purple.opacity(0.25), lineWidth: 1)
            )
    }
}

private extension Text {
    func sectionTitle() -> some View {
        self.font(.caption.weight(.bold))
            .foregroundColor(.purple)
            .tracking(1.2)
    }
}
