import SwiftUI

private enum RootTab: Hashable {
    case home
    case patch
    case files
    case tools
}

/// Root shell: Astra-style bottom tabs (Home / Patch / Files / Tools).
/// Home keeps the existing push navigation to ConfigView (features + INJECT);
/// Settings stays a sheet, the language picker a bottom panel.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [GameTarget] = []
    @State private var showSettings = false
    @State private var showLanguage = false
    @State private var tab: RootTab = .home

    var body: some View {
        Group {
            switch tab {
            case .home:
                NavigationStack(path: $path) {
                    HomeView(
                        openGame: { game in
                            model.game = game
                            model.refreshInstalled()
                            path.append(game)
                        },
                        openSettings: { showSettings = true }
                    )
                    .navigationDestination(for: GameTarget.self) { game in
                        ConfigView(game: game) { path.removeLast() }
                    }
                }
            case .patch:
                NavigationStack { PatchesView() }
            case .files:
                NavigationStack { FileBrowserView() }
            case .tools:
                NavigationStack { ToolsView() }
            }
        }
        .tint(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .sheet(isPresented: $showSettings) {
            SettingsView(openLanguage: {
                showSettings = false
                showLanguage = true
            })
            .presentationDragIndicator(.visible)
            .presentationDetents([.fraction(0.90)])
        }
        .overlay { languageOverlay }
        .onAppear {
            // Lớp UI: ContentView hiện nhưng session giả → đá về màn key
            guard LicenseGate.shared.revalidate() else { return }
            model.bootstrap()
            BackgroundAudio.shared.ensureRunning()
        }
        .onChange(of: scenePhase) { phase in
            BackgroundAudio.shared.ensureRunning()
            if phase == .active {
                guard LicenseGate.shared.revalidate() else { return }
                model.bootstrap()
                model.refreshInstalled()
            }
        }
        .toastOverlay(showSettings ? Binding<String?>.constant(nil) : $model.toastText)
    }

    // MARK: - bottom tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabItem(.home, "house.fill", "HOME")
            tabItem(.patch, "square.stack.3d.up.fill", "PATCH")
            tabItem(.files, "folder.fill", "FILES")
            tabItem(.tools, "wrench.and.screwdriver.fill", "TOOLS")
        }
        .padding(.top, 9)
        .padding(.bottom, 6)
        .background(
            Theme.card
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabItem(_ target: RootTab, _ icon: String, _ label: String) -> some View {
        Button {
            tab = target
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 8.5, weight: .heavy))
                    .tracking(0.6)
            }
            .foregroundColor(tab == target ? .white : Theme.dimmer)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: language panel (slides up from the bottom)

    private var languageOverlay: some View {
        ZStack(alignment: .bottom) {
            if showLanguage {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        closeLanguage()
                    }
                languageCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: showLanguage)
    }

    private var languageCard: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            Text(model.tr("Chọn ngôn ngữ", "Choose language"))
                .font(.headline.weight(.heavy))
                .foregroundColor(.white)
                .padding(.bottom, 4)
            langOption("vi", "🇻🇳", "Tiếng Việt")
            langOption("en", "🇺🇸", "English")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.cardHi)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.borderHi, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private func langOption(_ code: String, _ flag: String, _ title: String) -> some View {
        Button {
            model.setLanguage(code)
            closeLanguage()
        } label: {
            HStack(spacing: 12) {
                Text(flag)
                    .font(.system(size: 22))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                if model.language == code {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(model.language == code ? Theme.borderHi : Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }

    private func closeLanguage() {
        showLanguage = false
        showSettings = true
    }
}
