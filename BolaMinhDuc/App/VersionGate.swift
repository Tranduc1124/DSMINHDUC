import SwiftUI
import UIKit

/// Kiểm tra server cho TỪNG sản phẩm (bola / intexx):
/// - Server chặn bản cũ (version gate) → popup không bỏ qua, có nút tải bản mới.
/// - Server KILL sản phẩm (tắt tay hoặc quá ngày chết) → popup "NGỪNG HOẠT
///   ĐỘNG" không còn nút nào — app chết hẳn, inject bị chặn.
/// - Bản có cấu hình offline (vd IntexX): quá N ngày không xác thực được với
///   server → coi như bị kill (chống tắt mạng để né kill-switch).
final class VersionGate: ObservableObject {
    static let shared = VersionGate()

    @Published var blocked = false
    @Published var killed = false
    @Published var message = ""
    @Published var downloadURL = ServerConfig.base + "/download/latest"
    @Published var latestVersion = ""

    private var timer: Timer?
    private let lastOkKey = "bola_last_server_ok"

    func check() {
        // Luật offline (chỉ áp cho bản có cấu hình, vd IntexX): quá N ngày
        // không xác thực được với server -> dừng hoạt động.
        let maxDays = LicenseGate.offlineMaxDays
        if maxDays > 0 {
            let last = UserDefaults.standard.double(forKey: lastOkKey)
            if last > 0, Date().timeIntervalSince1970 - last > Double(maxDays) * 86400 {
                killed = true
                blocked = true
                message = "Cần kết nối mạng để xác thực (\(maxDays) ngày một lần)."
            }
        }

        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        PatchClient.check(
            version: version,
            sha256: "",
            license: LicenseGate.shared.licenseKey,
            device: ServerConfig.deviceId
        ) { [weak self] json in
            guard let self = self else { return }
            if (json["killed"] as? Bool) == true {
                killed = true
                blocked = true
                message = (json["message"] as? String) ?? "Bản này đã ngừng hoạt động."
                return
            }
            let blockedNow = (json["block"] as? Bool) ?? false
            blocked = blockedNow
            killed = false
            message = (json["message"] as? String) ?? ""
            latestVersion = (json["latestVersion"] as? String) ?? ""
            if let url = json["downloadUrl"] as? String, !url.isEmpty {
                downloadURL = url
            }
            if !blockedNow {
                // server trả lời OK → ghi mốc để tính luật offline
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self.lastOkKey)
            }
        }
    }

    /// Kiểm tra định kỳ 10 phút/lần — kill-switch áp dụng nhanh cả khi app mở lâu.
    func startPeriodic() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.check()
        }
    }
}

/// Popup chặn — phủ toàn màn hình.
/// Bản cũ: chỉ có nút tải bản mới. Bản bị KILL: không còn lối thoát.
struct BlockOverlay: View {
    @ObservedObject private var gate = VersionGate.shared

    var body: some View {
        Group {
            if gate.blocked {
                ZStack {
                    Color.black.opacity(0.94).ignoresSafeArea()

                    VStack(spacing: 16) {
                        Image(systemName: gate.killed
                              ? "nosign"
                              : "exclamationmark.triangle.fill")
                            .font(.system(size: 46, weight: .semibold))
                            .foregroundColor(gate.killed ? .red : .orange)
                        Text(gate.killed ? "NGỪNG HOẠT ĐỘNG" : "PHIÊN BẢN CŨ")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundColor(.white)
                        Text(gate.message.isEmpty
                             ? (gate.killed
                                ? "Bản này đã ngừng hoạt động."
                                : "Bạn đang sử dụng phiên bản cũ. Vui lòng tải bản mới nhất để tiếp tục!")
                             : gate.message)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                        if !gate.killed {
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
                        } else {
                            Text("Cảm ơn bạn đã sử dụng!")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .padding(26)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke((gate.killed ? Color.red : Color.orange).opacity(0.5), lineWidth: 1)
                    )
                    .padding(26)
                }
                .transition(.opacity)
                .zIndex(999)
            }
        }
    }
}
