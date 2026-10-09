import SwiftUI

/// Feature config for one game: ESP / AIM / MISC tabs + inject area.
struct ConfigView: View {
    @EnvironmentObject private var model: AppModel
    let game: GameTarget
    var goBack: () -> Void

    @State private var tab: FeatureTab = .esp

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 12) {
                header
                segment
                ScrollView {
                    VStack(spacing: 10) {
                        tabContent
                            .id(tab)
                            .transition(.opacity)
                    }
                    .padding(.bottom, 8)
                    .animation(.easeInOut(duration: 0.22), value: tab)
                }
                injectArea
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.card)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(game.title)
                    .font(.headline.weight(.heavy))
                    .foregroundColor(.white)
                Text(model.tr("Chỉnh chức năng", "Features"))
                    .font(.caption2)
                    .foregroundColor(Theme.dim)
            }
            Spacer()
            StatusDot(color: statusColor)
                .animation(.easeInOut(duration: 0.3), value: model.phase)
        }
    }

    // MARK: ESP / AIM / MISC

    private var segment: some View {
        HStack(spacing: 6) {
            ForEach(FeatureTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(SegmentButtonStyle(active: tab == item))
            }
        }
        .padding(4)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .esp:
            toggleRow("box", "square.dashed", "Box",
                      model.tr("Khung quanh người & bot", "Box around players & bots"))
            toggleRow("line", "line.diagonal", "Line",
                      model.tr("Đường kẻ từ tâm ngắm", "Line from the crosshair"))
            toggleRow("bone", "figure.walk", "Bone",
                      model.tr("Khung xương người (skeleton)", "Player skeleton"))
            toggleRow("hp", "heart.fill", model.tr("Máu", "Health"),
                      model.tr("Thanh HP cho người & bot", "HP bar for players & bots"))
            toggleRow("name", "textformat", model.tr("Tên", "Name"),
                      model.tr("Tên người chơi / bot", "Player / bot name"))
            toggleRow("dist", "ruler", model.tr("Khoảng cách", "Distance"),
                      model.tr("Khoảng cách tới mục tiêu", "Distance to the target"))
            toggleRow("bot", "cpu", "Bot",
                      model.tr("Hiện cả bot (AI)", "Show bots (AI) too"))
            toggleRow("count", "number", model.tr("Đếm Địch", "Enemy Count"),
                      model.tr("Số địch + bot ở trên màn hình", "Enemies + bots shown on screen"))
            colorRow("box", "square.dashed", model.tr("Màu Box", "Box color"))
            colorRow("line", "line.diagonal", model.tr("Màu Line", "Line color"))
            colorRow("bone", "figure.walk", model.tr("Màu Bone", "Bone color"))
        case .aim:
            toggleRow("aim", "scope", "Aimbot",
                      model.tr("Khoá địch gần tâm ngắm nhất", "Lock the enemy nearest the crosshair"))
            boneRow
        case .misc:
            comingSoonCard
        }
    }

    // MARK: rows

    private func toggleRow(_ key: String, _ icon: String,
                           _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(Theme.dimmer)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.flag(key) },
                set: { model.setFlag(key, $0) }
            ))
            .labelsHidden()
            .tint(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func colorRow(_ key: String, _ icon: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 26)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { model.featureColor(key) },
                set: { model.setFeatureColor(key, $0) }
            ), supportsOpacity: false)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var boneRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 26)
                Text(model.tr("Vị trí khoá", "Lock position"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            HStack(spacing: 8) {
                bonePill(0, model.tr("Đầu", "Head"))
                bonePill(1, model.tr("Cổ", "Neck"))
                bonePill(2, model.tr("Ngực", "Chest"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func bonePill(_ value: Int, _ title: String) -> some View {
        Button {
            model.setBone(value)
        } label: {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundColor(model.aimBone == value ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(model.aimBone == value ? Color.white : Theme.cardHi)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(model.aimBone == value ? Color.clear : Theme.borderHi, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var comingSoonCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
            Text(model.tr("Đang phát triển", "Coming soon"))
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
            Text(model.tr("Các chức năng mới sẽ được thêm trong bản cập nhật sau",
                          "New features will arrive in a future update"))
                .font(.caption)
                .foregroundColor(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .padding(.top, 6)
    }

    // MARK: inject

    private var injectArea: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text(model.installedInfo)
                    .font(.caption2)
                    .lineLimit(2)
                Spacer()
            }
            .foregroundColor(Theme.dim)

            Button {
                if model.busy {
                    if !model.restoring {
                        model.cancelInject()
                    }
                } else if model.patchInstalled {
                    model.restore()
                } else {
                    model.inject()
                }
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: model.restoring ? "hourglass"
                              : (model.busy ? "xmark"
                              : (model.patchInstalled ? "xmark.circle" : "bolt.fill")))
                        Text(model.restoring
                             ? model.tr("ĐANG GỠ…", "REMOVING…")
                             : (model.busy
                                ? model.tr("HỦY INJECT", "CANCEL")
                                : (model.patchInstalled
                                   ? model.tr("HỦY INJECT", "CANCEL")
                                   : "INJECT")))
                            .tracking(1.2)
                    }
                    .font(.title3.weight(.black))
                    Text(model.restoring
                         ? model.tr("vui lòng đợi", "please wait")
                         : (model.busy
                            ? model.tr("nhấn để huỷ", "tap to cancel")
                            : (model.patchInstalled
                               ? model.tr("gỡ khỏi game", "remove from the game")
                               : model.tr("cài & mở game", "install & open the game"))))
                        .font(.caption2.weight(.medium))
                        .opacity(0.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
            }
            .buttonStyle(InjectButtonStyle(busy: model.busy || model.patchInstalled))
            .disabled(model.restoring)
            .opacity(model.restoring ? 0.55 : 1)
        }
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

enum FeatureTab: String, CaseIterable, Identifiable {
    case esp, aim, misc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .esp: return "ESP"
        case .aim: return "AIM"
        case .misc: return "MISC"
        }
    }
}

/// white pill when active, transparent otherwise
struct SegmentButtonStyle: ButtonStyle {
    var active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(active ? .black : .white)
            .background(active ? Color.white.opacity(configuration.isPressed ? 0.75 : 1)
                               : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// inject button: white when idle, outlined dark when busy (CANCEL)
struct InjectButtonStyle: ButtonStyle {
    var busy: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(busy ? .white : .black)
            .background(busy ? Theme.cardHi.opacity(configuration.isPressed ? 0.7 : 1)
                             : Color.white.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(busy ? Theme.borderHi : Color.clear, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
