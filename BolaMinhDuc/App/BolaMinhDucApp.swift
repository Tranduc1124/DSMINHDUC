import SwiftUI

@main
struct BolaMinhDucApp: App {
    @StateObject private var model = AppModel()
    @ObservedObject private var gate = LicenseGate.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if AppConfig.requireKey {
                    keyedRoot
                } else {
                    keylessRoot
                }
            }
            .animation(.easeInOut(duration: 0.25), value: gate.canEnterApp)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                if AppConfig.requireKey {
                    _ = APIClientHandleOpenURL(url)
                }
            }
            .onAppear {
                LicenseGate.shared.start()
            }
            .onChange(of: gate.canEnterApp) { ok in
                if ok { afterUnlock() }
            }
        }
    }

    /// Bản có key: KeyScreen luôn là root, ContentView chỉ overlay khi
    /// canEnterApp (watchdog kéo về nếu session chết).
    private var keyedRoot: some View {
        ZStack {
            KeyScreenView()
            if gate.canEnterApp {
                content
                    .transition(.opacity)
            }
        }
    }

    /// Bản không dùng key: vào thẳng app.
    private var keylessRoot: some View {
        content
    }

    private var content: some View {
        ContentView()
            .environmentObject(model)
            .overlay { BlockOverlay() }
            .onAppear {
                if AppConfig.requireKey && !LicenseGate.shared.revalidate() {
                    model.append("gate: ContentView bị đá — session giả")
                    return
                }
                afterUnlock()
            }
    }

    private func afterUnlock() {
        VersionGate.shared.check()
        VersionGate.shared.startPeriodic()
        model.bootstrap()
    }
}
