import SwiftUI

/// Root: NavigationStack, no tab bar.
/// Home -> Config(game) via push; Settings via Delta-style sheet.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [GameTarget] = []
    @State private var showSettings = false

    var body: some View {
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
        .tint(.white)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDragIndicator(.visible)
                .presentationDetents([.fraction(0.90)])
        }
        .onAppear { model.bootstrap() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.bootstrap()
                model.refreshInstalled()
            }
        }
        .toastOverlay(showSettings ? Binding<String?>.constant(nil) : $model.toastText)
    }
}
