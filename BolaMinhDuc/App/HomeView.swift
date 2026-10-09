import SwiftUI

/// Main screen: hero header + chips + game list. No tab bar.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    var openGame: (GameTarget) -> Void
    var openSettings: () -> Void

    @State private var appear = false
    @State private var installed: [String: Bool] = [:]

    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(y: -210)
                .allowsHitTesting(false)
            ScrollView {
                VStack(spacing: 16) {
                    header
                    chips
                    gameList
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            appear = true
            refreshInstalled()
        }
        .onChange(of: model.installedInfo) { _ in
            refreshInstalled()
        }
    }

    private func refreshInstalled() {
        var d: [String: Bool] = [:]
        for g in GameTarget.allCases {
            d[g.rawValue] = Installer.patchExists(for: g)
        }
        installed = d
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 46, height: 46)
                    .shadow(color: .white.opacity(0.22), radius: 16, y: 4)
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(.black)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("BOLAMINHDUC")
                    .font(.title3.weight(.heavy))
                    .foregroundColor(.white)
                    .tracking(0.6)
                Text(model.tr("Trợ lý trong game", "In-game toolkit") + " • " + DeviceInfo.appVersion)
                    .font(.caption2)
                    .foregroundColor(Theme.dim)
            }
            Spacer()
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.card)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
        .animation(.easeOut(duration: 0.35), value: appear)
    }

    // MARK: chips

    private var chips: some View {
        HStack(spacing: 8) {
            chip(icon: "iphone",
                 title: model.tr("THIẾT BỊ", "DEVICE"),
                 value: DeviceInfo.machine)
            chip(icon: "gear",
                 title: model.tr("HỆ ĐIỀU HÀNH", "SYSTEM"),
                 value: DeviceInfo.iosVersion)
            chip(icon: "checkmark.shield.fill",
                 title: model.tr("TƯƠNG THÍCH", "SUPPORT"),
                 value: ExploitRunner.isSupported() ? model.tr("Tốt", "Good") : model.tr("Hạn chế", "Limited"))
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
        .animation(.easeOut(duration: 0.35).delay(0.05), value: appear)
    }

    private func chip(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundColor(Theme.dimmer)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    // MARK: games

    private var gameList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(model.tr("CHỌN GAME", "SELECT GAME"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
            }
            .foregroundColor(Theme.dim)
            .padding(.top, 4)
            .padding(.leading, 2)

            ForEach(Array(GameTarget.allCases.enumerated()), id: \.element.id) { idx, game in
                Button {
                    openGame(game)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(
                                    LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                                                   startPoint: .top, endPoint: .bottom)
                                )
                                .frame(width: 50, height: 50)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(Theme.borderHi, lineWidth: 1)
                                )
                            Image(systemName: game == .freefireTH ? "flame.fill" : "bolt.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.title)
                                .font(.headline.weight(.bold))
                                .foregroundColor(.white)
                            Text(model.tr("Chỉnh chức năng & INJECT", "Features & INJECT"))
                                .font(.caption)
                                .foregroundColor(Theme.dim)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            statusPill(installed[game.rawValue] ?? false)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.dimmer)
                        }
                    }
                    .padding(14)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(CardButtonStyle())
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 16)
                .animation(.spring(response: 0.45, dampingFraction: 0.9).delay(0.08 + Double(idx) * 0.08), value: appear)
            }
        }
    }

    private func statusPill(_ isInstalled: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isInstalled ? Color.green : Theme.dimmer)
                .frame(width: 6, height: 6)
            Text(isInstalled ? model.tr("Đã cài", "Installed") : model.tr("Chưa cài", "Not installed"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isInstalled ? .white : Theme.dim)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.cardHi)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}
