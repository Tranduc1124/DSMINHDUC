import SwiftUI

/// Màn hình CHỜ XÁC THỰC: hệ thống key của Tserver TỰ HIỆN bảng nhập key
/// (UI pack trong SDK) khi cần. Không làm form riêng theo yêu cầu.
struct KeyScreenView: View {
    @ObservedObject private var gate = LicenseGate.shared
    @State private var pulse = false

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
                    .scaleEffect(pulse ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)

                Text("BOLAMINHDUC")
                    .font(.system(size: 25, weight: .heavy))
                    .foregroundColor(.white)
                    .tracking(1)

                HStack(spacing: 8) {
                    ProgressView().tint(.white.opacity(0.8))
                    Text("Đang kết nối hệ thống key…")
                        .font(.footnote)
                        .foregroundColor(Theme.dim)
                }
                .padding(.top, 4)

                if !gate.statusText.isEmpty {
                    Text(gate.statusText)
                        .font(.caption2)
                        .foregroundColor(Theme.dimmer)
                }
                if !gate.errorText.isEmpty {
                    Text(gate.errorText)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                // nếu bảng nhập key của hệ thống chưa hiện, bấm để mở lại
                Button {
                    LicenseGate.shared.startIfNeeded()
                } label: {
                    Text("MỞ BẢNG NHẬP KEY")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 10)

                Spacer()
                Text("Chưa có key? Liên hệ admin để mua.")
                    .font(.caption2)
                    .foregroundColor(Theme.dimmer)
                    .padding(.bottom, 10)
            }
            .padding(22)
        }
        .onAppear { pulse = true }
    }
}
