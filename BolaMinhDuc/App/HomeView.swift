import SwiftUI

/// Main screen: hero card (logo + device stats) + game list. No tab bar.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    var openGame: (GameTarget) -> Void
    var openSettings: () -> Void

    @State private var appear = false
    @State private var detected: [String: Bool] = [:]

    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .offset(y: -220)
                .allowsHitTesting(false)
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    gameList
                    hint
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            appear = true
            refreshDetected()
        }
        .onChange(of: model.installedInfo) { _ in
            refreshDetected()
        }
    }

    private func refreshDetected() {
        var d: [String: Bool] = [:]
        for g in GameTarget.allCases {
            d[g.rawValue] = Installer.isGameDetected(g.rawValue)
        }
        detected = d
    }

    // MARK: hero

    private var hero: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 52, height: 52)
                        .shadow(color: .white.opacity(0.25), radius: 18, y: 5)
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(.black)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("BOLAMINHDUC")
                        .font(.headline.weight(.heavy))
                        .foregroundColor(.white)
                        .tracking(0.6)
                    Text(model.tr("Trợ lý trong game", "In-game toolkit"))
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
                        .background(Theme.cardHi)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.leading, 79)

            HStack(spacing: 0) {
                heroStat(icon: "iphone",
                         title: model.tr("THIẾT BỊ", "DEVICE"),
                         value: DeviceInfo.machine)
                statDivider
                heroStat(icon: "gear",
                         title: model.tr("HỆ ĐIỀU HÀNH", "SYSTEM"),
                         value: DeviceInfo.iosVersion)
                statDivider
                heroStat(icon: "checkmark.shield.fill",
                         title: model.tr("TƯƠNG THÍCH", "SUPPORT"),
                         value: ExploitRunner.isSupported() ? model.tr("Tốt", "Good") : model.tr("Hạn chế", "Limited"))
            }
            .padding(.vertical, 11)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
        .animation(.easeOut(duration: 0.35), value: appear)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1, height: 24)
    }

    private func heroStat(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundColor(Theme.dimmer)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: games

    private var gameList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(model.tr("CHỌN GAME", "SELECT GAME"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
            }
            .foregroundColor(Theme.dim)
            .padding(.top, 2)
            .padding(.leading, 2)

            ForEach(Array(GameTarget.allCases.enumerated()), id: \.element.id) { idx, game in
                Button {
                    openGame(game)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(gameIconGradient(game))
                                .frame(width: 54, height: 54)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                )
                                .shadow(color: gameAccent(game).opacity(0.35), radius: 12, y: 4)
                            Image(systemName: game == .freefireTH ? "flame.fill" : "bolt.fill")
                                .font(.system(size: 22, weight: .semibold))
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
                        VStack(alignment: .trailing, spacing: 9) {
                            detectPill(detected[game.rawValue] ?? false)
                            ZStack {
                                Circle()
                                    .fill(Theme.cardHi)
                                    .frame(width: 26, height: 26)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(13)
                    .background(
                        LinearGradient(colors: [Theme.cardHi.opacity(0.55), Theme.card],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(gameAccent(game))
                            .frame(width: 3)
                            .padding(.vertical, 14)
                            .padding(.leading, 1)
                    }
                }
                .buttonStyle(CardButtonStyle())
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 16)
                .animation(.spring(response: 0.45, dampingFraction: 0.9).delay(0.08 + Double(idx) * 0.08), value: appear)
            }
        }
    }

    private func gameAccent(_ game: GameTarget) -> Color {
        game == .freefireTH
            ? Color(red: 1.0, green: 0.42, blue: 0.2)
            : Color(red: 0.35, green: 0.55, blue: 1.0)
    }

    private func gameIconGradient(_ game: GameTarget) -> LinearGradient {
        if game == .freefireTH {
            return LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.15),
                                           Color(red: 0.9, green: 0.18, blue: 0.15)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [Color(red: 0.45, green: 0.6, blue: 1.0),
                                       Color(red: 0.5, green: 0.25, blue: 0.95)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func detectPill(_ found: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(found ? Color.green : Color.red.opacity(0.85))
                .frame(width: 6, height: 6)
            Text(found
                 ? model.tr("Đã phát hiện", "Detected")
                 : model.tr("Không phát hiện", "Not found"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.cardHi)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.borderHi, lineWidth: 1))
    }

    // MARK: hint

    private var hint: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
            Text(model.tr("Chọn game → chỉnh chức năng → bấm INJECT",
                          "Pick a game → tweak features → tap INJECT"))
                .font(.caption2)
            Spacer()
        }
        .foregroundColor(Theme.dimmer)
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .opacity(appear ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.3), value: appear)
    }
}
