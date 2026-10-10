import SwiftUI

@main
struct BolaMinhDucApp: App {
    @StateObject private var model = AppModel()
    @ObservedObject private var gate = LicenseGate.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if gate.state == .authorized {
                    ContentView()
                        .environmentObject(model)
                        .overlay { BlockOverlay() }
                } else {
                    KeyScreenView()
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                LicenseGate.shared.start()
            }
            .onChange(of: gate.state) { st in
                if st == .authorized {
                    VersionGate.shared.check()
                    model.bootstrap()
                }
            }
        }
    }
}
