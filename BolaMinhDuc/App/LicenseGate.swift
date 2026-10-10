import Foundation
import UIKit

/// Cổng license: chưa nhập key đúng — chỉ hiện màn hình nhập key,
/// vào giao diện chính sau khi Tserver xác nhận (lease hợp lệ).
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

    private var started = false
    private var activated = false

    func start() {
        guard !started else { return }
        started = true

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.TserverStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            // LƯU Ý: bản .a SDK hiện tại KHÔNG export symbol chuỗi
            // TserverStatusStringUserInfoKey — dùng key enum (NSNumber) thay thế.
            var typed: TserverStatusCode = .unknown
            if let n = note.userInfo?[TserverStatusEnumUserInfoKey] as? NSNumber,
               let t = TserverStatusCode(rawValue: n.intValue) {
                typed = t
            } else if let res = note.userInfo?[TserverResultUserInfoKey] as? [String: Any],
                      let st = res["status"] as? String {
                typed = TserverStatusCodeFromString(st)
            }
            self.statusText = TserverStatusCodeString(typed)
            if TserverStatusCodeIsValid(typed) {
                self.state = .authorized
                self.afterAuthorized()
            } else {
                // needKey / expired / revoked / device mismatch / maintenance… -> màn key
                self.state = .needKey
            }
        }

        APIClient.startAuthorization({ [weak self] in
            self?.state = .authorized
            self?.afterAuthorized()
        }, onRevoked: { [weak self] in
            self?.state = .needKey
        }, onTerminal: { res in
            NSLog("tserver terminal: %@", String(describing: res))
        })
    }

    /// Nhập key từ màn hình đầu tiên.
    func confirm(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        busy = true
        errorText = ""
        APIClient.confirmKey(k, success: { [weak self] _ in
            DispatchQueue.main.async {
                self?.busy = false
                self?.state = .authorized
                self?.afterAuthorized()
            }
        }, failure: { [weak self] res in
            DispatchQueue.main.async {
                self?.busy = false
                let st = (res["status"] as? String) ?? ""
                self?.errorText = st.isEmpty ? "Key không hợp lệ hoặc đã hết hạn." : "Key lỗi: \(st)"
            }
        })
    }

    /// Key hiện tại (SDK giữ lease; app dùng cho các API server patch).
    var licenseKey: String {
        return APIClient.currentKeyText()
    }

    private func afterAuthorized() {
        remainingText = APIClient.currentKeyRemainingText()
        if let info = APIClient.currentKeyInfo() {
            NSLog("tserver key info: %@", String(describing: info))
        }
        // đăng ký thiết bị với server patch (một lần / phiên)
        guard !activated else { return }
        activated = true
        PatchClient.activate(license: licenseKey, device: ServerConfig.deviceId) { ok, msg in
            if !ok { NSLog("server activate failed: %@", msg) }
        }
    }
}
