import SwiftUI
import UIKit

/// Root: two bottom tabs — INJECT và CÀI ĐẶT — with a pure black tab bar.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.08)
        let item = appearance.stackedLayoutAppearance
        item.normal.iconColor = UIColor.white.withAlphaComponent(0.45)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.45)]
        item.selected.iconColor = UIColor.white
        item.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            InjectView()
                .tabItem {
                    Label("INJECT", systemImage: "bolt.fill")
                }
                .tag(0)

            SettingsView()
                .tabItem {
                    Label("CÀI ĐẶT", systemImage: "gearshape.fill")
                }
                .tag(1)
        }
        .tint(.white)
        .onAppear { model.bootstrap() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.bootstrap()
                model.refreshInstalled()
            }
        }
        .alert(model.alertText ?? "", isPresented: Binding(
            get: { model.alertText != nil },
            set: { if !$0 { model.alertText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }
}
