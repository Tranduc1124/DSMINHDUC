import SwiftUI

/// Main screen: hero card (logo + device stats) + game list. Monochrome theme.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var gate = LicenseGate.shared
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
                    antibanCard
                    resetGuestCard
                    gameList
                    hint
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .safeAreaInset(edge: .bottom) { keyBar }
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
                        .shadow(color: .white.opacity(0.18), radius: 16, y: 4)
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(.black)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("BOLAMINHDUC")
                        .font(.headline.weight(.heavy))
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
                         value: (model.mhaActive || ExploitRunner.isSupported()) ? model.tr("Tốt", "Good") : model.tr("Hạn chế", "Limited"))
            }
            .padding(.vertical, 11)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
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

    // MARK: anti-ban

    private var antibanCard: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.cardHi)
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.tr("Anti-ban", "Anti-ban"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(gate.state == .authorized
                     ? model.tr("Mặc định tắt mỗi lần mở app — bật lại khi cần",
                                "Off by default each launch — enable when needed")
                     : model.tr("🔑 Nhập key trước để bật", "🔑 Activate your key first"))
                    .font(.caption2)
                    .foregroundColor(Theme.dim)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.antiban },
                set: { model.setAntiban($0) }
            ))
            .labelsHidden()
            .tint(.white)
            .disabled(gate.state != .authorized)
            .opacity(gate.state == .authorized ? 1 : 0.4)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 12)
        .animation(.easeOut(duration: 0.4).delay(0.06), value: appear)
    }

    // MARK: reset guest

    private var resetGuestCard: some View {
        Button {
            model.resetGuest()
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Theme.cardHi)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.tr("Reset Guest", "Reset Guest"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text(model.tr("Xoá định danh khách — mở game tạo guest mới (tắt hẳn game trước!)",
                                  "Wipe the guest identity — relaunch to create a new guest (force-close first!)"))
                        .font(.caption2)
                        .foregroundColor(Theme.dim)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
            }
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 12)
        .animation(.easeOut(duration: 0.4).delay(0.09), value: appear)
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
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Theme.cardHi)
                                .frame(width: 52, height: 52)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                            Image(systemName: game == .freefireTH ? "flame.fill" : "bolt.fill")
                                .font(.system(size: 21, weight: .semibold))
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
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
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

    private func detectPill(_ found: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(found ? Color.white : Theme.dimmer)
                .frame(width: 6, height: 6)
            Text(found
                 ? model.tr("Đã phát hiện", "Detected")
                 : model.tr("Không thấy game", "Not found"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(found ? .white : Theme.dim)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.cardHi)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
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

    // MARK: key bar (DEMO — real key system later)

    private var keyBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.cardHi)
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                Image(systemName: "key.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.tr("KEY", "KEY"))
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Theme.dimmer)
                Text(model.keyMaskedName.isEmpty ? "—" : model.keyMaskedName)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(model.keyHoursLeft < 0
                     ? model.tr("--", "--")
                     : model.tr("\(model.keyHoursLeft) giờ", "\(model.keyHoursLeft)h"))
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Theme.cardHi)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 14)
        .animation(.easeOut(duration: 0.4).delay(0.25), value: appear)
    }
}
