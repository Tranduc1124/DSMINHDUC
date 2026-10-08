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
                    }
                    .padding(.bottom, 8)
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
                Text("Chỉnh chức năng")
                    .font(.caption2)
                    .foregroundColor(Theme.dim)
            }
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
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
            toggleRow("box", "square.dashed", "Box", "Khung quanh người & bot")
            toggleRow("line", "line.diagonal", "Line", "Đường kẻ từ tâm ngắm")
            toggleRow("bone", "figure.walk", "Bone", "Khung xương người (skeleton)")
            toggleRow("hp", "heart.fill", "Máu", "Thanh HP cho người & bot")
            toggleRow("name", "textformat", "Tên", "Tên người chơi / bot")
            toggleRow("dist", "ruler", "Khoảng cách", "Khoảng cách tới mục tiêu")
            toggleRow("bot", "cpu", "Bot", "Hiện cả bot (AI)")
            toggleRow("count", "number", "Đếm Địch", "Số địch + bot ở trên màn hình")
        case .aim:
            toggleRow("aim", "scope", "Aimbot", "Khoá mục tiêu gần tâm nhất trong FOV")
            boneRow
            toggleRow("fov", "circle.dashed", "Vòng FOV", "Vòng tròn phạm vi khoá mục tiêu")
            if model.flag("fov") {
                fovRow
            }
        case .misc:
            placeholderRow("figure.run", "Tốc chạy", "Tăng tốc di chuyển")
            placeholderRow("arrow.up", "Nhảy cao", "Nhảy cao hơn")
            placeholderRow("infinity", "Đạn vô hạn", "Không giới hạn đạn")
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

    private var fovRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "circle.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 26)
                Text("Bán kính FOV")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(model.fovRadius))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(Theme.dim)
            }
            Slider(value: Binding(
                get: { model.fovRadius },
                set: { model.setFovRadius($0) }
            ), in: 8...40, step: 1, onEditingChanged: { editing in
                if !editing {
                    model.writeConfig()
                }
            })
            .tint(.white)
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

    private var boneRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 26)
                Text("Vị trí khoá")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            HStack(spacing: 8) {
                bonePill(0, "Đầu")
                bonePill(1, "Cổ")
                bonePill(2, "Ngực")
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

    private func placeholderRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("SẮP CÓ")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.85))
                        .clipShape(Capsule())
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(Theme.dimmer)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: .constant(false))
                .labelsHidden()
                .disabled(true)
                .opacity(0.4)
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
                        Text(model.restoring ? "ĐANG GỠ PATCH…"
                             : (model.busy ? "HỦY INJECT"
                             : (model.patchInstalled ? "HỦY INJECT" : "INJECT")))
                            .tracking(1.2)
                    }
                    .font(.title3.weight(.black))
                    Text(model.restoring ? "vui lòng đợi"
                         : (model.busy ? "nhấn để huỷ"
                         : (model.patchInstalled ? "gỡ patch khỏi game" : "cài patch & mở game")))
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
    }
}

/// inject button: white when idle, outlined dark when busy (HỦY INJECT)
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
    }
}
