import SwiftUI
import Foundation

/// Feature config for one game: ESP / AIM / MISC tabs + inject area.
struct ConfigView: View {
    @EnvironmentObject private var model: AppModel
    let game: GameTarget
    var goBack: () -> Void

    @State private var tab: FeatureTab = .esp
    @State private var colorPickKey: String? = nil

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

            if let ck = colorPickKey {
                colorPickerOverlay(ck)
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: colorPickKey)
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
            colorFeatureCard("box", "square.dashed", "Box",
                             model.tr("Khung quanh người & bot", "Box around players & bots"))
            colorFeatureCard("line", "line.diagonal", "Line",
                             model.tr("Đường kẻ từ tâm ngắm", "Line from the crosshair"))
            colorFeatureCard("bone", "figure.walk", "Bone",
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
        case .aim:
            aimCard
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

    private func colorFeatureCard(_ key: String, _ icon: String,
                                  _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 0) {
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

            if model.flag(key) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: 1)
                        .padding(.leading, 52)
                    Button {
                        colorPickKey = key
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 26)
                            Text(model.tr("Màu hiển thị", "Display color"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.dim)
                            Spacer()
                            Circle()
                                .fill(model.featureColor(key))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Theme.borderHi, lineWidth: 1))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.dimmer)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowButtonStyle())
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: model.flag(key))
    }

    private func colorTitle(_ key: String) -> String {
        if key == "box" {
            return model.tr("Màu Box", "Box color")
        }
        if key == "line" {
            return model.tr("Màu Line", "Line color")
        }
        return model.tr("Màu Bone", "Bone color")
    }

    private func colorPickerOverlay(_ key: String) -> some View {
        let (r, g, b) = model.featureRGB(key)
        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture {
                    colorPickKey = nil
                }
            CustomColorPickerPanel(
                title: colorTitle(key),
                initial: (r, g, b),
                onChange: { nr, ng, nb in
                    model.setFeatureColor(key, Color(red: nr, green: ng, blue: nb))
                },
                onClose: {
                    colorPickKey = nil
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private var aimCard: some View {
        VStack(spacing: 0) {
            toggleRowInline("aim", "scope", "Aimbot",
                            model.tr("Khoá địch gần tâm ngắm nhất", "Lock the enemy nearest the crosshair"))
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.leading, 52)
            toggleRowInline("silent", "cursorarrow.rays", model.tr("Aim Silent", "Silent Aim"),
                            model.tr("Bắn lệch vẫn bay vào bone đã chọn", "Shots bend into the selected bone"))
            if model.flag("aim") || model.flag("silent") {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: 1)
                        .padding(.leading, 52)
                    boneSection
                    if model.flag("silent") {
                        Rectangle()
                            .fill(Theme.border)
                            .frame(height: 1)
                            .padding(.leading, 52)
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "circle.dashed")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 26)
                                Text(model.tr("FOV", "FOV"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(model.silentFov)%")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(Theme.dim)
                            }
                            Slider(value: Binding(
                                get: { Double(model.silentFov) },
                                set: { model.setSilentFov(Int($0)) }
                            ), in: 5...100, step: 5)
                            .tint(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        Rectangle()
                            .fill(Theme.border)
                            .frame(height: 1)
                            .padding(.leading, 52)
                        toggleRowInline("showfov", "circle.dashed", model.tr("Hiện vòng FOV", "Show FOV circle"),
                                        model.tr("Ẩn/hiện vòng tròn FOV trên màn hình", "Show or hide the FOV circle on screen"))
                        Rectangle()
                            .fill(Theme.border)
                            .frame(height: 1)
                            .padding(.leading, 52)
                        toggleRowInline("skipknock", "figure.fall", model.tr("Bỏ qua gục", "Skip knocked"),
                                        model.tr("Không bắn vào địch đã bị hạ gục", "Don't shoot knocked-down enemies"))
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: model.flag("aim"))
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: model.flag("silent"))
    }

    private func toggleRowInline(_ key: String, _ icon: String,
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
    }

    private var boneSection: some View {
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
        .padding(.vertical, 11)
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


/// self-made HSV color picker panel (no system color picker)
struct CustomColorPickerPanel: View {
    let title: String
    let onChange: (Double, Double, Double) -> Void
    let onClose: () -> Void

    @State private var hue: Double
    @State private var sat: Double
    @State private var val: Double

    static let presets: [(Double, Double, Double)] = [
        (1.00, 0.15, 0.15),
        (1.00, 0.55, 0.10),
        (1.00, 0.85, 0.10),
        (0.55, 1.00, 0.35),
        (0.10, 1.00, 0.10),
        (0.10, 0.90, 1.00),
        (0.25, 0.50, 1.00),
        (0.65, 0.30, 1.00),
        (1.00, 0.30, 0.65),
        (1.00, 1.00, 1.00)
    ]

    init(title: String,
         initial: (Double, Double, Double),
         onChange: @escaping (Double, Double, Double) -> Void,
         onClose: @escaping () -> Void) {
        self.title = title
        self.onChange = onChange
        self.onClose = onClose
        let hsv = CustomColorPickerPanel.rgbToHSV(initial.0, initial.1, initial.2)
        _hue = State(initialValue: hsv.0)
        _sat = State(initialValue: hsv.1)
        _val = State(initialValue: hsv.2)
    }

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            HStack(spacing: 10) {
                Text(title)
                    .font(.headline.weight(.heavy))
                    .foregroundColor(.white)
                Spacer()
                Text(Self.hex(hue: hue, sat: sat, val: val))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.dim)
                Circle()
                    .fill(Color(hue: hue, saturation: sat, brightness: val))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(Theme.borderHi, lineWidth: 1))
            }

            GeometryReader { geo in
                let w = Double(geo.size.width)
                let h = Double(geo.size.height)
                ZStack(alignment: .topLeading) {
                    Color(hue: hue, saturation: 1, brightness: 1)
                    LinearGradient(
                        gradient: Gradient(colors: [Color.white, Color.white.opacity(0)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0), Color.black]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Circle()
                        .fill(Color(hue: hue, saturation: sat, brightness: val))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .offset(x: CGFloat(max(0, min(w - 18, sat * w - 9))),
                                y: CGFloat(max(0, min(h - 18, (1 - val) * h - 9))))
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let s = max(0, min(1, Double(g.location.x) / max(1.0, w)))
                            let v2 = max(0, min(1, 1 - Double(g.location.y) / max(1.0, h)))
                            sat = s
                            val = v2
                            let rgb = Self.hsvToRGB(hue, s, v2)
                            onChange(rgb.0, rgb.1, rgb.2)
                        }
                )
            }
            .frame(height: 130)

            gradientSlider(
                Gradient(colors: [
                    Color(hue: 0.00, saturation: 1, brightness: 1),
                    Color(hue: 0.17, saturation: 1, brightness: 1),
                    Color(hue: 0.33, saturation: 1, brightness: 1),
                    Color(hue: 0.50, saturation: 1, brightness: 1),
                    Color(hue: 0.67, saturation: 1, brightness: 1),
                    Color(hue: 0.83, saturation: 1, brightness: 1),
                    Color(hue: 1.00, saturation: 1, brightness: 1)
                ]),
                value: hue
            ) { v in
                hue = v
                let rgb = Self.hsvToRGB(v, sat, val)
                onChange(rgb.0, rgb.1, rgb.2)
            }

            HStack(spacing: 7) {
                ForEach(0..<Self.presets.count, id: \.self) { i in
                    let p = Self.presets[i]
                    Button {
                        let hsv = Self.rgbToHSV(p.0, p.1, p.2)
                        hue = hsv.0
                        sat = hsv.1
                        val = hsv.2
                        onChange(p.0, p.1, p.2)
                    } label: {
                        Circle()
                            .fill(Color(red: p.0, green: p.1, blue: p.2))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Theme.borderHi, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                onClose()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                    Text("OK")
                        .font(.subheadline.weight(.heavy))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Theme.cardHi)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.borderHi, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }

    private func gradientSlider(_ gradient: Gradient, value: Double,
                                 update: @escaping (Double) -> Void) -> some View {
        GeometryReader { geo in
            let w = Double(geo.size.width)
            ZStack(alignment: .leading) {
                LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 20)
                    .clipShape(Capsule())
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .offset(x: CGFloat(max(0, min(w - 14, value * w - 7))))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = Double(g.location.x) / max(1.0, w)
                        update(max(0, min(1, v)))
                    }
            )
        }
        .frame(height: 26)
    }

    static func hex(hue: Double, sat: Double, val: Double) -> String {
        let (r, g, b) = hsvToRGB(hue, sat, val)
        let ri = Int(max(0, min(255, (r * 255).rounded())))
        let gi = Int(max(0, min(255, (g * 255).rounded())))
        let bi = Int(max(0, min(255, (b * 255).rounded())))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    static func hsvToRGB(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    static func rgbToHSV(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxv = max(r, max(g, b))
        let minv = min(r, min(g, b))
        let d = maxv - minv
        var h = 0.0
        if d > 0.0001 {
            if maxv == r {
                h = ((g - b) / d).truncatingRemainder(dividingBy: 6) / 6
            } else if maxv == g {
                h = (((b - r) / d) + 2) / 6
            } else {
                h = (((r - g) / d) + 4) / 6
            }
            if h < 0 {
                h += 1
            }
        }
        let s = maxv <= 0.0001 ? 0 : d / maxv
        return (h, s, maxv)
    }
}
