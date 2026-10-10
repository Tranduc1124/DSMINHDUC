import Foundation
import UIKit

/// Where the BolaMinhDuc web panel lives (bola-server on your VPS).
enum ServerConfig {
    /// Domain VPS đã deploy sẵn — đổi nếu bạn chuyển server.
    static let base = "https://ds.tphat.store"

    /// ID thiết bị dùng để bind license (ổn định theo vendor).
    static var deviceId: String {
        if let v = UIDevice.current.identifierForVendor?.uuidString { return v }
        return "unknown-device"
    }
}
