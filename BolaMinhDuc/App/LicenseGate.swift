import Foundation
import UIKit

/// Cổng license — SDK Tserver 2.1.3 (activation-terminal), gói tối giản:
/// - App CHỈ CHỜ; bảng nhập key là của hệ thống (SDK/UI pack tự hiện).
/// - onAuthorized → vào giao diện chính; onRevoked → quay về màn chờ.
/// - Trước khi xác thực BẮT BUỘC phải nạp package token bằng
///   APIClientConfigure(...) — thiếu bước này SDK báo
///   "Thiếu cấu hình xác thực." (missing_auth_config) và không gửi request nào.
final class LicenseGate: ObservableObject {
    static let shared = LicenseGate()

    enum State: Equatable {
        case starting
        case needKey
        case authorized
    }

    @Published var state: State = .starting
    @Published var statusText: String = ""
    @Published var remainingText: String = ""
    @Published var busy = false
    @Published var errorText: String = ""

    /// Unix time khi lease hết hạn (0 = chưa biết) — gửi lên server để patch
    /// mang đúng hạn của KEY (thay vì luôn 30 ngày).
    var leaseExpiryUnix: Int = 0

    private var started = false
    private var activated = false

    func start() {
        guard !started else { return }
        started = true

        // Nạp UI pack native của SDK (bảng nhập key / gate UI) — cần cho app sideload.
        TserverForceLoadNativeUiPacks()

        // BẮT BUỘC: nạp package token trước khi xác thực (mỗi bản 1 pkg).
        APIClientConfigure(Self.packageToken)

        APIClient.startAuthorization({ [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.state = .authorized
                self.errorText = ""
                self.afterAuthorized()
            }
        }, onRevoked: { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.state = .needKey
                self.statusText = "Lease"
                self.errorText = "Key hết hạn hoặc bị thu hồi — nhập key mới."
            }
        }, onTerminal: { [weak self] res in
            NSLog("tserver terminal: %@", String(describing: res))
            DispatchQueue.main.async {
                guard let self = self else { return }
                let st = (res["status"] as? String) ?? ""
                let msg = (res["message"] as? String) ?? ""
                self.statusText = st
                if !msg.isEmpty { self.errorText = msg }
                // terminal = lỗi cuối của luồng kích hoạt (key sai, hết hạn,
                // bảo trì, thiếu cấu hình…) — vẫn ở màn chờ xác thực.
                if self.state != .authorized { self.state = .needKey }
            }
        })
    }

    /// Key hiện tại (SDK giữ lease; app dùng cho các API server patch).
    var licenseKey: String {
        return APIClient.currentKeyText()
    }

    /// Package token theo target (BolaMinhDuc vs IntexX).
    static var packageToken: String {
        if let t = Bundle.main.object(forInfoDictionaryKey: "TserverPkgToken") as? String {
            let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty && !s.contains("REPLACE") { return s }
        }
        return "pkg_6yNT9gnfWl9NjBw4vZw80CW9INCCUsNL"
    }

    /// id sản phẩm cho kill-switch server ("bola" / "intexx").
    static var productId: String {
        let v = (Bundle.main.object(forInfoDictionaryKey: "BolaProduct") as? String) ?? "bola"
        let s = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "bola" : s
    }

    /// Số ngày tối đa được phép không liên lạc được server (0 = không giới hạn).
    static var offlineMaxDays: Int {
        return (Bundle.main.object(forInfoDictionaryKey: "BolaOfflineMaxDays") as? Int) ?? 0
    }

    private func afterAuthorized() {
        remainingText = APIClient.currentKeyRemainingText()
        if let info = APIClient.currentKeyInfo() {
            NSLog("tserver key info: %@", String(describing: info))
            // hạn còn lại của key → đóng vào patch (server cap 30 ngày).
            if let rem = info["remainingSeconds"] as? NSNumber, rem.intValue > 0 {
                leaseExpiryUnix = Int(Date().timeIntervalSince1970) + rem.intValue
            }
        }
        // đăng ký thiết bị với server patch (một lần / phiên)
        guard !activated else { return }
        activated = true
        PatchClient.activate(license: licenseKey, device: ServerConfig.deviceId) { ok, msg in
            if !ok { NSLog("server activate failed: %@", msg) }
        }
    }
}
