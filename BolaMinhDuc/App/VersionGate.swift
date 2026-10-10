import SwiftUI
import UIKit

/// Kiểm tra phiên bản app với server: nếu server BẬT "chặn bản cũ" và bản
/// này cũ hơn (hoặc hash khác) -> hiện popup TO GIỮA MÀN HÌNH không bỏ qua.
final class VersionGate: ObservableObject {
    static let shared = VersionGate()

    @Published var blocked = false
    @Published var message = ""
    @Published var downloadURL = ServerConfig.base + "/download/latest"
    @Published var latestVersion = ""

    func check() {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        PatchClient.check(
            version: version,
            sha256: "",
            license: LicenseGate.shared.licenseKey,
            device: ServerConfig.deviceId
        ) { [weak self] json in
            guard let self = self else { return }
            self.blocked = (json["block"] as? Bool) ?? false
            self.message = (json["message"] as? String) ?? ""
            self.latestVersion = (json["latestVersion"] as? String) ?? ""
            if let url = json["downloadUrl"] as? String, !url.isEmpty {
                self.downloadURL = url
            }
        }
    }
}

/// Popup chặn bản cũ — phủ toàn màn hình, chỉ có nút tải bản mới.
struct BlockOverlay: View {
    @ObservedObject private var gate = VersionGate.shared

    var body: some View {
        Group {
            if gate.blocked {
                ZStack {
                    Color.black.opacity(0.94).ignoresSafeArea()

                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 46, weight: .semibold))
                            .foregroundColor(.orange)
                        Text("PHIÊN BẢN CŨ")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundColor(.white)
                        Text(gate.message.isEmpty
                             ? "Bạn đang sử dụng phiên bản cũ. Vui lòng tải bản mới nhất để tiếp tục!"
                             : gate.message)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                        if !gate.latestVersion.isEmpty {
                            Text("Bản mới nhất: \(gate.latestVersion)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.orange)
                        }
                        Button {
                            if let url = URL(string: gate.downloadURL) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("⬇️  TẢI BẢN MỚI NHẤT")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundColor(.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .background(Color.orange)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(26)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                    )
                    .padding(26)
                }
                .transition(.opacity)
                .zIndex(999)
            }
        }
    }
}
