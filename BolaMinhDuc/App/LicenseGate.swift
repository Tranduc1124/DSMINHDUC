import Foundation
import UIKit

/// Cổng license — SDK Tserver 2.1.3 (activation-terminal).
///
/// Chống bypass màn key (nhiều lớp):
/// 1) `authSeal` chỉ set trong callback SDK thật (hash key|pkg|product)
/// 2) `serverUnlocked` chỉ set sau activate server OK (hoặc offline grace)
/// 3) `canEnterApp` = cả 3 điều kiện — SwiftUI / inject / install đều dùng cái này
/// 4) Watchdog định kỳ gọi `revalidate()` — mất điều kiện → kéo về màn key
final class LicenseGate: ObservableObject {
    static let shared = LicenseGate()

    enum State: Equatable {
        case starting
        case needKey
        case authorized
    }

    @Published var state: State = .starting
    /// Cờ UI duy nhất để hiện ContentView — KHÔNG set tay ngoài afterAuthorized.
    @Published private(set) var canEnterApp: Bool = false
    @Published var statusText: String = ""
    @Published var remainingText: String = ""
    @Published var busy = false
    @Published var errorText: String = ""

    /// Unix time khi lease hết hạn (0 = chưa biết).
    var leaseExpiryUnix: Int = 0

    /// Seal chống bypass: chỉ set trong onAuthorized callback thật của SDK.
    private(set) var authSeal: UInt64 = 0
    /// Server đã xác nhận thiết bị (activate OK).
    private(set) var serverUnlocked: Bool = false

    private var started = false
    private var activated = false
    private var watchdog: Timer?

    func start() {
        guard !started else { return }
        started = true

        // KEYLESS BUILD: no SDK, no server, no key screen.
        if !AppConfig.requireKey {
            unlockKeyless()
            return
        }

        TserverForceLoadNativeUiPacks()
        APIClientConfigure(Self.packageToken)

        APIClient.startAuthorization({ [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.errorText = ""
                self.beginAuthorizedFlow()
            }
        }, onRevoked: { [weak self] in
            DispatchQueue.main.async {
                self?.lockOut(reason: "Key hết hạn hoặc bị thu hồi — nhập key mới.")
            }
        }, onTerminal: { [weak self] res in
            NSLog("tserver terminal: %@", String(describing: res))
            DispatchQueue.main.async {
                guard let self = self else { return }
                let st = (res["status"] as? String) ?? ""
                let msg = (res["message"] as? String) ?? ""
                self.statusText = st
                if !msg.isEmpty { self.errorText = msg }
                if !self.canEnterApp {
                    self.state = .needKey
                }
            }
        })

        startWatchdog()
    }

    /// Key hiện tại (SDK giữ lease).
    var licenseKey: String {
        if !AppConfig.requireKey { return AppConfig.keylessKey }
        return APIClient.currentKeyText()
    }

    /// Session local hợp lệ (SDK + seal) — chưa đủ để vào app.
    var isSessionValid: Bool {
        if !AppConfig.requireKey { return true }
        return sessionProbeA() && sessionProbeB()
    }

    /// Package token theo target.
    static var packageToken: String {
        if let t = Bundle.main.object(forInfoDictionaryKey: "TserverPkgToken") as? String {
            let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty && !s.contains("REPLACE") { return s }
        }
        return "pkg_6yNT9gnfWl9NjBw4vZw80CW9INCCUsNL"
    }

    static var productId: String {
        let v = (Bundle.main.object(forInfoDictionaryKey: "BolaProduct") as? String) ?? "bola"
        let s = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "bola" : s
    }

    static var offlineMaxDays: Int {
        return (Bundle.main.object(forInfoDictionaryKey: "BolaOfflineMaxDays") as? Int) ?? 0
    }

    /// Kéo về màn key — xoá mọi cờ unlock.
    func lockOut(reason: String? = nil) {
        authSeal = 0
        serverUnlocked = false
        activated = false
        leaseExpiryUnix = 0
        canEnterApp = false
        state = .needKey
        statusText = "Lease"
        if let reason, !reason.isEmpty {
            errorText = reason
        }
    }

