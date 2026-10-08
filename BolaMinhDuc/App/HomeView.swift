import SwiftUI

/// Main screen: header + status chips + game list. No tab bar.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    var openGame: (GameTarget) -> Void
    var openSettings: () -> Void

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    header
                    chips
                    gameList
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 34, height: 34)
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("BOLAMINHDUC")
                    .font(.headline.weight(.heavy))
                    .foregroundColor(.white)
                    .tracking(0.5)
                Text(DeviceInfo.appVersion)
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
                    .frame(width: 38, height: 38)
                    .background(Theme.card)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    // MARK: chips

    private var chips: some View {
        HStack(spacing: 8) {
            chip(title: "THIẾT BỊ", value: DeviceInfo.machine, valueColor: .white)
            chip(title: "HỆ ĐIỀU HÀNH", value: DeviceInfo.iosVersion, valueColor: .white)
            chip(title: "KERNEL",
                 value: ExploitRunner.isSupported() ? "Hỗ trợ" : "?",
                 valueColor: statusColor)
        }
    }

    private func chip(title: String, value: String, valueColor: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.dimmer)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    // MARK: games

    private var gameList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHỌN GAME")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.dim)
                .tracking(1)
                .padding(.top, 4)

            ForEach(GameTarget.allCases) { game in
                Button {
                    openGame(game)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.cardHi)
                                .frame(width: 46, height: 46)
                            Image(systemName: game == .freefireTH ? "flame.fill" : "bolt.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.title)
                                .font(.headline.weight(.bold))
                                .foregroundColor(.white)
                            Text("Chỉnh chức năng & INJECT")
                                .font(.caption)
                                .foregroundColor(Theme.dim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.dimmer)
                    }
                    .padding(14)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(model.statusText)
                .font(.caption)
                .foregroundColor(Theme.dim)
                .lineLimit(2)
            Spacer()
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .padding(.top, 2)
    }

    private var statusColor: Color {
        switch model.phase {
        case .idle: return Theme.dimmer
        case .running: return .yellow
        case .active: return .green
        case .failed: return .red
        }
    }
}
