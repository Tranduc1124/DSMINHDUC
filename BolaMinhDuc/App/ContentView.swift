import SwiftUI

/// Root: NavigationStack, no tab bar.
/// Home -> Config(game) via push; Settings via Delta-style sheet.
/// Language picker = custom bottom panel; the settings sheet slides away first.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [GameTarget] = []
    @State private var showSettings = false
    @State private var showLanguage = false

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
            SettingsView(openLanguage: {
                showSettings = false
                showLanguage = true
            })
            .presentationDragIndicator(.visible)
            .presentationDetents([.fraction(0.90)])
        }
        .overlay { languageOverlay }
        .onAppear { model.bootstrap() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.bootstrap()
                model.refreshInstalled()
            }
        }
        .toastOverlay(showSettings ? Binding<String?>.constant(nil) : $model.toastText)
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
