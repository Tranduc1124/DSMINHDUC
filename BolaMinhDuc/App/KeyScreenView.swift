import SwiftUI

/// Màn hình ĐẦU TIÊN: nhập license key. Chỉ sau khi key hợp lệ
/// (Tserver xác nhận) mới vào giao diện chính.
struct KeyScreenView: View {
    @ObservedObject private var gate = LicenseGate.shared
    @State private var key = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(y: -180)
                .allowsHitTesting(false)

            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundColor(.white)
                Text("BOLAMINHDUC")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(.white)
                    .tracking(1)
                Text(gate.errorText.isEmpty
                     ? "Nhập license key để tiếp tục"
                     : gate.errorText)
                    .font(.footnote)
                    .foregroundColor(gate.errorText.isEmpty ? Theme.dim : .red)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .foregroundColor(.white)
                    TextField("License key…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .foregroundColor(.white)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
                .padding(13)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )

                Button {
                    gate.confirm(key)
                } label: {
                    HStack(spacing: 8) {
                        if gate.busy {
                            ProgressView().tint(.black)
                        }
                        Text(gate.busy ? "ĐANG KIỂM TRA…" : "KÍCH HOẠT")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .disabled(gate.busy || key.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(gate.busy || key.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1)
                .buttonStyle(.plain)

                if !gate.statusText.isEmpty {
                    Text("Trạng thái: \(gate.statusText)")
                        .font(.caption2)
                        .foregroundColor(Theme.dimmer)
                }

                Spacer()
                Text("Chưa có key? Liên hệ admin để mua.")
                    .font(.caption2)
                    .foregroundColor(Theme.dimmer)
                    .padding(.bottom, 10)
            }
            .padding(22)
        }
    }
}
