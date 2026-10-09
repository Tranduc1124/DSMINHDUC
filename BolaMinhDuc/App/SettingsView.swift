import SwiftUI

/// CÀI ĐẶT — Delta-style sheet: big header, rounded rows card, language picker.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var openLanguage: () -> Void

    @State private var appear = false
    @State private var showPairing = false

    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Color.white.opacity(0.045))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(y: -190)
                .allowsHitTesting(false)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    rowsCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 32)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 14)
                .animation(.easeOut(duration: 0.35), value: appear)
                .onAppear {
                    appear = true
                    model.refreshPairing()
                }
            }
            if showPairing {
                pairingPanel
                    .zIndex(6)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: showPairing)
        .toastOverlay($model.toastText)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 54, height: 54)
                    .shadow(color: .white.opacity(0.16), radius: 14, y: 4)
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundColor(.black)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.tr("Cài Đặt", "Settings"))
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)
                Text("BOLAMINHDUC \(DeviceInfo.appVersion)")
                    .font(.footnote)
                    .foregroundColor(Theme.dim)
            }
            Spacer()
        }
        .padding(.bottom, 6)
    }

    // MARK: rows

    private var rowsCard: some View {
        VStack(spacing: 0) {
            row(icon: "globe",
                title: model.tr("Ngôn ngữ", "Language"),
                subtitle: model.language == "en" ? "English" : "Tiếng Việt") {
                openLanguage()
            }
            divider
            row(icon: "link.circle.fill",
                title: model.tr("Ghép đôi thiết bị", "Device pairing"),
                subtitle: model.pairingValid
                    ? model.tr("Đã có file ghép đôi", "Pairing file found")
                    : model.tr("Chưa có file ghép đôi", "No pairing file")) {
                model.refreshPairing()
                showPairing = true
            }
            divider
            row(icon: "trash",
                title: model.tr("Xoá Bộ Nhớ Đệm", "Clear Cache"),
                subtitle: model.tr("File tạm trong app", "Temporary app files")) {
                model.clearCache()
            }
            divider
            row(icon: "info.circle",
                title: model.tr("Thông Tin Ứng Dụng", "App Info"),
                subtitle: model.tr("Phiên bản • thiết bị", "Version • device")) {
                model.showToast("BOLAMINHDUC \(DeviceInfo.appVersion)\n\(model.tr("Thiết bị", "Device")): \(DeviceInfo.machine)\niOS: \(DeviceInfo.iosVersion)")
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func row(icon: String, title: String, subtitle: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.cardHi)
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.dim)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.dimmer)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 66)
    }

    // MARK: pairing panel

    private var pairingPanel: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture {
                    showPairing = false
                }
            VStack(spacing: 12) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                HStack(spacing: 10) {
                    Image(systemName: model.pairingValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(model.pairingValid ? .green : .yellow)
                    Text(model.tr("Ghép đôi thiết bị", "Device pairing"))
                        .font(.headline.weight(.heavy))
                        .foregroundColor(.white)
                    Spacer()
                }
                if let pin = model.pairingPin {
                    HStack(spacing: 10) {
                        Image(systemName: "number.square.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.tr("Mã ghép đôi", "Pair code"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Theme.dimmer)
                            Text(pin)
                                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Text(model.tr("nhập mã trên máy", "type it on the device"))
                            .font(.caption2)
                            .foregroundColor(Theme.dim)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.borderHi, lineWidth: 1)
                    )
                }
                if model.pairingValid {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.pairingName ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if let pid = model.pairingIdentifier {
                            Text(pid)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.dim)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Text(model.tr("Chép file ghép đôi (.mobiledevicepairing) từ máy tính vào thư mục BOLAMINHDUC trong Files, rồi bấm Làm mới.",
                              "Copy the pairing file (.mobiledevicepairing) from your computer into the BOLAMINHDUC folder in Files, then tap Refresh."))
                    .font(.caption2)
                    .foregroundColor(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                pillButton(model.pairingBusy
                           ? model.tr("Đang tạo…", "Generating…")
                           : model.tr("Tạo trên máy", "Generate on-device"),
                           primary: false) {
                    model.generatePairingOnDevice()
                }
                .disabled(model.pairingBusy)
                .opacity(model.pairingBusy ? 0.6 : 1)
                Text(model.tr("Bật LocalDevVPN trước, rồi bấm “Tạo trên máy” và làm theo hướng dẫn trên máy.",
                              "Turn on LocalDevVPN first, then tap “Generate on-device” and follow the on-screen prompts."))
                    .font(.caption2)
                    .foregroundColor(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    pillButton(model.tr("Làm mới", "Refresh"), primary: false) {
                        model.refreshPairing()
                    }
                    if model.pairingValid {
                        pillButton(model.tr("Xoá", "Delete"), primary: false) {
                            model.removePairingFile()
                        }
                    }
                    pillButton("OK", primary: true) {
                        showPairing = false
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(Theme.cardHi)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.borderHi, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func pillButton(_ title: String, primary: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundColor(primary ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(primary ? Color.white : Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(primary ? Color.clear : Theme.borderHi, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

}