    /// Gọi từ watchdog / ContentView — mất điều kiện thì lockOut.
    @discardableResult
    func revalidate() -> Bool {
        if !AppConfig.requireKey {
            if !canEnterApp { unlockKeyless() }
            return true
        }
        let ok = evaluateEnter()
        if canEnterApp != ok {
            if ok {
                canEnterApp = true
                state = .authorized
            } else if canEnterApp {
                lockOut(reason: "Phiên key không hợp lệ — nhập lại key.")
            }
        }
        return ok
    }

    // MARK: - private

    /// KEYLESS: set every unlock flag without the SDK.
    private func unlockKeyless() {
        authSeal = 1
        serverUnlocked = true
        activated = true
        leaseExpiryUnix = 0
        canEnterApp = true
        state = .authorized
        statusText = "Keyless"
        remainingText = ""
        errorText = ""
    }

    /// Hai probe khác nhau (cùng logic) — patch 1 chỗ `return true` chưa đủ.
    private func sessionProbeA() -> Bool {
        guard state == .authorized || canEnterApp || authSeal != 0 else { return false }
        let k = licenseKey
        guard !k.isEmpty, authSeal != 0 else { return false }
        return authSeal == Self.computeSeal(key: k)
    }

    private func sessionProbeB() -> Bool {
        let k = licenseKey
        guard !k.isEmpty else { return false }
        let expected = Self.computeSeal(key: k)
        return authSeal != 0 && authSeal == expected && expected != 0
    }

    private func evaluateEnter() -> Bool {
        let k = licenseKey
        guard !k.isEmpty else { return false }
        guard authSeal != 0, authSeal == Self.computeSeal(key: k) else { return false }
        guard serverUnlocked else { return false }
        if leaseExpiryUnix > 0, Int(Date().timeIntervalSince1970) >= leaseExpiryUnix {
            return false
        }
        return true
    }

    private static func computeSeal(key: String) -> UInt64 {
        let raw = "\(key)|\(packageToken)|\(productId)"
        var h: UInt64 = 0xcbf29ce484222325
        for b in raw.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        // salt thứ 2 — đổi công thức nhẹ so với bản seal cũ
        h ^= 0x9e3779b97f4a7c15
        return h == 0 ? 1 : h
    }

    private func beginAuthorizedFlow() {
        remainingText = APIClient.currentKeyRemainingText()
        let k = licenseKey
        guard !k.isEmpty else {
            lockOut(reason: "SDK không trả key — thử lại.")
            return
        }
        authSeal = Self.computeSeal(key: k)
        if let info = APIClient.currentKeyInfo() {
            NSLog("tserver key info: %@", String(describing: info))
            if let rem = info["remainingSeconds"] as? NSNumber, rem.intValue > 0 {
                leaseExpiryUnix = Int(Date().timeIntervalSince1970) + rem.intValue
            }
        }

        // Chưa mở UI — chờ server activate (hoặc offline grace).
        state = .starting
        statusText = "Auth"
        errorText = ""

        let allowOffline = Self.offlineMaxDays > 0
        PatchClient.activate(license: k, device: ServerConfig.deviceId) { [weak self] ok, msg in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if ok {
                    self.serverUnlocked = true
                    self.activated = true
                    self.state = .authorized
                    self.canEnterApp = self.evaluateEnter()
                    if !self.canEnterApp {
                        self.lockOut(reason: "Seal không khớp — nhập lại key.")
                    }
                } else if allowOffline, self.sessionProbeB() {
                    // IntexX: cho vào tạm khi mất mạng
                    self.serverUnlocked = true
                    self.state = .authorized
                    self.canEnterApp = self.evaluateEnter()
                    NSLog("server activate failed (offline grace): %@", msg)
                } else {
                    self.lockOut(reason: msg.isEmpty
                                 ? "Không xác thực được server — kiểm tra mạng / key."
                                 : msg)
                }
            }
        }
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.canEnterApp || self.state == .authorized {
                _ = self.revalidate()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
    }
}
