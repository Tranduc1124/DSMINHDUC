import SwiftUI

/// Tab 1 — INJECT: device/status chips, game and one white INJECT button.
struct InjectView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                chips
                gameCard
                injectButton
                extraRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.shield.fill")
                .font(.title3)
                .foregroundColor(.white)
            Text("BOLAMINHDUC")
                .font(.headline.weight(.heavy))
                .foregroundColor(.white)
                .tracking(0.5)
            Text(DeviceInfo.appVersion)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.9))
                .clipShape(Capsule())
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
        }
        .padding(.top, 4)
    }

    // MARK: chips (THIẾT BỊ / HỆ ĐIỀU HÀNH / TRẠNG THÁI)

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

    // MARK: game

    private var gameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRÒ CHƠI")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.dim)
                .tracking(1)

            HStack(spacing: 8) {
                ForEach(GameTarget.allCases) { game in
                    Button {
                        model.game = game
                        model.refreshInstalled()
                    } label: {
                        Text(game.title)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(PillButtonStyle(active: model.game == game))
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text(model.installedInfo)
                    .font(.caption)
                    .lineLimit(2)
            }
            .foregroundColor(Theme.dim)
        }
        .card()
    }

    // MARK: inject

    private var injectButton: some View {
        Button {
            model.inject()
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text("INJECT")
                        .tracking(1.5)
                }
                .font(.title3.weight(.black))
                Text("tự cài patch & mở game")
                    .font(.caption2.weight(.medium))
                    .opacity(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(WhiteButtonStyle())
        .disabled(model.busy)
        .opacity(model.busy ? 0.5 : 1)
    }

    private var extraRow: some View {
        Button {
            model.restore()
        } label: {
            Label("Xoá patch khỏi game", systemImage: "trash")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(GhostButtonStyle())
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

/// small pill button used for the game selector (active = white, inactive = dark)
struct PillButtonStyle: ButtonStyle {
    var active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(active ? .black : .white)
            .background(active ? Color.white.opacity(configuration.isPressed ? 0.75 : 1)
                               : Theme.cardHi.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(active ? Color.clear : Theme.borderHi, lineWidth: 1)
            )
    }
}
