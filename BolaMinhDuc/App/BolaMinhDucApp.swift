import SwiftUI

@main
struct BolaMinhDucApp: App {
    @StateObject private var model = AppModel()
    @ObservedObject private var gate = LicenseGate.shared

    var body: some Scene {
        WindowGroup {
            // KeyScreen LUÔN là root — ContentView chỉ overlay khi canEnterApp.
            // Patch nhánh if một chỗ vẫn còn KeyScreen bên dưới + watchdog kéo về.
            ZStack {
                KeyScreenView()

                if gate.canEnterApp {
                    ContentView()
                        .environmentObject(model)
                        .overlay { BlockOverlay() }
                        .transition(.opacity)
                        .onAppear {
                            // Lớp 2: vào ContentView mà seal/server chết → đá về key
                            if !LicenseGate.shared.revalidate() {
                                model.append("gate: ContentView bị đá — session giả")
                            } else {
                                VersionGate.shared.check()
                                VersionGate.shared.startPeriodic()
                                model.bootstrap()
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: gate.canEnterApp)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                _ = APIClientHandleOpenURL(url)
            }
            .onAppear {
                LicenseGate.shared.start()
            }
            .onChange(of: gate.canEnterApp) { ok in
                if ok {
                    VersionGate.shared.check()
                    VersionGate.shared.startPeriodic()
                    model.bootstrap()
                }
            }
        }
    }
}
